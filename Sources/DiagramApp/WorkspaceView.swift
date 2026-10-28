import AppKit
import SwiftUI
import DiagramCore

struct WorkspaceView: View {
    @ObservedObject var workspace: WorkspaceStore
    @Binding var appAppearance: AppAppearance
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            EditorView(store: workspace.activeStore, appAppearance: $appAppearance).id(workspace.activeStore.id)
        }
        .background(WorkspaceWindowGuard(workspace: workspace).frame(width: 0, height: 0))
        .onReceive(poll) { _ in workspace.checkExternalChanges() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Mode", selection: Binding(get: { workspace.activeStore.document.mode }, set: workspace.openMode)) {
                    ForEach(DocumentMode.allCases, id: \.self) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
                }.pickerStyle(.menu).frame(width: 158).accessibilityLabel("Mode")
                    .help("Switch to a mode's existing tab, or create a new one; current work stays in its tab")
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(workspace.tabs) { tab in
                            let selected = tab.id == workspace.selectedTabID
                            HStack(spacing: 6) {
                                Button { workspace.select(tab.id) } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: tab.document.mode.symbol).foregroundStyle(.secondary)
                                        if tab.dirty {
                                            Circle().fill(Color.secondary).frame(width: 6, height: 6)
                                                .accessibilityLabel("Unsaved changes")
                                        }
                                        Text(tab.document.title).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 0)
                                    }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Select diagram tab: \(tab.document.title)")
                                    .accessibilityValue(selected ? "Selected" : "Not selected")
                                    .help(tab.url?.path ?? "Unsaved diagram")
                                Button { workspace.closeTab(tab.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary).frame(width: 22, height: 24).contentShape(Rectangle())
                                }.buttonStyle(.plain).help("Close tab (⌘W)")
                                    .accessibilityLabel("Close diagram tab: \(tab.document.title)")
                            }
                            .font(.system(size: 12, weight: selected ? .medium : .regular))
                            .padding(.leading, 14).padding(.trailing, 6).frame(width: 200, height: 38)
                            .background(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                            .overlay(alignment: .bottom) { if selected { Color.accentColor.frame(height: 2) } }
                            .overlay(alignment: .trailing) { Divider().padding(.vertical, 8) }
                            .id(tab.id)
                        }
                    }
                }.onChange(of: workspace.selectedTabID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            Button(action: workspace.newTab) {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                    .frame(width: 38, height: 38).contentShape(Rectangle())
            }.buttonStyle(.plain).help("New \(workspace.activeStore.document.mode.title) tab (⌘T)").accessibilityLabel("New \(workspace.activeStore.document.mode.title) tab")
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Keep native window closing safe, while Command-W closes only the current diagram.
private struct WorkspaceWindowGuard: NSViewRepresentable {
    let workspace: WorkspaceStore
    func makeCoordinator() -> Coordinator { Coordinator(workspace: workspace) }
    func makeNSView(context: Context) -> WindowView {
        let view = WindowView(); view.coordinator = context.coordinator; return view
    }
    func updateNSView(_ view: WindowView, context: Context) { context.coordinator.attach(to: view.window) }
    static func dismantleNSView(_ view: WindowView, coordinator: Coordinator) { coordinator.detach() }

    final class WindowView: NSView {
        weak var coordinator: Coordinator?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); coordinator?.attach(to: window) }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let workspace: WorkspaceStore
        weak var window: NSWindow?
        weak var originalDelegate: NSWindowDelegate?
        private var keyMonitor: Any?
        init(workspace: WorkspaceStore) { self.workspace = workspace }
        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            detach(); self.window = window; originalDelegate = window.delegate; window.delegate = self
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, NSApp.keyWindow === self.window, self.window?.attachedSheet == nil,
                      !self.workspace.activeStore.sourceVisible,
                      event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "w" else { return event }
                self.workspace.closeActiveTab(); return nil
            }
        }
        func detach() {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
            if window?.delegate === self { window?.delegate = originalDelegate }
            window = nil; originalDelegate = nil
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            workspace.confirmCloseAll() && (originalDelegate?.windowShouldClose?(sender) ?? true)
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
        }
        override func forwardingTarget(for selector: Selector!) -> Any? { originalDelegate }
    }
}
