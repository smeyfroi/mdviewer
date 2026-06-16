import AppKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum MarkdownTheme: String, CaseIterable, Codable, Identifiable {
    case native
    case github
    case manuscript
    case night

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .native: "Native"
        case .github: "GitHub"
        case .manuscript: "Manuscript"
        case .night: "Night"
        }
    }

    var filename: String { "\(rawValue).css" }
}

struct MarkdownTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var url: URL?
    var bookmarkData: Data?
    var markdown: String
    var isDirty: Bool
    var errorMessage: String?
    var fileModificationDate: Date?
    var fileSize: Int64?

    var filePath: String? {
        url?.path
    }
}

struct MarkdownScrollRequest: Equatable {
    let id = UUID()
    let tabID: UUID
    let anchorID: String
}

struct RecentDocument: Identifiable, Equatable {
    let url: URL

    var id: String { url.path }
    var title: String { url.lastPathComponent }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var tabs: [MarkdownTab] = []
    @Published var selectedTabID: UUID?
    @Published private(set) var zoomScale: Double = 1.0
    @Published private(set) var theme: MarkdownTheme = .native
    @Published private(set) var editMode = false
    @Published private(set) var isOutlineVisible = false
    @Published var isFindVisible = false
    @Published var findQuery = ""
    @Published private(set) var findResultCount = 0
    @Published private(set) var scrollRequest: MarkdownScrollRequest?
    @Published private(set) var recentDocuments: [RecentDocument] = []

    private let supportedExtensions = Set(["md", "markdown", "mdown", "mkd"])
    private var hasRestored = false
    private var pendingSave: DispatchWorkItem?

    var canSaveActiveDocument: Bool {
        guard let tab = activeTab else { return false }
        return tab.url != nil && tab.isDirty
    }

    var hasActiveDocument: Bool {
        activeTab != nil
    }

    var canUseActiveFileCommands: Bool {
        activeTab?.url != nil
    }

    var zoomLabel: String {
        "\(Int((zoomScale * 100).rounded()))%"
    }

    private var activeTab: MarkdownTab? {
        guard let index = activeTabIndex else { return nil }
        return tabs[index]
    }

    private var activeTabIndex: Int? {
        guard let selectedTabID else { return tabs.isEmpty ? nil : 0 }
        return tabs.firstIndex { $0.id == selectedTabID }
    }

    func restoreIfNeeded(restoringTabs: Bool = true) {
        guard !hasRestored else { return }
        hasRestored = true

        guard let data = try? Data(contentsOf: workspaceFileURL),
              let snapshot = try? JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
        else { return }

        theme = snapshot.theme
        zoomScale = clampZoom(snapshot.zoomScale)
        editMode = snapshot.editMode
        isOutlineVisible = snapshot.isOutlineVisible ?? false
        if restoringTabs {
            tabs = snapshot.tabs.compactMap(restoreTab)
            selectedTabID = tabs.contains { $0.id == snapshot.selectedTabID } ? snapshot.selectedTabID : tabs.first?.id
        }
        refreshRecentDocuments()
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = markdownContentTypes
        panel.message = "Choose Markdown files or folders"

        guard panel.runModal() == .OK else { return }
        open(urls: panel.urls)
    }

    func open(urls: [URL]) {
        let markdownURLs = expandedMarkdownURLs(from: urls)
        guard !markdownURLs.isEmpty else { return }

        for url in markdownURLs {
            let standardized = url.standardizedFileURL
            noteRecentDocument(standardized)

            if let existing = tabs.first(where: { $0.url?.standardizedFileURL == standardized }) {
                selectedTabID = existing.id
                continue
            }

            tabs.append(loadTab(from: standardized))
            selectedTabID = tabs.last?.id
        }

        refreshRecentDocuments()
        saveWorkspace()
    }

    func openRecentDocument(_ recentDocument: RecentDocument) {
        open(urls: [resolvedRecentURL(for: recentDocument.url)])
    }

    func clearRecentDocuments() {
        NSDocumentController.shared.clearRecentDocuments(self)
        clearRecentBookmarks()
        refreshRecentDocuments()
    }

