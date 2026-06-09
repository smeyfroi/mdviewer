import AppKit
import SwiftUI

@main
struct MDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workspace)
                .onAppear {
                    appDelegate.workspace = workspace
                    workspace.restoreIfNeeded()
                }
                .onOpenURL { url in
                    workspace.open(urls: [url])
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    weak var workspace: WorkspaceStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.repairQuitMenuItem()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        repairQuitMenuItem()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        workspace?.open(urls: urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        workspace?.saveWorkspace()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(quit(_:)) {
            return true
        }

        return true
    }

    @objc private func quit(_ sender: Any?) {
        workspace?.saveWorkspace()
        NSApp.terminate(sender)
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
}
