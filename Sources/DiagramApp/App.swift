import SwiftUI
import AppKit
import DiagramCore

enum AppAppearance: String, CaseIterable {
    case light, dark

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

@main struct DiagramApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = EditorStore()
    @AppStorage("appAppearance") private var appAppearance: AppAppearance = .light
    var body: some Scene {
        WindowGroup("XKCD Diagrams") {
            EditorView(store: store, appAppearance: $appAppearance)
                .preferredColorScheme(appAppearance.colorScheme)
                .frame(minWidth: 1080, minHeight: 680)
                .onAppear { delegate.store = store; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1380, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Diagram", action: store.newDocument).keyboardShortcut("n")
                Button("Open…", action: store.open).keyboardShortcut("o")
                Button("Open Example", action: store.loadExample)
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
    weak var store: EditorStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { store?.confirmUnsaved() == false ? .terminateCancel : .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ application: NSApplication, open urls: [URL]) { if let url = urls.first, store?.confirmUnsaved() != false { store?.open(url) } }
}