    func refreshRecentDocuments() {
        recentDocuments = recentBookmarks().keys
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter(isSupportedMarkdown)
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            .map(RecentDocument.init)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let itemURL = item as? URL {
                    url = itemURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }

                guard let url else { return }
                Task { @MainActor in
                    self?.open(urls: [url])
                }
            }
        }

        return accepted
    }

    func closeActiveTab() {
        guard let index = activeTabIndex else { return }
        let tab = tabs[index]

        guard confirmCloseIfNeeded(tab) else { return }

        tabs.remove(at: index)
        if tabs.isEmpty {
            selectedTabID = nil
        } else if index < tabs.count {
            selectedTabID = tabs[index].id
        } else {
            selectedTabID = tabs.last?.id
        }
        saveWorkspace()
    }

    func saveActiveDocument() {
        guard let index = activeTabIndex,
              let url = tabs[index].url
        else { return }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try tabs[index].markdown.write(to: url, atomically: true, encoding: .utf8)
            removeMDViewerQuarantineAttribute(from: url)
            tabs[index].isDirty = false
            tabs[index].errorMessage = nil
            tabs[index].bookmarkData = makeBookmark(for: url)
            let attributes = fileAttributes(for: url)
            tabs[index].fileModificationDate = attributes.modified
            tabs[index].fileSize = attributes.size
            saveWorkspace()
        } catch {
            tabs[index].errorMessage = error.localizedDescription
            showError("Unable to save \(tabs[index].title)", detail: error.localizedDescription)
        }
    }

    func reloadActiveDocument() {
        guard let index = activeTabIndex,
              let url = tabs[index].url
        else { return }

        if tabs[index].isDirty && !confirmDiscardChanges(for: tabs[index], action: "reload") {
            return
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        defer {
            removeMDViewerQuarantineAttribute(from: url)
        }

        do {
            tabs[index].markdown = try String(contentsOf: url, encoding: .utf8)
            tabs[index].isDirty = false
            tabs[index].errorMessage = nil
            tabs[index].title = url.lastPathComponent
            tabs[index].bookmarkData = makeBookmark(for: url)
            let attributes = fileAttributes(for: url)
            tabs[index].fileModificationDate = attributes.modified
            tabs[index].fileSize = attributes.size
            saveWorkspace()
        } catch {
            tabs[index].errorMessage = error.localizedDescription
            showError("Unable to reload \(tabs[index].title)", detail: error.localizedDescription)
        }
    }

    func revealActiveDocument() {
        guard let url = activeTab?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyActiveDocumentPath() {
        guard let path = activeTab?.filePath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func copyRenderedHTML() {
        guard let tab = activeTab else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(renderedDocument(for: tab).html, forType: .string)
    }

    func markDirty(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if !tabs[index].isDirty {
            tabs[index].isDirty = true
        }
        scheduleWorkspaceSave()
    }

    func renderedDocument(for tab: MarkdownTab) -> RenderedMarkdown {
        let stylesheet = loadStylesheet(for: theme)
        return MarkdownRenderer.render(
            markdown: tab.markdown,
            title: tab.title,
            stylesheet: stylesheet,
            errorMessage: tab.errorMessage
        )
    }

    func renderedHTML(for tab: MarkdownTab) -> String {
        renderedDocument(for: tab).html
    }

    func setTheme(_ newTheme: MarkdownTheme) {
        theme = newTheme
        saveWorkspace()
    }

    func setEditMode(_ isEditing: Bool) {
        editMode = isEditing
        saveWorkspace()
    }

    func setOutlineVisible(_ isVisible: Bool) {
        isOutlineVisible = isVisible
        saveWorkspace()
    }

    func toggleFind() {
        isFindVisible.toggle()
        if !isFindVisible {
            findQuery = ""
            findResultCount = 0
        }
    }

    func updateFindResultCount(_ count: Int) {
        findResultCount = count
    }

    func scrollToHeading(_ heading: MarkdownHeading, in tab: MarkdownTab) {
        scrollRequest = MarkdownScrollRequest(tabID: tab.id, anchorID: heading.id)
    }

    func zoomIn() {
        zoomScale = clampZoom(zoomScale + 0.1)
        saveWorkspace()
    }

    func zoomOut() {
        zoomScale = clampZoom(zoomScale - 0.1)
        saveWorkspace()
    }

    func resetZoom() {
        zoomScale = 1.0
        saveWorkspace()
    }

    func saveWorkspace() {
        pendingSave?.cancel()

        let snapshot = WorkspaceSnapshot(
            tabs: tabs.map(SavedTab.init),
            selectedTabID: selectedTabID,
            zoomScale: zoomScale,
            theme: theme,
            editMode: editMode,
            isOutlineVisible: isOutlineVisible
        )

        do {
            try FileManager.default.createDirectory(
                at: workspaceDirectoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: workspaceFileURL, options: .atomic)
        } catch {
            assertionFailure("Unable to save workspace: \(error.localizedDescription)")
        }
    }

    private var markdownContentTypes: [UTType] {
        ["md", "markdown", "mdown", "mkd"].compactMap { UTType(filenameExtension: $0) }
    }

    private var workspaceDirectoryURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MDViewer", isDirectory: true)
    }

    private var workspaceFileURL: URL {
        workspaceDirectoryURL.appendingPathComponent("workspace.json")
    }

    private var recentBookmarksFileURL: URL {
        workspaceDirectoryURL.appendingPathComponent("recent-bookmarks.json")
    }

    private func isSupportedMarkdown(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func expandedMarkdownURLs(from urls: [URL]) -> [URL] {
        var markdownURLs: [URL] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            let didAccess = standardized.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    standardized.stopAccessingSecurityScopedResource()
                }
            }

            if isDirectory(standardized) {
                markdownURLs.append(contentsOf: markdownFiles(in: standardized))
            } else if isSupportedMarkdown(standardized) {
                markdownURLs.append(standardized)
            }
        }

        return Array(Set(markdownURLs)).sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func markdownFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            if isDirectory(url) {
                return nil
            }
            return isSupportedMarkdown(url) ? url.standardizedFileURL : nil
        }
    }

    private func loadTab(from url: URL) -> MarkdownTab {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        defer {
            removeMDViewerQuarantineAttribute(from: url)
        }

        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let attributes = fileAttributes(for: url)
            return MarkdownTab(
                id: UUID(),
                title: url.lastPathComponent,
                url: url,
                bookmarkData: makeBookmark(for: url),
                markdown: markdown,
                isDirty: false,
                errorMessage: nil,
                fileModificationDate: attributes.modified,
                fileSize: attributes.size
            )
        } catch {
            let attributes = fileAttributes(for: url)
            return MarkdownTab(
                id: UUID(),
                title: url.lastPathComponent,
                url: url,
                bookmarkData: makeBookmark(for: url),
                markdown: "# \(url.lastPathComponent)\n\nThe file could not be read.",
                isDirty: false,
                errorMessage: error.localizedDescription,
                fileModificationDate: attributes.modified,
                fileSize: attributes.size
            )
        }
    }

    private func restoreTab(_ saved: SavedTab) -> MarkdownTab? {
        let restoredURL = resolveURL(from: saved)
        let title = restoredURL?.lastPathComponent ?? saved.title
        var markdown = saved.draftMarkdown ?? ""
        var errorMessage: String?

        if saved.draftMarkdown == nil, let restoredURL {
            let didAccess = restoredURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    restoredURL.stopAccessingSecurityScopedResource()
                }
            }
            defer {
                removeMDViewerQuarantineAttribute(from: restoredURL)
            }

            do {
                markdown = try String(contentsOf: restoredURL, encoding: .utf8)
            } catch {
                markdown = "# \(title)\n\nThe restored file could not be read."
                errorMessage = error.localizedDescription
            }
        } else if restoredURL == nil {
            markdown = saved.draftMarkdown ?? "# \(title)\n\nThe restored file could not be found."
            errorMessage = "The saved bookmark or file path could not be resolved."
        }

        return MarkdownTab(
            id: saved.id,
            title: title,
            url: restoredURL,
            bookmarkData: saved.bookmarkData,
            markdown: markdown,
            isDirty: saved.isDirty,
            errorMessage: errorMessage,
            fileModificationDate: restoredURL.flatMap { fileAttributes(for: $0).modified },
            fileSize: restoredURL.flatMap { fileAttributes(for: $0).size }
        )
    }

    private func resolveURL(from saved: SavedTab) -> URL? {
        if let bookmarkData = saved.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }

        if let path = saved.path {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func noteRecentDocument(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        saveRecentBookmark(for: url)
        removeMDViewerQuarantineAttribute(from: url)
    }

    private func resolvedRecentURL(for url: URL) -> URL {
        let standardized = url.standardizedFileURL
        guard let bookmarkData = recentBookmarks()[standardized.path] else {
            return standardized
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return standardized
        }

        if isStale {
            saveRecentBookmark(for: resolvedURL)
        }

        return resolvedURL.standardizedFileURL
    }

    private func saveRecentBookmark(for url: URL) {
        guard let bookmarkData = makeBookmark(for: url) else { return }

        var bookmarks = recentBookmarks()
        bookmarks[url.standardizedFileURL.path] = bookmarkData

        do {
            try FileManager.default.createDirectory(
                at: workspaceDirectoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(bookmarks).write(to: recentBookmarksFileURL, options: .atomic)
        } catch {
            assertionFailure("Unable to save recent bookmarks: \(error.localizedDescription)")
        }
    }

    private func recentBookmarks() -> [String: Data] {
        guard let data = try? Data(contentsOf: recentBookmarksFileURL),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data)
        else { return [:] }

        return bookmarks
    }

    private func clearRecentBookmarks() {
        try? FileManager.default.removeItem(at: recentBookmarksFileURL)
    }

    private func loadStylesheet(for theme: MarkdownTheme) -> String {
        let resource = theme.rawValue
        if let url = Bundle.main.url(forResource: resource, withExtension: "css", subdirectory: "Styles"),
           let css = try? String(contentsOf: url, encoding: .utf8) {
            return css
        }

        return """
        body { font: -apple-system-body; margin: 0; }
        .markdown-body { max-width: 820px; margin: 0 auto; padding: 48px 56px; }
        """
    }

    private func fileAttributes(for url: URL) -> (modified: Date?, size: Int64?) {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return (nil, nil)
        }
        return (values.contentModificationDate, values.fileSize.map(Int64.init))
    }

    private func removeMDViewerQuarantineAttribute(from url: URL) {
        guard quarantineAttributeWasWrittenByMDViewer(at: url) else { return }

        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            quarantineAttributeName.withCString { attributeName in
                _ = removexattr(path, attributeName, 0)
            }
        }
    }

    private func quarantineAttributeWasWrittenByMDViewer(at url: URL) -> Bool {
        guard let value = extendedAttribute(named: quarantineAttributeName, at: url),
              let quarantineValue = String(data: value, encoding: .utf8)
        else { return false }

        let fields = quarantineValue.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 3 else { return false }
        return fields[2].localizedCaseInsensitiveCompare("MDViewer") == .orderedSame
    }

    private func extendedAttribute(named name: String, at url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }

            return name.withCString { attributeName -> Data? in
                let length = getxattr(path, attributeName, nil, 0, 0, 0)
                guard length > 0 else { return nil }

                let expectedLength = length
                var data = Data(count: expectedLength)
                let readLength = data.withUnsafeMutableBytes { buffer -> ssize_t in
                    guard let baseAddress = buffer.baseAddress else { return -1 }
                    return getxattr(path, attributeName, baseAddress, expectedLength, 0, 0)
                }

                guard readLength > 0 else { return nil }
                if readLength < data.count {
                    data.removeSubrange(Int(readLength)..<data.count)
                }
                return data
            }
        }
    }

    private func confirmCloseIfNeeded(_ tab: MarkdownTab) -> Bool {
        guard tab.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to \(tab.title)?"
        alert.informativeText = "Unsaved edits will be discarded if the tab is closed."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveActiveDocument()
            return activeTab?.isDirty == false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func confirmDiscardChanges(for tab: MarkdownTab, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Discard changes to \(tab.title)?"
        alert.informativeText = "Unsaved edits will be lost if you \(action) this document."
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func scheduleWorkspaceSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveWorkspace()
        }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    private func clampZoom(_ value: Double) -> Double {
        min(2.6, max(0.55, value))
    }
}

private let quarantineAttributeName = "com.apple.quarantine"

private struct WorkspaceSnapshot: Codable {
    var tabs: [SavedTab]
    var selectedTabID: UUID?
    var zoomScale: Double
    var theme: MarkdownTheme
    var editMode: Bool
    var isOutlineVisible: Bool?
}

private struct SavedTab: Codable {
    var id: UUID
    var title: String
    var path: String?
    var bookmarkData: Data?
    var draftMarkdown: String?
    var isDirty: Bool

    init(id: UUID, title: String, path: String?, bookmarkData: Data?, draftMarkdown: String?, isDirty: Bool) {
        self.id = id
        self.title = title
        self.path = path
        self.bookmarkData = bookmarkData
        self.draftMarkdown = draftMarkdown
        self.isDirty = isDirty
    }

    init(_ tab: MarkdownTab) {
        id = tab.id
        title = tab.title
        path = tab.filePath
        bookmarkData = tab.bookmarkData
        draftMarkdown = tab.isDirty ? tab.markdown : nil
        isDirty = tab.isDirty
    }
}
