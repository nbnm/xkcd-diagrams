import AppKit
import SwiftUI
import DiagramCore

@MainActor final class EditorStore: ObservableObject {
    @Published var document: Diagram
    @Published var scene: RenderScene
    @Published var selection: String?
    @Published var connecting = false
    @Published var connectionStart: String?
    @Published var url: URL?
    @Published var dirty = false
    @Published var errorMessage: String?
    @Published var externalChange = false
    @Published var sourceVisible = false
    @Published var fitRequest = 0
    @Published var zoomRequest = 0
    @Published var zoomScale: Double = 1
    @Published var status = "Ready"
    @Published var historyVersion = 0
    let library: [DiagramCore.LibraryItem] = Library.items()
    private var revision: String?
    private var past: [Diagram] = [], future: [Diagram] = []
    private var lastAction = "", lastChange = Date.distantPast
    private var autosave: DispatchWorkItem?

    init() {
        let sample = Library.sample()
        document = sample
        scene = try! Renderer.scene(sample)
    }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var canZoomIn: Bool { zoomScale < 3 - 0.0001 }
    var canZoomOut: Bool { zoomScale > 0.2 + 0.0001 }
    func zoomIn() { zoomRequest += 1 }
    func zoomOut() { zoomRequest -= 1 }
    var selectionLabel: String { selection.map(document.label(of:)) ?? "Diagram" }
    func isConnectionEndpoint(_ id: String) -> Bool { id != document.root && (document.nodes[id] != nil || document.containers[id] != nil) }
    func toggleConnector() {
        if connecting { cancelConnection() } else { beginConnection() }
    }
    func beginConnection(from id: String? = nil) {
        guard id == nil || isConnectionEndpoint(id!) else { return }
        connecting = true; connectionStart = id
        if let id { selection = id }
        status = id == nil ? "Drag between objects, or click the source and destination" : "Drag from this source, or click a destination"
    }
    func cancelConnection() {
        connecting = false; connectionStart = nil; status = "Ready"
    }
    func connect(from source: String, to destination: String) {
        guard source != destination, isConnectionEndpoint(source), isConnectionEndpoint(destination) else { return }
        let key = "connection-" + UUID().uuidString.prefix(8).lowercased()
        mutate("Connect systems", coalescingKey: key) { $0.connectors[key] = Connector(from: Endpoint(source), to: Endpoint(destination)) }
        if document.connectors[key] != nil { selection = key; connecting = false; connectionStart = nil }
    }

