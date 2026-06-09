import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var isDropTargeted = false
    @FocusState private var findFieldIsFocused: Bool

    var body: some View {
        ZStack {
            if workspace.tabs.isEmpty {
                EmptyWorkspaceView(openAction: workspace.openPanel)
            } else {
                TabView(selection: $workspace.selectedTabID) {
                    ForEach($workspace.tabs) { $tab in
                        MarkdownPane(tab: $tab)
                            .tabItem {
                                Label(tab.title, systemImage: tab.isDirty ? "doc.badge.ellipsis" : "doc.richtext")
                            }
                            .tag(Optional(tab.id))
                    }
                }
                .padding(.top, 1)
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
        .onChange(of: workspace.isFindVisible) {
            if workspace.isFindVisible {
                findFieldIsFocused = true
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button(action: workspace.openPanel) {
                    Label("Open", systemImage: "folder")
                }
                .accessibilityLabel("Open Markdown Files")
                .help("Open Markdown files")

                Button(action: workspace.closeActiveTab) {
                    Label("Close Tab", systemImage: "xmark")
                }
                .disabled(workspace.selectedTabID == nil)
                .accessibilityLabel("Close Tab")
                .help("Close the active tab")

                Divider()

                Button(action: workspace.reloadActiveDocument) {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(!workspace.canUseActiveFileCommands)
                .accessibilityLabel("Reload from Disk")
                .help("Reload from disk")

                Button(action: workspace.revealActiveDocument) {
                    Label("Reveal", systemImage: "finder")
                }
                .disabled(!workspace.canUseActiveFileCommands)
                .accessibilityLabel("Reveal in Finder")
                .help("Reveal in Finder")

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
                .disabled(workspace.selectedTabID == nil)
                .accessibilityLabel("Edit")
                .help(workspace.editMode ? "Hide editor" : "Show editor")
            }

            ToolbarItemGroup {
                Toggle(isOn: outlineBinding) {
                    Label("Outline", systemImage: "sidebar.left")
                }
                .toggleStyle(.button)
                .disabled(workspace.selectedTabID == nil)
                .accessibilityLabel("Outline")
                .help(workspace.isOutlineVisible ? "Hide document outline" : "Show document outline")

                Toggle(isOn: findVisibleBinding) {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .toggleStyle(.button)
                .disabled(workspace.selectedTabID == nil)
                .accessibilityLabel("Find")
                .help(workspace.isFindVisible ? "Hide find" : "Find in preview")
            }

            ToolbarItemGroup {
                Button(action: workspace.zoomOut) {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(workspace.selectedTabID == nil)
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
                .disabled(workspace.selectedTabID == nil)
                .accessibilityLabel("Zoom In")
                .help("Zoom in")
            }

            ToolbarItem {
                Picker("Style", selection: themeBinding) {
                    ForEach(MarkdownTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 148)
                .disabled(workspace.selectedTabID == nil)
                .accessibilityLabel("Preview Style")
                .help("Choose preview style")
            }

            if workspace.isFindVisible {
                ToolbarItemGroup {
                    TextField("Find", text: $workspace.findQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .focused($findFieldIsFocused)
                        .accessibilityLabel("Find")
                        .help("Find in preview")

                    if !findResultText.isEmpty {
                        Text(findResultText)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .frame(width: 96, alignment: .leading)
                            .background(.quaternary, in: Capsule())
                            .accessibilityLabel("Find Result Count")
                            .accessibilityValue(findResultText)
                            .help("Matching results")
                    }

                    Button {
                        workspace.toggleFind()
                    } label: {
                        Label("Close Find", systemImage: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Close Find")
                    .help("Close find")
                }
            }
        }
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

    private var findVisibleBinding: Binding<Bool> {
        Binding(
            get: { workspace.isFindVisible },
            set: { isVisible in
                if workspace.isFindVisible != isVisible {
                    workspace.toggleFind()
                }
            }
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
        NativeMarkdownPreview(
            tab: tab,
            document: document,
            zoomScale: workspace.zoomScale,
            theme: workspace.theme,
            findQuery: workspace.isFindVisible ? workspace.findQuery : "",
            scrollRequest: workspace.scrollRequest?.tabID == tab.id ? workspace.scrollRequest : nil,
            onFindResult: { count in
                workspace.updateFindResultCount(count)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct NativeMarkdownPreview: View {
    let tab: MarkdownTab
    let document: RenderedMarkdown
    let zoomScale: Double
    let theme: MarkdownTheme
    let findQuery: String
    let scrollRequest: MarkdownScrollRequest?
    let onFindResult: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style = NativePreviewStyle(theme: theme, colorScheme: colorScheme)
        let blocks = NativeMarkdownBlock.parse(tab.markdown, headings: document.headings)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(blocks) { block in
                        blockView(block, style: style)
                    }
                }
                .frame(maxWidth: style.contentWidth, alignment: .topLeading)
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, style.verticalPadding)
                .background(style.contentBackground)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.vertical, style.outerVerticalPadding)
            }
            .background(style.pageBackground)
            .onAppear {
                updateFindCount()
            }
            .onChange(of: tab.markdown) {
                updateFindCount()
            }
            .onChange(of: findQuery) {
                updateFindCount()
            }
            .onChange(of: scrollRequest) {
                guard let anchorID = scrollRequest?.anchorID else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(anchorID, anchor: .top)
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: NativeMarkdownBlock, style: NativePreviewStyle) -> some View {
        switch block.kind {
        case let .heading(level, title, anchorID):
            markdownText(title, style: style, baseSize: headingSize(for: level), weight: .semibold, foreground: style.text)
                .lineSpacing(2 * zoomScale)
                .padding(.top, level == 1 ? 0 : headingTopPadding(for: level))
                .padding(.bottom, 8 * zoomScale)
                .id(anchorID)

        case let .paragraph(text):
            markdownText(text, style: style, baseSize: 15.5, weight: .regular, foreground: style.text)
                .lineSpacing(5 * zoomScale)
                .padding(.bottom, 13 * zoomScale)

        case let .quote(text):
            markdownText(text, style: style, baseSize: 15, weight: .regular, foreground: style.mutedText)
                .lineSpacing(4 * zoomScale)
                .padding(.vertical, 10 * zoomScale)
                .padding(.horizontal, 14 * zoomScale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(style.quoteBackground)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(style.accent)
                        .frame(width: 3)
                }
                .padding(.bottom, 14 * zoomScale)

        case let .code(text):
            ScrollView(.horizontal) {
                Text(attributedText(for: text, style: style, foreground: style.text, parsesMarkdown: false))
                    .font(.system(size: 13.5 * zoomScale, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(14 * zoomScale)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(style.codeBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(style.border, lineWidth: 1)
            }
            .padding(.bottom, 15 * zoomScale)

        case let .unorderedList(items):
            listView(items: items, ordered: false, style: style)
                .padding(.bottom, 12 * zoomScale)

        case let .orderedList(items):
            listView(items: items, ordered: true, style: style)
                .padding(.bottom, 12 * zoomScale)

        case .rule:
            Rectangle()
                .fill(style.border)
                .frame(height: 1)
                .padding(.vertical, 18 * zoomScale)
        }
    }

    private func listView(items: [String], ordered: Bool, style: NativePreviewStyle) -> some View {
        VStack(alignment: .leading, spacing: 7 * zoomScale) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 9 * zoomScale) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.system(size: 15.5 * zoomScale, weight: .medium, design: style.fontDesign))
                        .foregroundStyle(style.mutedText)
                        .frame(width: ordered ? 28 * zoomScale : 16 * zoomScale, alignment: .trailing)

                    markdownText(item, style: style, baseSize: 15.5, weight: .regular, foreground: style.text)
                        .lineSpacing(4 * zoomScale)
                }
            }
        }
        .padding(.leading, 4 * zoomScale)
    }

    private func markdownText(
        _ text: String,
        style: NativePreviewStyle,
        baseSize: Double,
        weight: Font.Weight,
        foreground: Color
    ) -> Text {
        Text(attributedText(for: text, style: style, foreground: foreground))
            .font(.system(size: baseSize * zoomScale, weight: weight, design: style.fontDesign))
    }

    private func attributedText(
        for text: String,
        style: NativePreviewStyle,
        foreground: Color,
        parsesMarkdown: Bool = true
    ) -> AttributedString {
        var attributed: AttributedString
        if parsesMarkdown {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        } else {
            attributed = AttributedString(text)
        }

        attributed.foregroundColor = foreground
        applyFindHighlight(to: &attributed, style: style)
        return attributed
    }

    private func applyFindHighlight(to attributed: inout AttributedString, style: NativePreviewStyle) {
        let needle = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return }

        let plainText = String(attributed.characters)
        var searchStart = plainText.startIndex

        while searchStart < plainText.endIndex,
              let match = plainText.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<plainText.endIndex
              ) {
            let lowerOffset = plainText.distance(from: plainText.startIndex, to: match.lowerBound)
            let upperOffset = plainText.distance(from: plainText.startIndex, to: match.upperBound)
            let lowerBound = attributed.characters.index(attributed.startIndex, offsetBy: lowerOffset)
            let upperBound = attributed.characters.index(attributed.startIndex, offsetBy: upperOffset)

            attributed[lowerBound..<upperBound].backgroundColor = style.findHighlight
            attributed[lowerBound..<upperBound].foregroundColor = style.findText
            searchStart = match.upperBound
        }
    }

    private func updateFindCount() {
        onFindResult(Self.countMatches(in: tab.markdown, query: findQuery))
    }

    private static func countMatches(in text: String, query: String) -> Int {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return 0 }

        var count = 0
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private func headingSize(for level: Int) -> Double {
        switch level {
        case 1: 31
        case 2: 24
        case 3: 19
        case 4: 16.5
        default: 15
        }
    }

    private func headingTopPadding(for level: Int) -> Double {
        switch level {
        case 2: 25 * zoomScale
        case 3: 20 * zoomScale
        default: 16 * zoomScale
        }
    }
}

private struct NativePreviewStyle {
    let pageBackground: Color
    let contentBackground: Color
    let text: Color
    let mutedText: Color
    let accent: Color
    let border: Color
    let codeBackground: Color
    let quoteBackground: Color
    let findHighlight: Color
    let findText: Color
    let fontDesign: Font.Design
    let contentWidth: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let outerVerticalPadding: CGFloat

    init(theme: MarkdownTheme, colorScheme: ColorScheme) {
        let isDark = colorScheme == .dark

        switch theme {
        case .native:
            pageBackground = Color(nsColor: isDark ? NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1) : .windowBackgroundColor)
            contentBackground = Color(nsColor: isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1) : .textBackgroundColor)
            text = Color(nsColor: isDark ? .white : .labelColor)
            mutedText = Color(nsColor: .secondaryLabelColor)
            accent = Color(nsColor: .controlAccentColor)
            border = Color(nsColor: .separatorColor)
            codeBackground = Color(nsColor: isDark ? NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1) : NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1))
            quoteBackground = Color(nsColor: isDark ? NSColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1) : NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1))
            fontDesign = .default
            contentWidth = 860
            horizontalPadding = 58
            verticalPadding = 52
            outerVerticalPadding = 0

        case .github:
            pageBackground = Color(nsColor: isDark ? NSColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 1) : NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1))
            contentBackground = pageBackground
            text = Color(nsColor: isDark ? NSColor(red: 0.90, green: 0.93, blue: 0.96, alpha: 1) : NSColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1))
            mutedText = Color(nsColor: isDark ? NSColor(red: 0.55, green: 0.59, blue: 0.63, alpha: 1) : NSColor(red: 0.35, green: 0.39, blue: 0.43, alpha: 1))
            accent = Color(nsColor: isDark ? NSColor(red: 0.35, green: 0.65, blue: 1, alpha: 1) : NSColor(red: 0.04, green: 0.41, blue: 0.86, alpha: 1))
            border = Color(nsColor: isDark ? NSColor(red: 0.19, green: 0.22, blue: 0.25, alpha: 1) : NSColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1))
            codeBackground = Color(nsColor: isDark ? NSColor(red: 0.09, green: 0.11, blue: 0.14, alpha: 1) : NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1))
            quoteBackground = .clear
            fontDesign = .default
            contentWidth = 920
            horizontalPadding = 54
            verticalPadding = 48
            outerVerticalPadding = 0

        case .manuscript:
            pageBackground = Color(nsColor: isDark ? NSColor(red: 0.10, green: 0.09, blue: 0.08, alpha: 1) : NSColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1))
            contentBackground = Color(nsColor: isDark ? NSColor(red: 0.13, green: 0.12, blue: 0.11, alpha: 1) : NSColor(red: 1.00, green: 0.99, blue: 0.96, alpha: 1))
            text = Color(nsColor: isDark ? NSColor(red: 0.94, green: 0.91, blue: 0.86, alpha: 1) : NSColor(red: 0.15, green: 0.13, blue: 0.12, alpha: 1))
            mutedText = Color(nsColor: isDark ? NSColor(red: 0.72, green: 0.67, blue: 0.61, alpha: 1) : NSColor(red: 0.41, green: 0.38, blue: 0.35, alpha: 1))
            accent = Color(nsColor: isDark ? NSColor(red: 0.89, green: 0.64, blue: 0.41, alpha: 1) : NSColor(red: 0.49, green: 0.25, blue: 0.13, alpha: 1))
            border = Color(nsColor: isDark ? NSColor(red: 0.29, green: 0.26, blue: 0.22, alpha: 1) : NSColor(red: 0.85, green: 0.82, blue: 0.77, alpha: 1))
            codeBackground = Color(nsColor: isDark ? NSColor(red: 0.12, green: 0.11, blue: 0.10, alpha: 1) : NSColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1))
            quoteBackground = Color(nsColor: isDark ? NSColor(red: 0.17, green: 0.15, blue: 0.12, alpha: 1) : NSColor(red: 0.98, green: 0.95, blue: 0.91, alpha: 1))
            fontDesign = .serif
            contentWidth = 760
            horizontalPadding = 66
            verticalPadding = 62
            outerVerticalPadding = 0

        case .night:
            pageBackground = Color(nsColor: NSColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1))
            contentBackground = Color(nsColor: NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1))
            text = Color(nsColor: NSColor(red: 0.93, green: 0.95, blue: 0.97, alpha: 1))
            mutedText = Color(nsColor: NSColor(red: 0.61, green: 0.65, blue: 0.71, alpha: 1))
            accent = Color(nsColor: NSColor(red: 0.55, green: 0.78, blue: 1.00, alpha: 1))
            border = Color(nsColor: NSColor(red: 0.19, green: 0.21, blue: 0.25, alpha: 1))
            codeBackground = Color(nsColor: NSColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1))
            quoteBackground = Color(nsColor: NSColor(red: 0.12, green: 0.15, blue: 0.19, alpha: 1))
            fontDesign = .default
            contentWidth = 880
            horizontalPadding = 60
            verticalPadding = 54
            outerVerticalPadding = 0
        }

        findHighlight = Color(nsColor: NSColor(red: 1.00, green: 0.82, blue: 0.24, alpha: 0.95))
        findText = Color(nsColor: .black)
    }
}

