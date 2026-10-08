import AppKit
import Combine
import DiagramCore

@MainActor final class WorkspaceStore: ObservableObject {
    @Published private(set) var tabs: [EditorStore] = []
    @Published private(set) var selectedTabID: UUID?
    private var observations: [UUID: AnyCancellable] = [:]
    private let defaults: UserDefaults?
    private let confirmClose: @MainActor (EditorStore) -> Bool
    private var closeApproved = false

    init(defaults: UserDefaults? = .standard, confirmClose: @escaping @MainActor (EditorStore) -> Bool = { $0.confirmUnsaved() }) {
        self.defaults = defaults; self.confirmClose = confirmClose
        if let paths = defaults?.stringArray(forKey: "openDiagramTabs") {
            for path in paths {
                let url = Self.fileURL(URL(fileURLWithPath: path))
                guard !tabs.contains(where: { $0.url.map(Self.fileURL) == url }),
                      let (document, revision) = try? DiagramFiles.read(url) else { continue }
                append(EditorStore(document: document, url: url, revision: revision))
            }
            if let path = defaults?.string(forKey: "selectedDiagramTab"),
               let tab = tabs.first(where: { $0.url?.path == path }) { selectedTabID = tab.id }
            if tabs.isEmpty { append(EditorStore(document: Diagram())) }
        } else { append(EditorStore()) }
    }

    var activeStore: EditorStore { tabs.first { $0.id == selectedTabID } ?? tabs[0] }
    var canSwitchTabs: Bool { tabs.count > 1 }
    private static func fileURL(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }

    private func append(_ store: EditorStore) {
        store.canSaveTo = { [weak self, weak store] url in
            guard let self, let store else { return false }
            return !self.tabs.contains { $0.id != store.id && $0.url.map(Self.fileURL) == Self.fileURL(url) }
        }
        observations[store.id] = store.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.closeApproved = false; self.objectWillChange.send()
            DispatchQueue.main.async { [weak self] in self?.persistSession() }
        }
        tabs.append(store); selectedTabID = store.id; closeApproved = false
    }

    func select(_ id: UUID) {
        guard id != selectedTabID, tabs.contains(where: { $0.id == id }) else { return }
        activeStore.cancelTools(); selectedTabID = id; closeApproved = false; persistSession()
    }
    func newTab() { activeStore.cancelTools(); append(EditorStore(document: Diagram())); persistSession() }
    func openExample() { activeStore.cancelTools(); append(EditorStore()); persistSession() }
    func open() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { open(url) }
    }
    func open(_ source: URL) {
        let url = Self.fileURL(source)
        if let existing = tabs.first(where: { $0.url.map(Self.fileURL) == url }) { select(existing.id); return }
        do {
            let (document, revision) = try DiagramFiles.read(url)
            activeStore.cancelTools(); append(EditorStore(document: document, url: url, revision: revision)); persistSession()
        } catch { activeStore.errorMessage = error.localizedDescription }
    }
    func switchTab(by delta: Int) {
        guard canSwitchTabs, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let next = (index + delta % tabs.count + tabs.count) % tabs.count
        select(tabs[next].id)
    }
    func closeActiveTab() { closeTab(activeStore.id) }
    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let store = tabs[index]
        guard !store.dirty || confirmClose(store) else { return }
        store.stopAutosave(); observations.removeValue(forKey: id)
        tabs.remove(at: index)
        if tabs.isEmpty { append(EditorStore(document: Diagram())) }
        else if selectedTabID == id { selectedTabID = tabs[min(index, tabs.count - 1)].id }
        closeApproved = false; persistSession()
    }
    func checkExternalChanges() { for tab in tabs { tab.checkExternalChanges() } }
    func confirmCloseAll() -> Bool {
        if closeApproved { return true }
        let ordered = [activeStore] + tabs.filter { $0.id != selectedTabID }
        for tab in ordered where tab.dirty {
            select(tab.id)
            guard confirmClose(tab) else { return false }
        }
        for tab in tabs { tab.stopAutosave() }
        persistSession(); closeApproved = true; return true
    }
    private func persistSession() {
        defaults?.set(tabs.compactMap { $0.url.map(Self.fileURL)?.path }, forKey: "openDiagramTabs")
        if let url = activeStore.url { defaults?.set(Self.fileURL(url).path, forKey: "selectedDiagramTab") }
        else { defaults?.removeObject(forKey: "selectedDiagramTab") }
    }
}