    func mutate(_ action: String, coalescingKey: String? = nil, _ change: (inout Diagram) throws -> Void) {
        var next = document
        do {
            try change(&next)
            guard next != document else { return }
            let nextScene = try Renderer.scene(next)
            let key = coalescingKey ?? action
            if key != lastAction || Date().timeIntervalSince(lastChange) > 0.6 { past.append(document) }
            if past.count > 100 { past.removeFirst() }
            lastAction = key; lastChange = Date(); future.removeAll(); historyVersion += 1
            reconcileSelection(in: next)
            document = next; scene = nextScene; dirty = true; status = action
            scheduleSave()
        } catch { errorMessage = error.localizedDescription }
    }
    func undo() {
        guard let old = past.popLast() else { return }
        future.append(document); install(old); historyVersion += 1; status = "Undo"; lastAction = ""; scheduleSave()
    }
    func redo() {
        guard let next = future.popLast() else { return }
        past.append(document); install(next); historyVersion += 1; status = "Redo"; lastAction = ""; scheduleSave()
    }
    private func reconcileSelection(in d: Diagram) {
        if let id = selection, d.nodes[id] == nil && d.containers[id] == nil && d.connectors[id] == nil { selection = nil }
        if let id = connectionStart, d.nodes[id] == nil && d.containers[id] == nil { connectionStart = nil }
    }
    private func install(_ d: Diagram) { reconcileSelection(in: d); document = d; scene = try! Renderer.scene(d); dirty = true }
    func select(_ id: String?) {
        if connecting {
            guard let id, isConnectionEndpoint(id) else { return }
            if let start = connectionStart, start != id {
                connect(from: start, to: id)
            } else { beginConnection(from: id) }
        } else { selection = id }
    }
    func add(_ item: DiagramCore.LibraryItem, point: CGPoint? = nil, parent: String? = nil) {
        let target = parent ?? selection.flatMap { document.containers[$0] != nil ? $0 : nil } ?? document.root
        let id = item.id + "-" + UUID().uuidString.prefix(6).lowercased()
        mutate("Add \(item.title)") { d in
            let frame = scene.layout.frames[target] ?? .zero, padding = d.containers[target]!.layout.padding
            let header: Double = target == d.root ? 0 : 36
            let p = point.map { Point(x: max(0, $0.x - frame.minX - padding), y: max(0, $0.y - frame.minY - padding - header)) }
                ?? Point(x: Double(d.containers[target]!.children.count % 3) * 220 + 40, y: Double(d.containers[target]!.children.count / 3) * 150 + 40)
            d.nodes[id] = item.node(at: d.containers[target]!.layout.mode == .free ? p : nil)
            if let asset = item.asset { d.assets[item.id] = asset }
            d.containers[target]?.children.append(id)
            try DiagramEditing.ensureGridRoom(container: target, document: &d)
            if let point, let grid = scene.layout.grids[target] {
                let local = CGPoint(x: point.x - frame.minX - padding, y: point.y - frame.minY - padding - header)
                try DiagramEditing.setGridCell(grid.cell(at: local), element: id, document: &d)
            }
        }
        if document.nodes[id] != nil { selection = id }
    }
    func addContainer(point: CGPoint? = nil, parent target: String? = nil) {
        let parent = target ?? selection.flatMap { document.containers[$0] != nil ? $0 : nil } ?? document.root
        let id = "group-" + UUID().uuidString.prefix(6).lowercased()
        mutate("Add container") { d in
            let owner = d.containers[parent]!, frame = scene.layout.frames[parent] ?? .zero
            let position = point.map { Point(x: max(0, $0.x - frame.minX - owner.layout.padding), y: max(0, $0.y - frame.minY - owner.layout.padding - (parent == d.root ? 0 : 36))) } ?? Point(x: 100, y: 80)
            d.containers[id] = Container(label: "Container", position: owner.layout.mode == .free ? position : nil)
            d.containers[parent]?.children.append(id)
            try DiagramEditing.ensureGridRoom(container: parent, document: &d)
            if let point, let grid = scene.layout.grids[parent] {
                let local = CGPoint(x: point.x - frame.minX - owner.layout.padding, y: point.y - frame.minY - owner.layout.padding - (parent == d.root ? 0 : 36))
                try DiagramEditing.setGridCell(grid.cell(at: local), element: id, document: &d)
            }
        }
        if document.containers[id] != nil { selection = id }
    }
    func setCanvasLayout(_ mode: LayoutMode) {
        mutate("Change canvas placement", coalescingKey: "canvas-placement") { try DiagramEditing.setLayout(mode, container: $0.root, document: &$0) }
    }
    func configureGrid(_ id: String, rows: Int, columns: Int) {
        mutate("Change grid dimensions", coalescingKey: "grid-\(id)") { try DiagramEditing.configureGrid(rows: rows, columns: columns, container: id, document: &$0) }
    }
    func setGridCell(_ cell: GridCell, element id: String) {
        guard selection == id else { return }
        mutate("Place item in grid", coalescingKey: "cell-\(id)") { try DiagramEditing.setGridCell(cell, element: id, document: &$0) }
    }
    func addContainerBelow() {
        let id = "group-" + UUID().uuidString.prefix(6).lowercased()
        mutate("Add container below diagram", coalescingKey: id) { d in
            if d.containers[d.root]?.layout.mode != .grid { try DiagramEditing.setLayout(.free, container: d.root, document: &d) }
            else {
                let plan = try GridLayout.plan(d.containers[d.root]!, id: d.root)
                d.containers[d.root]?.layout.cells = plan.cells
            }
            d.containers[id] = Container(label: "Container", layout: .init(mode: .horizontal))
            d.containers[d.root]?.children.append(id)
            try DiagramEditing.ensureGridRoom(container: d.root, document: &d)
            try DiagramEditing.placeContainerBelow(id, document: &d)
        }
        if document.containers[id] != nil { selection = id; fitRequest += 1 }
    }
    func placeSelectedContainerBelow() {
        guard let id = selection else { return }
        mutate("Place container below diagram", coalescingKey: "below-\(id)") { try DiagramEditing.placeContainerBelow(id, document: &$0) }
        fitRequest += 1
    }
    func deleteSelection() {
        guard let id = selection, id != document.root else { return }
        let removed = document.descendants(of: id)
        let attached = document.connectors.filter { removed.contains($0.value.from.element) || removed.contains($0.value.to.element) }.count
        if attached > 0 {
            let alert = NSAlert(); alert.messageText = "Delete \(selectionLabel)?"
            alert.informativeText = "This also removes \(attached) attached connection\(attached == 1 ? "" : "s"). You can undo this change."
            alert.addButton(withTitle: "Delete"); alert.addButton(withTitle: "Cancel")
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else { return }
            alert.beginSheetModal(for: window) { [weak self] answer in
                guard answer == .alertFirstButtonReturn else { return }
                self?.removeSelection(id)
            }
            return
        }
        removeSelection(id)
    }
    private func removeSelection(_ id: String) {
        mutate("Delete selection") { $0.remove(id) }; selection = nil
    }
    func move(_ id: String, to point: CGPoint, delta: CGPoint) {
        let excluded = document.descendants(of: id)
        let target = scene.layout.order.reversed().first {
            document.containers[$0] != nil && !excluded.contains($0) && scene.layout.frames[$0]!.contains(point)
        } ?? document.root
        let c = document.containers[target]!, frame = scene.layout.frames[target]!
        let old = scene.layout.frames[id]!
        if let grid = scene.layout.grids[target] {
            let local = CGPoint(x: point.x - frame.minX - c.layout.padding, y: point.y - frame.minY - c.layout.padding - (target == document.root ? 0 : 36))
            var cell = grid.cell(at: local)
            if let previous = grid.cells[id] {
                cell.rowSpan = previous.rowSpan; cell.columnSpan = previous.columnSpan
                cell.column = min(cell.column, grid.columnWidths.count - cell.columnSpan + 1)
            }
            mutate("Move element in grid", coalescingKey: "move-grid-\(id)") { d in
                if d.parent(of: id) != target { try DiagramEditing.reparent(id, into: target, position: nil, document: &d) }
                try DiagramEditing.setGridCell(cell, element: id, document: &d)
            }
            return
        }
        let position = Point(x: max(0, old.minX + delta.x - frame.minX - c.layout.padding),
                             y: max(0, old.minY + delta.y - frame.minY - c.layout.padding - (target == document.root ? 0 : 36)))
        var index: Int? = nil
        if c.layout.mode != .free {
            let coordinate = c.layout.mode == .horizontal ? point.x : point.y
            index = c.children.filter { $0 != id }.prefix { child in
                let r = scene.layout.frames[child]!
                return (c.layout.mode == .horizontal ? r.midX : r.midY) < coordinate
            }.count
        }
        mutate("Move element") { try DiagramEditing.reparent(id, into: target, position: position, index: index, document: &$0) }
    }
    func nudge(_ dx: Double, _ dy: Double) {
        guard let id = selection, let parent = document.parent(of: id), document.containers[parent]?.layout.mode == .free else { return }
        mutate("Nudge element") { d in
            if var n = d.nodes[id] { var p = n.position ?? .init(); p.x = max(0, p.x + dx); p.y = max(0, p.y + dy); n.position = p; d.nodes[id] = n }
            else if var c = d.containers[id] { var p = c.position ?? .init(); p.x = max(0, p.x + dx); p.y = max(0, p.y + dy); c.position = p; d.containers[id] = c }
        }
    }
    func newDocument() {
        guard confirmUnsaved() else { return }
        reset(Diagram(), url: nil, revision: nil); fitRequest += 1
    }
    func loadExample() {
        guard confirmUnsaved() else { return }
        reset(Library.sample(), url: nil, revision: nil); fitRequest += 1
    }
    func open() {
        guard confirmUnsaved() else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }; open(url)
    }
    func open(_ url: URL) {
        do { let (d, rev) = try DiagramFiles.read(url); reset(d, url: url, revision: rev); fitRequest += 1 }
        catch { errorMessage = error.localizedDescription }
    }
    private func reset(_ d: Diagram, url: URL?, revision: String?) {
        autosave?.cancel(); selection = nil; connectionStart = nil; connecting = false
        document = d; scene = try! Renderer.scene(d)
        self.url = url; self.revision = revision; dirty = false; externalChange = false
        past = []; future = []; historyVersion += 1; status = "Ready"; lastAction = ""
    }
    @discardableResult func save(asCopy: Bool = false) -> Bool {
        var destination = url
        if destination == nil || asCopy {
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = document.title + ".diagram.json"
            guard panel.runModal() == .OK else { return false }; destination = panel.url
        }
        guard let destination else { return false }
        do {
            let same = destination.standardizedFileURL == url?.standardizedFileURL
            let rev = try DiagramFiles.write(document, to: destination, expectedRevision: same ? revision : nil, overwrite: !same)
            url = destination; revision = rev; dirty = false; externalChange = false; status = "Saved"; return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func export(_ format: String) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [format == "png" ? .png : .svg]
        panel.nameFieldStringValue = document.title + "." + format
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            guard destination.standardizedFileURL != url?.standardizedFileURL else { throw DiagramError.message("Choose a different path from the source document.") }
            let data = try format == "png" ? Renderer.png(document) : Renderer.svg(document)
            try DiagramFiles.writeData(data, to: destination); status = "Exported \(format.uppercased())"
        } catch { errorMessage = error.localizedDescription }
    }
    func applySource(_ text: String) -> Bool {
        do { let next = try Diagram.decode(Data(text.utf8)); mutate("Apply source") { $0 = next }; return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func checkExternalChanges() {
        guard let url, let revision else { return }
        guard let data = try? Data(contentsOf: url) else { externalChange = true; status = "Source file is unavailable"; return }
        guard DiagramFiles.revision(data) != revision else { return }
        autosave?.cancel()
        if dirty { externalChange = true; status = "File changed outside the app" }
        else {
            do { let d = try Diagram.decode(data); reset(d, url: url, revision: DiagramFiles.revision(data)); status = "Reloaded external changes" }
            catch { externalChange = true; status = "External file contains errors" }
        }
    }
    func reloadExternal() { if let url, confirmUnsaved() { open(url) } }
    func confirmUnsaved() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "Save changes to \(document.title)?"
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Discard Changes"); alert.addButton(withTitle: "Cancel")
        let answer = alert.runModal()
        return answer == .alertSecondButtonReturn || (answer == .alertFirstButtonReturn && save())
    }
    private func scheduleSave() {
        autosave?.cancel(); guard url != nil, !externalChange else { return }
        let task = DispatchWorkItem { [weak self] in guard let self, self.dirty, !self.externalChange else { return }; _ = self.save() }
        autosave = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
    }
}