private struct NativeMarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case heading(level: Int, title: String, anchorID: String)
        case paragraph(String)
        case quote(String)
        case code(String)
        case unorderedList([String])
        case orderedList([String])
        case rule
    }

    static func parse(_ markdown: String, headings: [MarkdownHeading]) -> [NativeMarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [NativeMarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0
        var headingIndex = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(NativeMarkdownBlock(kind: .paragraph(paragraph.joined(separator: " "))))
            paragraph.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = codeFence(in: trimmed) {
                flushParagraph()
                var code: [String] = []
                index += 1
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                        index += 1
                        break
                    }
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(NativeMarkdownBlock(kind: .code(code.joined(separator: "\n"))))
                continue
            }

            if let heading = heading(in: trimmed) {
                flushParagraph()
                let anchorID = headingIndex < headings.count ? headings[headingIndex].id : "section-\(headingIndex + 1)"
                headingIndex += 1
                blocks.append(NativeMarkdownBlock(kind: .heading(level: heading.level, title: heading.title, anchorID: anchorID)))
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                flushParagraph()
                blocks.append(NativeMarkdownBlock(kind: .rule))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoteLines.append(String(quoteLine.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(NativeMarkdownBlock(kind: .quote(quoteLines.joined(separator: "\n"))))
                continue
            }

            if let first = listItem(from: trimmed) {
                flushParagraph()
                var items: [String] = []
                while index < lines.count {
                    let itemLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let item = listItem(from: itemLine), item.ordered == first.ordered else { break }
                    items.append(item.text)
                    index += 1
                }
                blocks.append(NativeMarkdownBlock(kind: first.ordered ? .orderedList(items) : .unorderedList(items)))
                continue
            }

            paragraph.append(trimmed)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func heading(in line: String) -> (level: Int, title: String)? {
        var level = 0
        for character in line {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }

        guard (1...6).contains(level),
              line.dropFirst(level).first == " "
        else { return nil }

        return (level, String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces))
    }

    private static func codeFence(in line: String) -> String? {
        if line.hasPrefix("```") {
            return "```"
        }
        if line.hasPrefix("~~~") {
            return "~~~"
        }
        return nil
    }

    private static func listItem(from line: String) -> (ordered: Bool, text: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return (false, String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }

        var digits = ""
        for character in line {
            if character.isNumber {
                digits.append(character)
            } else {
                break
            }
        }

        guard !digits.isEmpty else { return nil }
        let remainder = line.dropFirst(digits.count)
        guard remainder.hasPrefix(". ") || remainder.hasPrefix(") ") else { return nil }
        return (true, String(remainder.dropFirst(2)).trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" } || compact.allSatisfy { $0 == "_" }
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
