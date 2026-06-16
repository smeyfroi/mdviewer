import AppKit
import SwiftUI

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        Window("MDViewer", id: "main") {
            ContentView()
                .environmentObject(workspace)
                .background {
                    WindowAccessor { window in
                        appDelegate.configureMainWindow(window)
                    }
                }
                .onAppear {
                    let launchURLs = appDelegate.attach(workspace: workspace)
                    workspace.restoreIfNeeded(restoringTabs: launchURLs.isEmpty)
                    if !launchURLs.isEmpty {
                        workspace.open(urls: launchURLs)
                    }
                    workspace.refreshRecentDocuments()
                }
                .onOpenURL { url in
                    appDelegate.open(urls: [url])
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    workspace.openPanel()
                }
                .keyboardShortcut("o")
            }

            CommandGroup(after: .newItem) {
                Button("Close Tab") {
                    workspace.closeActiveTab()
                }
                .keyboardShortcut("w")
                .disabled(!workspace.hasActiveDocument)

                Divider()

                Menu("Open Recent") {
                    if workspace.recentDocuments.isEmpty {
                        Button("No Recent Files") { }
                            .disabled(true)
                    } else {
                        ForEach(workspace.recentDocuments) { recentDocument in
                            Button(recentDocument.title) {
                                workspace.openRecentDocument(recentDocument)
                            }
                            .help(recentDocument.url.path)
                        }

                        Divider()

                        Button("Clear Menu") {
                            workspace.clearRecentDocuments()
                        }
                    }
                }
            }

            CommandGroup(after: .saveItem) {
                Button("Save") {
                    workspace.saveActiveDocument()
                }
                .keyboardShortcut("s")
                .disabled(!workspace.canSaveActiveDocument)

                Divider()

                Button("Reload from Disk") {
                    workspace.reloadActiveDocument()
                }
                .keyboardShortcut("r")
                .disabled(!workspace.canUseActiveFileCommands)

                Button("Reveal in Finder") {
                    workspace.revealActiveDocument()
                }
                .disabled(!workspace.canUseActiveFileCommands)

                Button("Copy File Path") {
                    workspace.copyActiveDocumentPath()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!workspace.canUseActiveFileCommands)
            }

            CommandGroup(after: .toolbar) {
                Button(workspace.isOutlineVisible ? "Hide Outline" : "Show Outline") {
                    workspace.setOutlineVisible(!workspace.isOutlineVisible)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!workspace.hasActiveDocument)
            }

            CommandMenu("Markdown") {
                Button(workspace.isFindVisible ? "Hide Find" : "Find") {
                    workspace.toggleFind()
                }
                .keyboardShortcut("f")
                .disabled(!workspace.hasActiveDocument)

                Divider()

                Button(workspace.editMode ? "Hide Editor" : "Show Editor") {
                    workspace.setEditMode(!workspace.editMode)
                }
                .keyboardShortcut("e")
                .disabled(!workspace.hasActiveDocument)

                Button("Copy Rendered HTML") {
                    workspace.copyRenderedHTML()
                }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
                .disabled(!workspace.hasActiveDocument)

                Divider()

                Button("Zoom In") {
                    workspace.zoomIn()
                }
                .keyboardShortcut("+")
                .disabled(!workspace.hasActiveDocument)

                Button("Zoom Out") {
                    workspace.zoomOut()
                }
                .keyboardShortcut("-")
                .disabled(!workspace.hasActiveDocument)

                Button("Actual Size") {
                    workspace.resetZoom()
                }
                .keyboardShortcut("0")
                .disabled(!workspace.hasActiveDocument)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSWindowDelegate {
    weak var workspace: WorkspaceStore?
    private var pendingOpenURLs: [URL] = []
    private var mainWindow: NSWindow?
    private var keyDownMonitor: Any?

    func attach(workspace: WorkspaceStore) -> [URL] {
        self.workspace = workspace
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }

    func open(urls: [URL]) {
        guard !urls.isEmpty else { return }

        if let workspace {
            showMainWindow()
            workspace.open(urls: urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    func configureMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else {
            normalizeToolbar(for: window)
            return
        }

        mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        normalizeToolbar(for: window)
        repairCloseMenuItem()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        installKeyDownMonitor()
        DispatchQueue.main.async { [weak self] in
            self?.repairQuitMenuItem()
            self?.repairCloseMenuItem()
            self?.normalizeToolbars()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        repairQuitMenuItem()
        repairCloseMenuItem()
        normalizeToolbars()
        workspace?.refreshRecentDocuments()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        open(urls: urls)
        normalizeToolbars()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeKeyDownMonitor()
        workspace?.saveWorkspace()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(quit(_:)) {
            return true
        }
        if menuItem.action == #selector(closeTab(_:)) {
            return workspace?.hasActiveDocument ?? false
        }

        return true
    }

    @objc private func quit(_ sender: Any?) {
        workspace?.saveWorkspace()
        NSApp.terminate(sender)
    }

    @objc private func closeTab(_ sender: Any?) {
        workspace?.closeActiveTab()
        repairCloseMenuItem()
        showMainWindow()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === mainWindow else { return true }

        if workspace?.hasActiveDocument == true {
            workspace?.closeActiveTab()
        }

        repairCloseMenuItem()
        showMainWindow()
        return false
    }

    private func repairQuitMenuItem() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }

        let quitItem = appMenu.items.first { item in
            item.action == #selector(NSApplication.terminate(_:)) ||
            item.title.localizedCaseInsensitiveContains("Quit")
        }

        guard let quitItem else { return }
        quitItem.title = "Quit MDViewer"
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        quitItem.action = #selector(quit(_:))
        quitItem.isEnabled = true
    }

    private func repairCloseMenuItem() {
        guard let fileMenu = NSApp.mainMenu?.items.first(where: { $0.title == "File" })?.submenu else { return }

        let closeItems = fileMenu.items.filter { item in
            item.action == #selector(NSWindow.performClose(_:)) ||
            item.keyEquivalent == "w" ||
            item.title.localizedCaseInsensitiveContains("Close Window")
        }

        for closeItem in closeItems {
            closeItem.title = "Close Tab"
            closeItem.keyEquivalent = "w"
            closeItem.keyEquivalentModifierMask = [.command]
            closeItem.target = self
            closeItem.action = #selector(closeTab(_:))
            closeItem.isEnabled = workspace?.hasActiveDocument ?? false
        }
    }

    private func installKeyDownMonitor() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 13,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            else { return event }

            Task { @MainActor in
                guard let self else { return }
                if self.workspace?.hasActiveDocument == true {
                    self.workspace?.closeActiveTab()
                }
                self.repairCloseMenuItem()
                self.showMainWindow()
            }

            return nil
        }
    }

    private func removeKeyDownMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }

    private func showMainWindow() {
        guard let mainWindow else { return }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func normalizeToolbars() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let mainWindow = self.mainWindow {
                self.normalizeToolbar(for: mainWindow)
            }
        }
    }

    private func normalizeToolbar(for window: NSWindow) {
        window.toolbarStyle = .unifiedCompact
        guard let toolbar = window.toolbar else { return }
        toolbar.isVisible = true
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.autosavesConfiguration = false
        toolbar.allowsUserCustomization = false
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolveWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolveWindow(for: nsView)
    }

    private func resolveWindow(for view: NSView) {
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
    }
}
