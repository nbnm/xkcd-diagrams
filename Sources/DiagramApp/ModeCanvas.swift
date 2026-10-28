import AppKit
import SwiftUI
import DiagramCore
import CoreText

struct ModeCanvas: NSViewRepresentable {
    @ObservedObject var store: EditorStore
    func makeNSView(context: Context) -> ModeCanvasView { ModeCanvasView(store: store) }
    func updateNSView(_ view: ModeCanvasView, context: Context) {
        view.setAccessibilityLabel(store.document.mode.title + " canvas")
        if view.lastFit != store.fitRequest { view.lastFit = store.fitRequest; view.fit() }
        if view.lastZoom != store.zoomRequest { let steps = store.zoomRequest - view.lastZoom; view.lastZoom = store.zoomRequest; view.zoomBy(steps) }
        if view.lastLabelEdit != store.labelEditRequest {
            view.lastLabelEdit = store.labelEditRequest
            if store.document.mode == .drawing, let id = store.selection, store.document.nodes[id] != nil { view.beginText(id: id) }
        }
        view.window?.invalidateCursorRects(for: view); view.needsDisplay = true
    }
}

@MainActor final class ModeCanvasView: NSView, NSTextViewDelegate {
    let store: EditorStore
    var zoom: CGFloat = 1, offset = CGPoint(x: 50, y: 65)
    var lastFit: Int, lastZoom: Int, lastLabelEdit: Int
    private var monitor: Any?
    private var press: CGPoint?, lastPointer: CGPoint?, dragID: String?, gesture = ""
    private var delta = CGPoint.zero, samples: [Point] = [], erased = Set<String>()
    private var eraserPaths: [(String, CGPath)] = []
    private var startVersion = 0
    private var textEditor: CanvasTextEditor?, editingID: String?, textPosition = CGPoint.zero
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(store: EditorStore) {
        self.store = store; lastFit = store.fitRequest; lastZoom = store.zoomRequest; lastLabelEdit = store.labelEditRequest
        super.init(frame: .zero); setAccessibilityLabel(store.document.mode.title + " canvas")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); guard window != nil else { return }
        store.finishTextEditing = { [weak self] in self?.finishText(commit: true) }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            if let viewport = self.store.canvasViewport { self.zoom = viewport.zoom; self.offset = viewport.offset; self.publishZoom() }
            else { self.fit() }
            window.makeFirstResponder(self); self.needsDisplay = true
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, (event.window ?? NSApp.keyWindow) === window, window.attachedSheet == nil,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            if window.firstResponder === self.textEditor { return event }
            if event.keyCode == 53 {
                self.clearGesture(); self.store.drawingTool = .select; window.makeFirstResponder(self); return nil
            }
            guard !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField), !event.isARepeat,
                  let key = event.charactersIgnoringModifiers?.uppercased() else { return event }
            if self.store.document.mode == .drawing, let tool = FreeDrawingTool.allCases.first(where: { $0.key == key }) {
                self.clearGesture(); self.store.chooseDrawingTool(tool); window.makeFirstResponder(self); return nil
            }
            if self.store.document.mode == .timeline, key == "N" || key == "M" {
                self.store.addTask(milestone: key == "M"); window.makeFirstResponder(self); return nil
            }
            return event
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { remember(); store.finishTextEditing = nil }
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        super.viewWillMove(toWindow: newWindow)
    }
    override func resetCursorRects() {
        let cursor: NSCursor = store.document.mode == .drawing && store.drawingTool != .select ? .crosshair : .arrow
        addCursorRect(bounds, cursor: cursor)
    }
    func fit() {
        finishText(commit: true)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let r = store.scene.layout.bounds
        zoom = max(0.2, min(1.2, min((bounds.width - 70) / max(1, r.width), (bounds.height - 70) / max(1, r.height))))
        offset = CGPoint(x: (bounds.width - r.width * zoom) / 2 - r.minX * zoom, y: (bounds.height - r.height * zoom) / 2 - r.minY * zoom)
        remember(); publishZoom(); needsDisplay = true
    }
    func zoomBy(_ steps: Int) { adjustZoom(zoom * pow(1.25, CGFloat(steps)), at: CGPoint(x: bounds.midX, y: bounds.midY)) }
    private func world(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - offset.x) / zoom, y: (p.y - offset.y) / zoom) }
    private func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom + offset.x, y: p.y * zoom + offset.y) }
    private func remember() { store.canvasViewport = CanvasViewport(zoom: zoom, offset: offset) }
    private func publishZoom() { DispatchQueue.main.async { [weak self] in if let self { self.store.zoomScale = Double(self.zoom) } } }
    private func adjustZoom(_ next: CGFloat, at anchor: CGPoint) {
        finishText(commit: true); let p = world(anchor); zoom = min(3, max(0.2, next))
        offset = CGPoint(x: anchor.x - p.x * zoom, y: anchor.y - p.y * zoom); remember(); publishZoom(); needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { adjustZoom(zoom * exp(-event.scrollingDeltaY * 0.015), at: convert(event.locationInWindow, from: nil)) }
        else { finishText(commit: true); offset.x -= event.scrollingDeltaX; offset.y -= event.scrollingDeltaY; remember(); needsDisplay = true }
    }
    override func magnify(with event: NSEvent) { adjustZoom(zoom * (1 + event.magnification), at: convert(event.locationInWindow, from: nil)) }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        store.scene.drawBackground(in: ctx, bounds: bounds)
        ctx.saveGState(); ctx.translateBy(x: offset.x, y: offset.y); ctx.scaleBy(x: zoom, y: zoom)
        let visible = CGRect(origin: world(.zero), size: CGSize(width: bounds.width / zoom, height: bounds.height / zoom))
        store.scene.drawBackground(in: ctx, bounds: visible); store.scene.draw(in: ctx)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(1.5 / zoom)
        if let id = store.selection, let r = itemFrame(id) {
            let moved = gesture == "move" && dragID == id ? r.offsetBy(dx: delta.x, dy: delta.y) : r
            ctx.stroke(moved.insetBy(dx: -5 / zoom, dy: -5 / zoom))
        }
        if gesture.hasPrefix("task"), let id = dragID, let r = taskPreview(id) {
            ctx.saveGState(); ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor); ctx.fill(r)
            ctx.setLineDash(phase: 0, lengths: [5 / zoom, 3 / zoom]); ctx.stroke(r); ctx.restoreGState()
        }
        if !samples.isEmpty, let drawing = store.document.drawing {
            ctx.addPath(FreehandGeometry.path(InkStroke(points: samples, strokeWidth: drawing.strokeWidth, smoothing: drawing.smoothing)))
            ctx.setStrokeColor(store.scene.palette.color(0.14, role: .outline)); ctx.setLineWidth(CGFloat(drawing.strokeWidth)); ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
        }
        for id in erased {
            if let r = itemFrame(id) { ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor); ctx.fill(r.insetBy(dx: -3, dy: -3)) }
        }
        ctx.restoreGState()
        if store.document.mode == .drawing, store.document.nodes.isEmpty, store.document.drawing?.strokes.isEmpty == true, samples.isEmpty, textEditor == nil {
            let text = "Draw freely with the mouse\nP  Pen    T  Text    V  Select    E  Eraser"
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineSpacing = 8
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]).draw(in: CGRect(x: bounds.midX - 210, y: bounds.midY - 35, width: 420, height: 80))
        }
    }
    private func itemFrame(_ id: String) -> CGRect? {
        if let stroke = store.document.drawing?.strokes.first(where: { $0.id == id }) { return FreehandGeometry.path(stroke).boundingBoxOfPath.insetBy(dx: -stroke.strokeWidth / 2, dy: -stroke.strokeWidth / 2) }
        return store.scene.layout.frames[id]
    }
    private func hit(_ p: CGPoint) -> String? {
        if store.document.mode == .timeline {
            guard let timeline = store.document.timeline else { return nil }
            let g = TimelineGeometry(timeline)
            return timeline.tasks.reversed().first { (g.bars[$0.id]?.insetBy(dx: -5 / zoom, dy: -5 / zoom).contains(p) == true) || (p.x < g.labelWidth && g.rows[$0.id]?.contains(p) == true) }?.id
        }
        if let id = store.scene.layout.order.reversed().first(where: { store.document.nodes[$0] != nil && store.scene.layout.frames[$0]?.contains(p) == true }) { return id }
        return store.document.drawing?.strokes.reversed().first { FreehandGeometry.hit($0, point: p, tolerance: 6 / zoom) }?.id
    }
    private func clearGesture() { press = nil; dragID = nil; lastPointer = nil; gesture = ""; delta = .zero; samples = []; erased = []; eraserPaths = []; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {
        finishText(commit: true); window?.makeFirstResponder(self); clearGesture()
        let p = convert(event.locationInWindow, from: nil), w = world(p)
        press = p; lastPointer = w; startVersion = store.historyVersion
        if event.modifierFlags.contains(.option) { gesture = "pan"; return }
        if store.document.mode == .drawing {
            let id = hit(w)
            if event.clickCount == 2, let id, store.document.nodes[id] != nil { clearGesture(); beginText(id: id); return }
            switch store.drawingTool {
            case .pen: store.selection = nil; gesture = "pen"; appendSample(w)
            case .text: clearGesture(); beginText(id: id.flatMap { store.document.nodes[$0] != nil ? $0 : nil }, at: w)
            case .eraser:
                gesture = "erase"
                eraserPaths = (store.document.drawing?.strokes ?? []).map { ($0.id, FreehandGeometry.path($0).copy(strokingWithWidth: max(CGFloat($0.strokeWidth), 14 / zoom), lineCap: .round, lineJoin: .round, miterLimit: 2)) }
                collectErase(from: w, to: w)
            case .select: store.selection = id; dragID = id; gesture = id == nil ? "pan" : "move"
            }
        } else {
            let id = hit(w); store.selection = id; dragID = id
            guard let id, let task = store.document.timeline?.tasks.first(where: { $0.id == id }), let r = itemFrame(id) else {
                if event.clickCount == 2, let timeline = store.document.timeline { store.addTask(start: TimelineGeometry(timeline).date(at: w.x)) }
                gesture = "pan"; return
            }
            if event.clickCount == 2 { store.labelEditRequest += 1; clearGesture(); return }
            let labels = TimelineGeometry(store.document.timeline!).labelWidth
            gesture = w.x < labels ? "task-reorder" : !task.milestone && abs(w.x - r.minX) < 7 / zoom ? "task-left" : !task.milestone && abs(w.x - r.maxX) < 7 / zoom ? "task-right" : "task-move"
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = press else { return }
        let p = convert(event.locationInWindow, from: nil), w = world(p)
        if gesture == "pan" { offset.x += p.x - start.x; offset.y += p.y - start.y; press = p; remember() }
        else if gesture == "pen" { appendSample(w) }
        else if gesture == "erase" { collectErase(from: lastPointer ?? w, to: w) }
        else { delta = CGPoint(x: (p.x - start.x) / zoom, y: (p.y - start.y) / zoom) }
        lastPointer = w; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { clearGesture() }
        guard store.historyVersion == startVersion else { return }
        if gesture == "pen" { appendSample(world(convert(event.locationInWindow, from: nil))); store.addStroke(samples) }
        else if gesture == "erase" { store.eraseModeItems(erased) }
        else if gesture == "move", let id = dragID, hypot(delta.x, delta.y) > 1 {
            if store.document.nodes[id] != nil, let frame = itemFrame(id) {
                store.mutate("Move text", coalescingKey: UUID().uuidString) { $0.nodes[id]?.position = Point(x: frame.minX + delta.x, y: frame.minY + delta.y) }
            }
            else { store.moveStroke(id, delta: delta) }
        } else if gesture.hasPrefix("task"), let id = dragID, let timeline = store.document.timeline {
            let days = Int((delta.x / timeline.scale.dayWidth).rounded())
            if gesture == "task-reorder" { store.reorderTask(id, by: Int((delta.y / 52).rounded())) }
            else if days != 0 {
                store.editTask(id, action: "Drag task", coalescingKey: UUID().uuidString) { task in
                    if gesture == "task-left" { let shift = min(days, task.duration - 1); task.start = TimelineDate.adding(shift, to: task.start) ?? task.start; task.duration -= shift }
                    else if gesture == "task-right" { task.duration = max(1, task.duration + days) }
                    else { task.start = TimelineDate.adding(days, to: task.start) ?? task.start }
                }
            }
        }
    }
    private func appendSample(_ p: CGPoint) {
        guard p.x.isFinite, p.y.isFinite, abs(p.x) <= 100000, abs(p.y) <= 100000 else { return }
        if let last = samples.last, hypot(p.x - last.x, p.y - last.y) < 0.6 / zoom { return }
        if samples.count >= 20000 { samples[samples.count - 1] = Point(x: p.x, y: p.y) }
        else { samples.append(Point(x: p.x, y: p.y)) }
    }
    private func collectErase(from a: CGPoint, to b: CGPoint) {
        let count = max(1, min(512, Int(ceil(hypot(b.x - a.x, b.y - a.y) / max(1, 5 / zoom)))))
        for i in 0...count {
            let t = CGFloat(i) / CGFloat(count), p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            for (id, path) in eraserPaths where !erased.contains(id) {
                if path.boundingBoxOfPath.contains(p) && path.contains(p) { erased.insert(id) }
            }
            for id in store.document.nodes.keys where store.scene.layout.frames[id]?.contains(p) == true { erased.insert(id) }
        }
    }
    private func taskPreview(_ id: String) -> CGRect? {
        guard let r = itemFrame(id), let timeline = store.document.timeline, let task = timeline.tasks.first(where: { $0.id == id }) else { return nil }
        let days = Int((delta.x / timeline.scale.dayWidth).rounded()), dx = CGFloat(days) * timeline.scale.dayWidth
        if gesture == "task-reorder" { return r.offsetBy(dx: 0, dy: (delta.y / 52).rounded() * 52) }
        if gesture == "task-left" { let shift = CGFloat(min(days, task.duration - 1)) * timeline.scale.dayWidth; return CGRect(x: r.minX + shift, y: r.minY, width: r.width - shift, height: r.height) }
        if gesture == "task-right" { return CGRect(x: r.minX, y: r.minY, width: max(timeline.scale.dayWidth, r.width + dx), height: r.height) }
        return r.offsetBy(dx: dx, dy: 0)
    }
    func beginText(id: String? = nil, at point: CGPoint = .zero) {
        finishText(commit: true)
        editingID = id; store.selection = id
        textPosition = id.flatMap { store.document.nodes[$0]?.position }.map { CGPoint(x: $0.x, y: $0.y) } ?? CGPoint(x: point.x - 18, y: point.y - 12)
        let origin = screen(CGPoint(x: textPosition.x + 18, y: textPosition.y + 12))
        let width = id.flatMap { store.scene.layout.frames[$0]?.width }.map { max(40, $0 - 36) } ?? 224
        let editor = CanvasTextEditor(frame: CGRect(origin: origin, size: CGSize(width: width * zoom, height: 130 * zoom)))
        editor.identifier = .init("free-drawing-text"); editor.setAccessibilityLabel("Canvas text")
        editor.isRichText = false; editor.allowsUndo = true; editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
        editor.string = id.flatMap { store.document.nodes[$0]?.label } ?? ""
        let size = id.map { store.document.fontSize(for: $0) } ?? store.document.theme.fontSize
        let font = Typography.font(store.document.theme, size: CGFloat(size) * zoom)
        editor.font = NSFont(name: CTFontCopyPostScriptName(font) as String, size: CGFloat(size) * zoom) ?? .systemFont(ofSize: CGFloat(size) * zoom)
        editor.textColor = NSColor(cgColor: store.scene.palette.color(0.12))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5 * zoom
        editor.defaultParagraphStyle = paragraph
        editor.backgroundColor = NSColor(cgColor: store.scene.palette.background) ?? .textBackgroundColor
        editor.drawsBackground = true; editor.textContainerInset = .zero; editor.textContainer?.lineFragmentPadding = 0
        editor.delegate = self; editor.finish = { [weak self] commit in self?.finishText(commit: commit) }
        textEditor = editor; addSubview(editor); window?.makeFirstResponder(editor); editor.selectAll(nil)
        store.status = "Type text · ⌘Return to finish · Escape cancels"; needsDisplay = true
    }
    private func finishText(commit: Bool) {
        guard let editor = textEditor else { return }
        textEditor = nil; let id = editingID; editingID = nil; let value = editor.string
        editor.delegate = nil; editor.finish = nil; editor.removeFromSuperview()
        if commit {
            if let id { store.mutate("Edit text", coalescingKey: id) { $0.nodes[id]?.label = value } }
            else if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.addFreeText(value, at: textPosition) }
        }
        if window?.firstResponder === editor { window?.makeFirstResponder(self) }
        store.status = "Ready"; needsDisplay = true
    }
    func textDidEndEditing(_ notification: Notification) { finishText(commit: true) }
    func textDidChange(_ notification: Notification) { store.objectWillChange.send() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: store.deleteSelection()
        case 123: store.nudge(event.modifierFlags.contains(.shift) ? -10 : -1, 0)
        case 124: store.nudge(event.modifierFlags.contains(.shift) ? 10 : 1, 0)
        case 125: store.nudge(0, 1)
        case 126: store.nudge(0, -1)
        case 53: clearGesture(); store.selection = nil; store.drawingTool = .select
        default: super.keyDown(with: event)
        }
    }
    @objc func copy(_ sender: Any?) { store.copySelection() }
    @objc func paste(_ sender: Any?) { store.pasteSelection() }
    @objc func cut(_ sender: Any?) { if store.copySelection() { store.deleteSelection() } }
}

@MainActor private final class CanvasTextEditor: NSTextView {
    var finish: ((Bool) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish?(false) }
        else if event.keyCode == 36 && event.modifierFlags.contains(.command) { finish?(true) }
        else { super.keyDown(with: event) }
    }
}
