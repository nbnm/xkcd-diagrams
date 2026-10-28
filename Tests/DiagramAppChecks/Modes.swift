import AppKit
import DiagramCore

@MainActor func modesKeepDocumentsSeparateAndNewTabsInheritMode() throws {
    let workspace = WorkspaceStore(defaults: nil), diagram = workspace.activeStore
    workspace.openMode(.drawing); let drawing = workspace.activeStore
    drawing.addStroke([Point(x: -30, y: 0), Point(x: 50, y: 40)])
    workspace.openMode(.timeline); let timeline = workspace.activeStore
    timeline.addTask(start: "2026-10-26")
    workspace.openMode(.drawing)
    try expect(workspace.activeStore === drawing && drawing.document.drawing?.strokes.count == 1)
    workspace.newTab(); try expect(workspace.activeStore.document.mode == .drawing && workspace.activeStore.document.drawing?.strokes.isEmpty == true)
    workspace.select(timeline.id); timeline.undo()
    try expect(timeline.document.timeline?.tasks.isEmpty == true && drawing.document.drawing?.strokes.count == 1)
    workspace.select(diagram.id); try expect(diagram.document.nodes.count == 5 && diagram.document.mode == .diagram)
}

@MainActor func canvasFixture(_ store: EditorStore) -> (NSWindow, ModeCanvasView) {
    _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    let canvas = ModeCanvasView(store: store); window.contentView = canvas
    canvas.frame = CGRect(x: 0, y: 0, width: 900, height: 650); canvas.zoom = 1; canvas.offset = .zero
    return (window, canvas)
}
@MainActor func mouse(_ type: NSEvent.EventType, on canvas: ModeCanvasView, at p: CGPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: canvas.convert(p, to: nil), modifierFlags: [], timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}
@MainActor func drag(_ canvas: ModeCanvasView, from a: CGPoint, to b: CGPoint) {
    canvas.mouseDown(with: mouse(.leftMouseDown, on: canvas, at: a))
    canvas.mouseDragged(with: mouse(.leftMouseDragged, on: canvas, at: b))
    canvas.mouseUp(with: mouse(.leftMouseUp, on: canvas, at: b))
}

@MainActor func freeDrawingMouseGesturesAreAtomicAndEditable() throws {
    let store = EditorStore(document: DocumentMode.drawing.blank()), (window, canvas) = canvasFixture(store)
    defer { window.contentView = nil; window.close() }
    drag(canvas, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 220, y: 140))
    try expect(store.document.drawing?.strokes.count == 1 && store.canUndo)
    let stroke = store.document.drawing!.strokes[0]
    try expect(stroke.points.first == Point(x: 100, y: 100) && stroke.points.last == Point(x: 220, y: 140))
    store.undo(); try expect(store.document.drawing?.strokes.isEmpty == true && !store.canUndo)
    store.redo(); store.chooseDrawingTool(.select)
    drag(canvas, from: CGPoint(x: 160, y: 120), to: CGPoint(x: 190, y: 170))
    try expect(store.document.drawing!.strokes[0].points.first == Point(x: 130, y: 150))
    store.undo(); try expect(store.document.drawing!.strokes[0] == stroke)
    store.chooseDrawingTool(.eraser)
    drag(canvas, from: CGPoint(x: 160, y: 90), to: CGPoint(x: 160, y: 160))
    try expect(store.document.drawing?.strokes.isEmpty == true)
    store.undo(); try expect(store.document.drawing!.strokes[0] == stroke)
    store.chooseDrawingTool(.pen)
    canvas.mouseDown(with: mouse(.leftMouseDown, on: canvas, at: CGPoint(x: 10, y: 10)))
    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    canvas.keyDown(with: escape); canvas.mouseUp(with: mouse(.leftMouseUp, on: canvas, at: CGPoint(x: 20, y: 30)))
    try expect(store.document.drawing?.strokes.count == 1)
}

@MainActor func inlineTextCommitsOnceAndCancelsWithoutCreatingItems() throws {
    let store = EditorStore(document: DocumentMode.drawing.blank()), (window, canvas) = canvasFixture(store)
    defer { window.contentView = nil; window.close() }
    canvas.beginText(at: CGPoint(x: -30, y: 90))
    let editor = canvas.subviews.compactMap { $0 as? NSTextView }.first!
    try expect(editor.frame.origin == CGPoint(x: -30, y: 90))
    editor.string = "A typed note\nSecond line"
    store.finishTextEditing?()
    try expect(store.document.nodes.count == 1)
    let text = store.document.nodes.values.first!
    try expect(text.label == "A typed note\nSecond line" && text.position == Point(x: -48, y: 78))
    store.undo(); try expect(store.document.nodes.isEmpty && !store.canUndo)
    canvas.beginText(at: CGPoint(x: 90, y: 100))
    let canceled = canvas.subviews.compactMap { $0 as? NSTextView }.first!
    canceled.string = "Cancel this"
    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    canceled.keyDown(with: escape)
    try expect(store.document.nodes.isEmpty && canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty)
}

