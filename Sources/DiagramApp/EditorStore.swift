import AppKit
import SwiftUI
import DiagramCore

struct CanvasViewport: Equatable {
    var zoom: CGFloat
    var offset: CGPoint
}

@MainActor final class EditorStore: ObservableObject, Identifiable {
    let id = UUID()
    @Published var document: Diagram
    @Published var scene: RenderScene
    @Published var selection: String?
    @Published var connecting = false
    @Published var placingContainer = false
    @Published var placingItem: String?
    @Published var labelEditRequest = 0
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
    var canvasViewport: CanvasViewport?
    var canSaveTo: ((URL) -> Bool)?
    private var revision: String?
    private var past: [Diagram] = [], future: [Diagram] = []
    private var lastAction = "", lastChange = Date.distantPast
    private var autosave: DispatchWorkItem?
    private var clipboardChange = -1, pasteCount = 0
    private static let itemPasteboardType = NSPasteboard.PasteboardType("com.t1a.diagrams.elements")

    init(document: Diagram = Library.sample(), url: URL? = nil, revision: String? = nil) {
        self.document = document
        scene = try! Renderer.scene(document)
        self.url = url; self.revision = revision
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
        placingContainer = false
        placingItem = nil
        connecting = true; connectionStart = id
        if let id { selection = id }
        status = id == nil ? "Drag between objects, or click the source and destination" : "Drag from this source, or click a destination"
    }
    func cancelConnection() {
        connecting = false; connectionStart = nil; status = "Ready"
    }
    func beginContainerPlacement() {
        cancelTools(); placingContainer = true
        status = "Click the canvas to place a container"
    }
    func activateTool(_ action: ToolboxAction) {
        switch action {
        case .container: beginContainerPlacement()
        case .connector: beginConnection()
        case .item(let id):
            guard let item = library.first(where: { $0.id == id }) else { return }
            cancelTools(); placingItem = id; status = "Click the canvas to place \(item.title) · Esc to cancel"
        }
    }
    func cancelTools() {
        placingContainer = false; placingItem = nil; cancelConnection()
    }
    func editLabel(_ id: String) {
        guard id != document.root, document.nodes[id] != nil || document.containers[id] != nil || document.connectors[id] != nil else { return }
        cancelTools(); selection = id; labelEditRequest += 1
    }
    func clipboardCommand(_ command: String) {
        // Keep the native text responder responsible for editing fields and source JSON.
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSTextView || responder is NSTextField {
            NSApp.sendAction(NSSelectorFromString(command + ":"), to: nil, from: nil)
            return
        }
        switch command {
        case "copy": copySelection()
        case "paste": pasteSelection()
        case "cut": if copySelection() { deleteSelection() }
        default: break
        }
    }
    @discardableResult func copySelection() -> Bool {
        guard let id = selection, id != document.root else { return false }
        do {
            let data = try DiagramClipboard.capture(id, from: document).encoded()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents(); pasteboard.setData(data, forType: Self.itemPasteboardType)
            pasteboard.setString(String(decoding: data, as: UTF8.self), forType: .string)
            clipboardChange = pasteboard.changeCount; pasteCount = 0
            status = "Copied \(document.label(of: id))"; return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func pasteSelection() {
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: Self.itemPasteboardType) else { status = "Copy a diagram item before pasting"; return }
        do {
            let clip = try DiagramClipboard.decode(data)
            if clipboardChange != pasteboard.changeCount { clipboardChange = pasteboard.changeCount; pasteCount = 0 }
            let sameDocument = clip.sourceDocumentID == document.id
            let parent: String
            if sameDocument, let original = clip.sourceParent, document.containers[original] != nil { parent = original }
            else { parent = selection.flatMap { document.containers[$0] != nil ? $0 : nil } ?? document.root }
            let shift = Double(pasteCount + 1) * 24
            let position = sameDocument
                ? scene.layout.position(at: CGPoint(x: clip.origin.x + shift, y: clip.origin.y + shift), in: parent, document: document)
                : Point(x: shift + 40, y: shift + 40)
            var pasted: String?
            let before = document
            mutate("Paste item", coalescingKey: UUID().uuidString) { pasted = try clip.paste(into: parent, at: position, document: &$0) }
            if document != before, let pasted { cancelTools(); selection = pasted; pasteCount += 1; status = "Pasted \(document.label(of: pasted))" }
        } catch { errorMessage = error.localizedDescription }
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
        cancelTools()
        let target = parent ?? selection.flatMap { document.containers[$0] != nil ? $0 : nil } ?? document.root
        let id = item.id + "-" + UUID().uuidString.prefix(6).lowercased()
        mutate("Add \(item.title)") { d in
            let origin = scene.layout.contentOrigins[target] ?? .zero
            let p = point.map { scene.layout.position(at: $0, in: target, document: d) }
                ?? Point(x: Double(d.containers[target]!.children.count % 3) * 220 + 40, y: Double(d.containers[target]!.children.count / 3) * 150 + 40)
            d.nodes[id] = item.node(at: d.containers[target]!.layout.mode == .free ? p : nil)
            if let asset = item.asset { d.assets[item.id] = asset }
            d.containers[target]?.children.append(id)
            try DiagramEditing.ensureGridRoom(container: target, document: &d)
            if let point, let grid = scene.layout.grids[target] {
                let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
                try DiagramEditing.setGridCell(grid.cell(at: local), element: id, document: &d)
            }
        }
        if document.nodes[id] != nil { selection = id }
    }
    func addContainer(point: CGPoint? = nil, parent target: String? = nil) {
        cancelTools()
        let parent = target ?? selection.flatMap { document.containers[$0] != nil ? $0 : nil } ?? document.root
        let id = "group-" + UUID().uuidString.prefix(6).lowercased()
        mutate("Add container") { d in
            let owner = d.containers[parent]!, origin = scene.layout.contentOrigins[parent] ?? .zero
            let position = point.map { scene.layout.position(at: $0, in: parent, document: d) } ?? Point(x: 100, y: 80)
            d.containers[id] = Container(label: "Container", position: owner.layout.mode == .free ? position : nil)
            d.containers[parent]?.children.append(id)
            try DiagramEditing.ensureGridRoom(container: parent, document: &d)
            if let point, let grid = scene.layout.grids[parent] {
                let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
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
        cancelTools()
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
            $0 != document.root && document.containers[$0] != nil && !excluded.contains($0) && scene.layout.frames[$0]!.contains(point)
        } ?? document.root
        let c = document.containers[target]!, origin = scene.layout.contentOrigins[target]!
        let old = scene.layout.frames[id]!
        if let grid = scene.layout.grids[target] {
            let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
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
        let position = scene.layout.position(at: CGPoint(x: old.minX + delta.x, y: old.minY + delta.y), in: target, document: document)
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
        guard let frame = scene.layout.frames[id] else { return }
        let position = scene.layout.position(at: CGPoint(x: frame.minX + dx, y: frame.minY + dy), in: parent, document: document)
        mutate("Nudge element") { d in
            if d.nodes[id] != nil { d.nodes[id]?.position = position }
            else if d.containers[id] != nil { d.containers[id]?.position = position }
        }
    }
    func open(_ url: URL) {
        do { let (d, rev) = try DiagramFiles.read(url); reset(d, url: url, revision: rev); fitRequest += 1 }
        catch { errorMessage = error.localizedDescription }
    }
    func revealFileInFinder() {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    private func reset(_ d: Diagram, url: URL?, revision: String?) {
        autosave?.cancel(); selection = nil; connectionStart = nil; connecting = false; placingContainer = false; placingItem = nil
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
        guard canSaveTo?(destination) != false else {
            errorMessage = "This file is already open in another tab. Choose a different filename."; return false
        }
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
    func stopAutosave() { autosave?.cancel(); autosave = nil }
    private func scheduleSave() {
        autosave?.cancel(); guard url != nil, !externalChange else { return }
        let task = DispatchWorkItem { [weak self] in guard let self, self.dirty, !self.externalChange else { return }; _ = self.save() }
        autosave = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
    }
}
