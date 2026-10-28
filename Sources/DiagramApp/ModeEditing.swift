import AppKit
import DiagramCore

enum FreeDrawingTool: String, CaseIterable {
    case pen, select, text, eraser
    var title: String { rawValue.capitalized }
    var key: String { switch self { case .pen: return "P"; case .select: return "V"; case .text: return "T"; case .eraser: return "E" } }
    var symbol: String { switch self { case .pen: return "pencil.tip"; case .select: return "cursorarrow"; case .text: return "textformat"; case .eraser: return "eraser" } }
}
private struct ModeClipboard: Codable { var stroke: InkStroke?; var task: TimelineTask? }

@MainActor extension EditorStore {
    var contentSummary: String {
        switch document.mode {
        case .diagram: return "\(document.nodes.count) systems · \(document.containers.count - 1) boundaries"
        case .drawing: return "\(document.drawing?.strokes.count ?? 0) strokes · \(document.nodes.count) text items"
        case .timeline: return "\(document.timeline?.tasks.count ?? 0) tasks · calendar days"
        }
    }
    var modeHint: String {
        switch document.mode {
        case .diagram: return placingContainer || placingItem != nil ? "Click to place · Esc to cancel" : connecting ? (connectionStart == nil ? "Select the source" : "Select the destination") : "⌥ drag to pan · pinch to zoom"
        case .drawing: return "\(drawingTool.title) · ⌥ drag to pan · pinch to zoom"
        case .timeline: return "Drag bars to move · drag ends to resize · ⌥ drag to pan"
        }
    }
    func chooseDrawingTool(_ tool: FreeDrawingTool) {
        drawingTool = tool
        status = tool == .text ? "Click the canvas to type" : tool == .pen ? "Draw with the mouse" : tool == .eraser ? "Drag across strokes or text to erase" : "Select and drag strokes or text"
    }
    func addStroke(_ points: [Point]) {
        guard let options = document.drawing, !points.isEmpty else { return }
        let stroke = InkStroke(points: points, strokeWidth: options.strokeWidth, smoothing: options.smoothing)
        mutate("Draw stroke", coalescingKey: stroke.id) { $0.drawing?.strokes.append(stroke) }
        if document.drawing?.strokes.contains(where: { $0.id == stroke.id }) == true { selection = stroke.id }
    }
    @discardableResult func addFreeText(_ label: String, at point: CGPoint) -> String {
        let id = "text-" + UUID().uuidString.prefix(8).lowercased()
        mutate("Add text", coalescingKey: id) {
            $0.nodes[id] = Node(type: "text", label: label, shape: .text, position: Point(x: point.x, y: point.y), width: 260, height: 44)
            $0.containers[$0.root]?.children.append(id)
        }
        selection = id; drawingTool = .select; return id
    }
    func eraseModeItems(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        mutate("Erase", coalescingKey: UUID().uuidString) { d in for id in ids { d.remove(id) } }
    }
    func moveStroke(_ id: String, delta: CGPoint) {
        mutate("Move stroke", coalescingKey: UUID().uuidString) { d in
            guard let i = d.drawing?.strokes.firstIndex(where: { $0.id == id }) else { return }
            d.drawing!.strokes[i].points = d.drawing!.strokes[i].points.map { Point(x: $0.x + delta.x, y: $0.y + delta.y) }
        }
    }
    func addTask(milestone: Bool = false, start: String? = nil) {
        guard let timeline = document.timeline else { return }
        let selected = timeline.tasks.first { $0.id == selection }
        let date = start ?? selected.flatMap { TimelineDate.adding($0.milestone ? 0 : $0.duration, to: $0.start) } ?? TimelineDate.today
        let task = TimelineTask(label: milestone ? "New milestone" : "New task", start: date, duration: milestone ? 0 : 5, milestone: milestone)
        mutate(milestone ? "Add milestone" : "Add task", coalescingKey: task.id) { $0.timeline?.tasks.append(task) }
        if document.timeline?.tasks.contains(where: { $0.id == task.id }) == true { selection = task.id }
    }
    func editTask(_ id: String, action: String = "Edit task", coalescingKey: String? = nil, _ edit: (inout TimelineTask) -> Void) {
        mutate(action, coalescingKey: coalescingKey ?? action + id) { d in
            guard let index = d.timeline?.tasks.firstIndex(where: { $0.id == id }) else { return }
            edit(&d.timeline!.tasks[index])
        }
    }
    func reorderTask(_ id: String, by delta: Int) {
        mutate("Reorder task", coalescingKey: UUID().uuidString) { d in
            guard var timeline = d.timeline else { return }
            TimelineEditing.reorder(id, by: delta, in: &timeline); d.timeline = timeline
        }
    }
    func nudgeModeSelection(_ dx: Double, _ dy: Double) -> Bool {
        guard let id = selection else { return false }
        if document.drawing?.strokes.contains(where: { $0.id == id }) == true { moveStroke(id, delta: CGPoint(x: dx, y: dy)); return true }
        if document.timeline?.tasks.contains(where: { $0.id == id }) == true {
            if dx != 0 { editTask(id, action: "Move task") { $0.start = TimelineDate.adding(Int(dx), to: $0.start) ?? $0.start } }
            else if dy != 0 { reorderTask(id, by: dy > 0 ? 1 : -1) }
            return true
        }
        return false
    }
    func copyModeSelection() -> Bool? {
        let stroke = document.drawing?.strokes.first { $0.id == selection }
        let task = document.timeline?.tasks.first { $0.id == selection }
        guard stroke != nil || task != nil else { return nil }
        do {
            let data = try JSONEncoder().encode(ModeClipboard(stroke: stroke, task: task))
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .init("com.t1a.diagrams.mode-item"))
            status = "Copied \(selectionLabel)"; return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func pasteModeSelection() -> Bool {
        guard let data = pasteboard.data(forType: .init("com.t1a.diagrams.mode-item")) else { return false }
        do {
            let item = try JSONDecoder().decode(ModeClipboard.self, from: data)
            if var stroke = item.stroke, document.mode == .drawing {
                stroke.id = UUID().uuidString.lowercased(); stroke.points = stroke.points.map { Point(x: $0.x + 24, y: $0.y + 24) }
                mutate("Paste stroke", coalescingKey: stroke.id) { $0.drawing?.strokes.append(stroke) }; selection = stroke.id
            } else if var task = item.task, document.mode == .timeline {
                task.id = UUID().uuidString.lowercased(); task.label += " copy"
                task.dependencies = task.dependencies.filter { id in document.timeline?.tasks.contains { $0.id == id } == true }
                mutate("Paste task", coalescingKey: task.id) { $0.timeline?.tasks.append(task) }; selection = task.id
            } else { status = "Paste this item into a \(item.stroke == nil ? "timeline" : "free drawing") tab" }
        } catch { errorMessage = error.localizedDescription }
        return true
    }
    var canvasTextEditor: NSTextView? {
        guard let view = NSApp.keyWindow?.firstResponder as? NSTextView, view.identifier?.rawValue == "free-drawing-text" else { return nil }
        return view
    }
    var canUndoEditing: Bool { canvasTextEditor?.undoManager?.canUndo ?? canUndo }
    var canRedoEditing: Bool { canvasTextEditor?.undoManager?.canRedo ?? canRedo }
    func undoEditing() { if let editor = canvasTextEditor { editor.undoManager?.undo() } else { undo() } }
    func redoEditing() { if let editor = canvasTextEditor { editor.undoManager?.redo() } else { redo() } }
}