@MainActor func timelineMouseMoveResizeAndReorderKeepDatesConsistent() throws {
    var d = DocumentMode.timeline.blank(); d.timeline = .example(start: "2026-10-26")
    let store = EditorStore(document: d), (window, canvas) = canvasFixture(store)
    defer { window.contentView = nil; window.close() }
    let g = TimelineGeometry(d.timeline!), bar = g.bars["build"]!
    drag(canvas, from: CGPoint(x: bar.midX, y: bar.midY), to: CGPoint(x: bar.midX + 3 * g.dayWidth, y: bar.midY))
    try expect(store.document.timeline?.tasks[1].start == "2026-11-03" && store.document.timeline?.tasks[1].duration == 10)
    store.undo(); try expect(store.document == d && !store.canUndo)
    drag(canvas, from: CGPoint(x: bar.maxX - 1, y: bar.midY), to: CGPoint(x: bar.maxX - 1 + 2 * g.dayWidth, y: bar.midY))
    try expect(store.document.timeline?.tasks[1].duration == 12)
    store.undo()
    drag(canvas, from: CGPoint(x: bar.minX + 1, y: bar.midY), to: CGPoint(x: bar.minX + 1 + 2 * g.dayWidth, y: bar.midY))
    try expect(store.document.timeline?.tasks[1].duration == 8 && store.document.timeline?.tasks[1].finish == d.timeline?.tasks[1].finish)
    store.undo()
    drag(canvas, from: CGPoint(x: 60, y: bar.midY), to: CGPoint(x: 60, y: bar.midY + 52))
    try expect(store.document.timeline?.tasks[2].id == "build")
    store.undo()
    store.editTask("discovery") { $0.dependencies = ["launch"] }
    try expect(store.document == d && store.errorMessage?.contains("cycle") == true)
}

@MainActor func modeClipboardUsesFreshIDsAndPreservesOtherItems() throws {
    let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
    let drawing = EditorStore(document: DocumentMode.drawing.blank()); drawing.pasteboard = board
    drawing.addStroke([Point(x: 10, y: 20), Point(x: 30, y: 40)])
    let original = drawing.document.drawing!.strokes[0]
    try expect(drawing.copySelection()); drawing.pasteSelection()
    try expect(drawing.document.drawing?.strokes.count == 2 && drawing.document.drawing!.strokes[1].id != original.id)
    try expect(drawing.document.drawing!.strokes[1].points[0] == Point(x: 34, y: 44))
    drawing.undo(); try expect(drawing.document.drawing?.strokes == [original])
    let timeline = EditorStore(document: DocumentMode.timeline.blank()); timeline.pasteboard = board
    timeline.pasteSelection(); try expect(timeline.document.timeline?.tasks.isEmpty == true)
    timeline.addTask(start: "2026-10-26"); let task = timeline.document.timeline!.tasks[0]
    try expect(timeline.copySelection()); timeline.pasteSelection()
    try expect(timeline.document.timeline?.tasks.count == 2 && timeline.document.timeline!.tasks[1].id != task.id)
    timeline.undo(); try expect(timeline.document.timeline?.tasks == [task])
}

@MainActor func modeFilesRestoreAndSwitchingCommitsPendingText() throws {
    let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("drawing.diagram.json")
    _ = try DiagramFiles.write(DocumentMode.drawing.blank(), to: file)
    let workspace = WorkspaceStore(defaults: nil, confirmClose: { _ in true })
    workspace.open(file); let drawing = workspace.activeStore
    drawing.finishTextEditing = { drawing.finishTextEditing = nil; drawing.addFreeText("Pending text", at: CGPoint(x: 20, y: 30)) }
    workspace.newTab(mode: .timeline)
    try expect(drawing.document.nodes.values.first?.label == "Pending text" && drawing.dirty)
    try expect(drawing.save())
    let (saved, _) = try DiagramFiles.read(file)
    try expect(saved.mode == .drawing && saved.nodes.values.first?.label == "Pending text")
    drawing.stopAutosave()
    let reopened = WorkspaceStore(defaults: nil); reopened.open(file)
    try expect(reopened.activeStore.document == saved)
}
