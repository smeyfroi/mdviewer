import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var isDropTargeted = false
    @FocusState private var findFieldIsFocused: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                appToolbar

                Divider()

                if workspace.tabs.isEmpty {
                    EmptyWorkspaceView(openAction: workspace.openPanel)
                } else {
                    DocumentTabStrip()

                    Divider()

                    if let selectedTabIndex = workspace.selectedTabIndex {
                        MarkdownPane(tab: $workspace.tabs[selectedTabIndex])
                    } else {
                        EmptyWorkspaceView(openAction: workspace.openPanel)
                    }
                }
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [9, 6]))
                    .padding(18)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            workspace.handleDrop(providers)
        }
        .onChange(of: workspace.findFocusRequest) {
            findFieldIsFocused = true
        }
    }

    private var appToolbar: some View {
        HStack(spacing: 10) {
            outlineToggle
            documentActionGroup

            Spacer(minLength: 24)

            previewControlGroup
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var previewControlGroup: some View {
        HStack(spacing: 10) {
            zoomGroup
            styleGroup
        }
        .labelStyle(.iconOnly)
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var outlineToggle: some View {
        Toggle(isOn: outlineBinding) {
            Label("Outline", systemImage: "sidebar.left")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .disabled(!workspace.hasActiveDocument)
        .accessibilityLabel("Outline")
        .help(workspace.isOutlineVisible ? "Hide document outline" : "Show document outline")
    }

    private var documentActionGroup: some View {
        HStack(spacing: 10) {
            documentButtons
            findGroup
        }
        .labelStyle(.iconOnly)
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var documentButtons: some View {
        ControlGroup {
            Button(action: workspace.openPanel) {
                Label("Open", systemImage: "folder")
            }
            .accessibilityLabel("Open Markdown Files")
            .help("Open Markdown files")

            Button(action: workspace.reloadActiveDocument) {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(!workspace.canUseActiveFileCommands)
            .accessibilityLabel("Reload from Disk")
            .help("Reload from disk")

            Button(action: workspace.saveActiveDocument) {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(!workspace.canSaveActiveDocument)
            .accessibilityLabel("Save")
            .help("Save the active document")

            Toggle(isOn: editModeBinding) {
                Label("Edit", systemImage: "pencil")
            }
            .toggleStyle(.button)
            .disabled(!workspace.hasActiveDocument)
            .accessibilityLabel("Edit")
            .help(workspace.editMode ? "Hide editor" : "Show editor")
        }
    }

    private var findGroup: some View {
        HStack(spacing: 8) {
            findField
            findCount
        }
    }

    private var findField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Find", text: $workspace.findQuery)
                .textFieldStyle(.plain)
                .focused($findFieldIsFocused)
                .disabled(!workspace.hasActiveDocument)
                .accessibilityLabel("Find")
        }
        .padding(.horizontal, 8)
        .frame(width: 180, height: 26)
        .background(.quaternary.opacity(0.75), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
        .help("Find in preview")
    }

    @ViewBuilder
    private var findCount: some View {
        if !findResultText.isEmpty {
            Text(findResultText)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel("Find Result Count")
                .accessibilityValue(findResultText)
                .help("Matching results")
        }
    }

    private var zoomGroup: some View {
        HStack(spacing: 4) {
            Button(action: workspace.zoomOut) {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .disabled(!workspace.hasActiveDocument)
            .accessibilityLabel("Zoom Out")
            .help("Zoom out")

            Text(workspace.zoomLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46)
                .accessibilityLabel("Zoom")
                .help("Current zoom: \(workspace.zoomLabel)")

            Button(action: workspace.zoomIn) {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .disabled(!workspace.hasActiveDocument)
            .accessibilityLabel("Zoom In")
            .help("Zoom in")
        }
    }

    private var styleGroup: some View {
        Picker("Style", selection: themeBinding) {
            ForEach(MarkdownTheme.allCases) { theme in
                Text(theme.displayName).tag(theme)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 128)
        .disabled(!workspace.hasActiveDocument)
        .accessibilityLabel("Preview Style")
        .help("Choose preview style")
    }

    private var findResultText: String {
        guard !workspace.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        if workspace.findResultCount == 1 {
            return "1 match"
        }
        return "\(workspace.findResultCount) matches"
    }

    private var editModeBinding: Binding<Bool> {
        Binding(
            get: { workspace.editMode },
            set: { workspace.setEditMode($0) }
        )
    }

    private var themeBinding: Binding<MarkdownTheme> {
        Binding(
            get: { workspace.theme },
            set: { workspace.setTheme($0) }
        )
    }

    private var outlineBinding: Binding<Bool> {
        Binding(
            get: { workspace.isOutlineVisible },
            set: { workspace.setOutlineVisible($0) }
        )
    }

}

private struct EmptyWorkspaceView: View {
    let openAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Drop Markdown")
                    .font(.title2.weight(.semibold))

                Text("Open or drop files and folders to begin.")
                    .foregroundStyle(.secondary)
            }

            Button(action: openAction) {
                Label("Open Files", systemImage: "folder")
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DocumentTabStrip: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(workspace.tabs) { tab in
                    DocumentTabItem(
                        tab: tab,
                        isSelected: tab.id == workspace.selectedTabID
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open Documents")
    }
}

private struct DocumentTabItem: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var isHovering = false

    let tab: MarkdownTab
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            closeButton

            statusIcon

            Text(tab.title)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .frame(width: 190, height: 28)
        .background(tabBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(tabBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture {
            workspace.selectTab(tab.id)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var closeButton: some View {
        Button {
            workspace.closeTab(tab.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9.5, weight: .bold))
                .frame(width: 18, height: 18)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(isSelected || isHovering ? 1 : 0.45)
        .background(closeButtonBackground, in: Circle())
        .accessibilityLabel("Close \(tab.title)")
        .help("Close \(tab.title)")
    }

    private var closeButtonBackground: Color {
        isHovering ? Color(nsColor: .quaternaryLabelColor).opacity(0.24) : .clear
    }

    @ViewBuilder
    private var statusIcon: some View {
        if tab.isDirty {
            Circle()
                .fill(Color(nsColor: .controlAccentColor))
                .frame(width: 6, height: 6)
                .accessibilityLabel("Unsaved")
        } else {
            Image(systemName: "doc.richtext")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.primary.opacity(0.72) : Color.secondary.opacity(0.72))
                .accessibilityHidden(true)
        }
    }

    private var tabBackground: Color {
        if isSelected {
            return Color(nsColor: .controlAccentColor).opacity(0.18)
        }
        if isHovering {
            return Color(nsColor: .quaternaryLabelColor).opacity(0.18)
        }
        return .clear
    }

    private var tabBorder: Color {
        if isSelected {
            return Color(nsColor: .controlAccentColor).opacity(0.42)
        }
        if isHovering {
            return Color(nsColor: .separatorColor).opacity(0.45)
        }
        return .clear
    }
}

private struct MarkdownPane: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Binding var tab: MarkdownTab

    var body: some View {
        let document = workspace.renderedDocument(for: tab)

        VStack(spacing: 0) {
            HSplitView {
                if workspace.isOutlineVisible && !document.headings.isEmpty {
                    OutlineSidebar(headings: document.headings) { heading in
                        workspace.scrollToHeading(heading, in: tab)
                    }
                }

                if workspace.editMode {
                    HSplitView {
                        editor
                            .frame(minWidth: 280)

                        preview(document)
                            .frame(minWidth: 360)
                    }
                } else {
                    preview(document)
                        .frame(minWidth: 420)
                }
            }

            Divider()

            DocumentStatusBar(tab: tab, headingCount: document.headings.count)
        }
    }

    private var editor: some View {
        TextEditor(text: $tab.markdown)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: tab.markdown) {
                workspace.markDirty(tab.id)
            }
    }

    private func preview(_ document: RenderedMarkdown) -> some View {
        MarkdownWebView(
            html: document.html,
            baseURL: tab.url?.deletingLastPathComponent(),
            zoomScale: workspace.zoomScale,
            findQuery: workspace.findQuery,
            scrollRequest: workspace.scrollRequest?.tabID == tab.id ? workspace.scrollRequest : nil,
            onFindResult: { count in
                workspace.updateFindResultCount(count)
            }
        )
        .id(tab.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct OutlineSidebar: View {
    let headings: [MarkdownHeading]
    let action: (MarkdownHeading) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Outline", systemImage: "list.bullet.indent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(headings) { heading in
                        Button {
                            action(heading)
                        } label: {
                            Text(heading.title)
                                .font(.system(size: 12.5, weight: heading.level <= 2 ? .semibold : .regular))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5)
                                .padding(.leading, CGFloat(max(0, heading.level - 1) * 12) + 10)
                                .padding(.trailing, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 190, idealWidth: 220, maxWidth: 280)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct DocumentStatusBar: View {
    let tab: MarkdownTab
    let headingCount: Int

    var body: some View {
        HStack(spacing: 10) {
            if tab.isDirty {
                Label("Edited", systemImage: "circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.orange, .orange)
            }

            Text("\(wordCount) words")
            Text("\(lineCount) lines")

            if headingCount > 0 {
                Text("\(headingCount) headings")
            }

            Spacer(minLength: 16)

            if let fileSizeText {
                Text(fileSizeText)
            }

            if let modifiedText {
                Text("Modified \(modifiedText)")
            }

            if let path = tab.filePath {
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 27)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var wordCount: Int {
        tab.markdown
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private var lineCount: Int {
        max(1, tab.markdown.components(separatedBy: .newlines).count)
    }

    private var fileSizeText: String? {
        guard let fileSize = tab.fileSize else { return nil }
        return Self.byteFormatter.string(fromByteCount: fileSize)
    }

    private var modifiedText: String? {
        guard let date = tab.fileModificationDate else { return nil }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
