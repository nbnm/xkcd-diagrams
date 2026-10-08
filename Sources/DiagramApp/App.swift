import SwiftUI
import AppKit
import DiagramCore

enum AppAppearance: String, CaseIterable {
    case light, dark

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

@main struct DiagramApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var workspace = WorkspaceStore()
    @AppStorage("appAppearance") private var appAppearance: AppAppearance = .light
    private var store: EditorStore { workspace.activeStore }
    var body: some Scene {
        Window("XKCD Diagrams", id: "editor") {
            WorkspaceView(workspace: workspace, appAppearance: $appAppearance)
                .preferredColorScheme(appAppearance.colorScheme)
                .frame(minWidth: 1080, minHeight: 680)
                .onAppear { delegate.workspace = workspace; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1380, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Diagram", action: workspace.newTab).keyboardShortcut("n")
                Button("New Tab", action: workspace.newTab).keyboardShortcut("t")
                Button("Open…", action: workspace.open).keyboardShortcut("o")
                Button("Open Example", action: workspace.openExample)
                Divider()
                Button("Close Tab", action: workspace.closeActiveTab).keyboardShortcut("w").disabled(store.sourceVisible)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save", action: { store.save() }).keyboardShortcut("s")
                Button("Save As…", action: { store.save(asCopy: true) }).keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Export SVG…", action: { store.export("svg") })
                Button("Export PNG…", action: { store.export("png") })
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo", action: store.undo).keyboardShortcut("z").disabled(!store.canUndo)
                Button("Redo", action: store.redo).keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!store.canRedo)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { store.clipboardCommand("cut") }.keyboardShortcut("x")
                Button("Copy") { store.clipboardCommand("copy") }.keyboardShortcut("c")
                Button("Paste") { store.clipboardCommand("paste") }.keyboardShortcut("v")
            }
            CommandMenu("Toolbox") {
                ForEach(Array(ToolboxShortcuts.all.filter { $0.keys.count == 1 }.enumerated()), id: \.offset) { _, tool in
                    Button("\(tool.title) (\(tool.displayKeys))") { store.activateTool(tool.action) }
                }
                ForEach(Array(ToolboxShortcuts.groups.enumerated()), id: \.offset) { index, group in
                    Menu(group) {
                        ForEach(Array(ToolboxShortcuts.matching([String(index + 1)]).enumerated()), id: \.offset) { _, tool in
                            Button("\(tool.title) (\(tool.displayKeys))") { store.activateTool(tool.action) }
                        }
                    }
                }
            }
            CommandGroup(before: .windowList) {
                Button("Next Tab") { workspace.switchTab(by: 1) }.keyboardShortcut("]", modifiers: [.command, .shift]).disabled(!workspace.canSwitchTabs)
                Button("Previous Tab") { workspace.switchTab(by: -1) }.keyboardShortcut("[", modifiers: [.command, .shift]).disabled(!workspace.canSwitchTabs)
                Divider()
            }
            CommandMenu("Diagram") {
                Button("Add Container") { store.addContainer() }.keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Add Container Below Diagram", action: store.addContainerBelow)
                Picker("Canvas Placement", selection: Binding(get: { store.document.containers[store.document.root]?.layout.mode ?? .free }, set: store.setCanvasLayout)) {
                    Text("Free placement").tag(LayoutMode.free)
                    Text("Horizontal row").tag(LayoutMode.horizontal)
                    Text("Vertical column").tag(LayoutMode.vertical)
                    Text("Custom rows and columns").tag(LayoutMode.grid)
                }
                Button("Connector", action: store.toggleConnector).keyboardShortcut("k")
                Button("Zoom In", action: store.zoomIn).keyboardShortcut("=").disabled(!store.canZoomIn)
                Button("Zoom Out", action: store.zoomOut).keyboardShortcut("-").disabled(!store.canZoomOut)
                Button("Fit to Content") { store.fitRequest += 1 }.keyboardShortcut("0")
                Button("Edit Source") { store.sourceVisible = true }.keyboardShortcut("e", modifiers: [.command, .shift])
                Divider(); Button("Delete Selection", action: store.deleteSelection).disabled(store.selection == nil)
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingURLs: [URL] = []
    weak var workspace: WorkspaceStore? {
        didSet {
            guard let workspace else { return }
            let urls = pendingURLs; pendingURLs = []
            for url in urls { workspace.open(url) }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { workspace?.confirmCloseAll() == false ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let workspace else { pendingURLs.append(contentsOf: urls); return }
        for url in urls { workspace.open(url) }
    }
}
