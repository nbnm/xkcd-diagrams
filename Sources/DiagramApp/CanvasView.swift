import AppKit
import SwiftUI
import DiagramCore

struct DiagramCanvas: NSViewRepresentable {
    @ObservedObject var store: EditorStore
    func makeNSView(context: Context) -> CanvasView { CanvasView(store: store) }
    func updateNSView(_ view: CanvasView, context: Context) {
        view.store = store
        if view.lastFitRequest != store.fitRequest { view.lastFitRequest = store.fitRequest; view.fit() }
        if view.lastZoomRequest != store.zoomRequest {
            let steps = store.zoomRequest - view.lastZoomRequest
            view.lastZoomRequest = store.zoomRequest
            view.zoomBy(steps: steps)
        }
        view.needsDisplay = true
    }
}

@MainActor final class CanvasView: NSView {
    var store: EditorStore
    var zoom: CGFloat = 1, offset = CGPoint(x: 65, y: 65)
    var lastFitRequest = -1
    var lastZoomRequest: Int
    private var dragStart: CGPoint?, dragID: String?, dragDelta = CGPoint.zero
    private var panning = false
    private var connectionGesture = false, connectionDragged = false
    private var connectionPress: String?, connectionClickSource: String?, connectionDropTarget: String?
    private var connectionPointer: CGPoint?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(store: EditorStore) { self.store = store; lastZoomRequest = store.zoomRequest; super.init(frame: .zero); registerForDraggedTypes([.string]); setAccessibilityLabel("Diagram canvas") }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window != nil { DispatchQueue.main.async { self.fit() } } }
    func fit() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let r = store.scene.layout.bounds
        zoom = min(1.2, max(0.25, min((bounds.width - 90) / max(r.width, 1), (bounds.height - 90) / max(r.height, 1))))
        offset = CGPoint(x: (bounds.width - r.width * zoom) / 2 - r.minX * zoom, y: (bounds.height - r.height * zoom) / 2 - r.minY * zoom)
        publishZoom()
        needsDisplay = true
    }
    func zoomBy(steps: Int) {
        adjustZoom(zoom * pow(1.25, CGFloat(steps)), anchor: CGPoint(x: bounds.midX, y: bounds.midY))
    }
    private func world(_ point: CGPoint) -> CGPoint { CGPoint(x: (point.x - offset.x) / zoom, y: (point.y - offset.y) / zoom) }
    override func draw(_ dirtyRect: NSRect) {
        (NSColor(cgColor: store.scene.palette.background) ?? .white).setFill(); bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Blueprint uses shared drafting paper; other themes have editor-only alignment dots.
        ctx.setFillColor(CGColor(gray: store.scene.palette.dark ? 0.24 : 0.86, alpha: 1))
        let grid: CGFloat = 24 * zoom
        if !store.scene.palette.blueprint && grid >= 12 {
            for x in stride(from: offset.x.truncatingRemainder(dividingBy: grid), through: bounds.width, by: grid) {
                for y in stride(from: offset.y.truncatingRemainder(dividingBy: grid), through: bounds.height, by: grid) { ctx.fillEllipse(in: CGRect(x: x, y: y, width: 1, height: 1)) }
            }
        }
        ctx.saveGState(); ctx.translateBy(x: offset.x, y: offset.y); ctx.scaleBy(x: zoom, y: zoom)
        if store.scene.palette.blueprint {
            let origin = world(.zero)
            store.scene.drawBackground(in: ctx, bounds: CGRect(origin: origin, size: CGSize(width: bounds.width / zoom, height: bounds.height / zoom)))
        }
        if let grid = store.scene.layout.grids[store.document.root], let root = store.document.containers[store.document.root], let frame = store.scene.layout.frames[store.document.root] {
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(gray: store.scene.palette.lightInk ? 1 : 0.25, alpha: 0.16))
            ctx.setLineWidth(1 / zoom); ctx.setLineDash(phase: 0, lengths: [4 / zoom, 4 / zoom])
            for row in 1...grid.rowHeights.count {
                for column in 1...grid.columnWidths.count {
                    let cell = grid.frame(GridCell(row: row, column: column)).offsetBy(dx: frame.minX + root.layout.padding, dy: frame.minY + root.layout.padding)
                    ctx.stroke(cell.insetBy(dx: -4, dy: -4))
                }
            }
            ctx.restoreGState()
        }
        store.scene.draw(in: ctx)
        if let id = store.selection, let frame = store.scene.layout.frames[id] {
            let r = frame.offsetBy(dx: dragID == id ? dragDelta.x : 0, dy: dragID == id ? dragDelta.y : 0).insetBy(dx: -5, dy: -5)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(1.5 / zoom)
            if dragID == id { ctx.setLineDash(phase: 0, lengths: [5 / zoom, 4 / zoom]) }
            ctx.stroke(r)
        } else if let id = store.selection, let points = store.scene.layout.routes[id] {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(3 / zoom)
            ctx.beginPath(); ctx.move(to: points[0]); for point in points.dropFirst() { ctx.addLine(to: point) }; ctx.strokePath()
        }
        if store.connecting, let id = store.connectionStart, let frame = store.scene.layout.frames[id] {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(2 / zoom); ctx.stroke(frame.insetBy(dx: -8, dy: -8))
        }
        if store.connecting, connectionDragged, let source = connectionPress, let pointer = connectionPointer {
            let target = connectionEndpoint(at: pointer).flatMap { $0 == source ? nil : $0 }
            if let points = store.scene.layout.connectionPreview(from: source, to: target, at: pointer, document: store.document), let first = points.first {
                ctx.saveGState(); ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(2 / zoom)
                ctx.setLineDash(phase: 0, lengths: [5 / zoom, 4 / zoom]); ctx.beginPath(); ctx.move(to: first)
                for point in points.dropFirst() { ctx.addLine(to: point) }; ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
                if let target, let frame = store.scene.layout.frames[target] { ctx.stroke(frame.insetBy(dx: -8, dy: -8)) }
                ctx.restoreGState()
            }
        }
        if let target = connectionDropTarget, let frame = store.scene.layout.frames[target] {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(2 / zoom); ctx.stroke(frame.insetBy(dx: -8, dy: -8))
        }
        ctx.restoreGState()
    }
    private func connectionEndpoint(at point: CGPoint) -> String? {
        let node = store.scene.layout.order.reversed().first { store.document.nodes[$0] != nil && store.scene.layout.frames[$0]?.contains(point) == true }
        return node ?? store.scene.layout.hit(point, document: store.document)
    }
    func updateConnectorToolDrag(at location: CGPoint) {
        let point = convert(location, from: nil)
        connectionDropTarget = bounds.contains(point) ? connectionEndpoint(at: world(point)) : nil
        needsDisplay = true
    }
    func clearConnectorToolDrag() { connectionDropTarget = nil; needsDisplay = true }
    func dropConnectorTool(at location: CGPoint) {
        let point = convert(location, from: nil)
        guard bounds.contains(point) else { return }
        clearGesture(); window?.makeFirstResponder(self)
        store.beginConnection(from: connectionEndpoint(at: world(point)))
    }
    private func clearGesture() {
        dragStart = nil; dragID = nil; dragDelta = .zero; panning = false
        connectionGesture = false; connectionDragged = false; connectionPress = nil; connectionClickSource = nil; connectionPointer = nil
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        clearGesture()
        dragStart = p; dragDelta = .zero
        panning = event.modifierFlags.contains(.option)
        if panning { return }
        let w = world(p)
        if store.connecting {
            connectionGesture = true; connectionPress = connectionEndpoint(at: w); connectionClickSource = store.connectionStart
            connectionPointer = w
            if store.connectionStart == nil, let source = connectionPress { store.beginConnection(from: source) }
            needsDisplay = true; return
        }
        let node = store.scene.layout.order.reversed().first { store.document.nodes[$0] != nil && store.scene.layout.frames[$0]!.contains(w) }
        if let node { store.select(node); dragID = store.connecting ? nil : node }
        else {
            let edge = store.document.connectors.keys.sorted().first { id in
                if store.scene.layout.labelFrames[id]?.contains(w) == true { return true }
                let points = store.scene.layout.routes[id]!
                return zip(points, points.dropFirst()).contains { distance(w, to: $0, and: $1) < 7 / zoom }
            }
            let hit = edge ?? store.scene.layout.hit(w, document: store.document)
            store.select(hit); dragID = edge == nil && !store.connecting ? hit : nil; panning = hit == nil
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        if connectionGesture {
            guard store.connecting, let source = connectionPress else { return }
            if hypot(p.x - start.x, p.y - start.y) > 3 {
                if !connectionDragged { store.beginConnection(from: source) }
                connectionDragged = true; connectionPointer = world(p); needsDisplay = true
            }
            return
        }
        if panning { offset.x += p.x - start.x; offset.y += p.y - start.y; dragStart = p }
        else { dragDelta = CGPoint(x: (p.x - start.x) / zoom, y: (p.y - start.y) / zoom) }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if connectionGesture {
            if store.connecting {
                let target = connectionEndpoint(at: world(convert(event.locationInWindow, from: nil)))
                if connectionDragged, let source = connectionPress, let target, source != target {
                    store.connect(from: source, to: target)
                } else if !connectionDragged, let pressed = connectionPress, target == pressed {
                    if let source = connectionClickSource, source != pressed { store.connect(from: source, to: pressed) }
                    else { store.beginConnection(from: pressed) }
                }
            }
            clearGesture(); return
        }
        if let id = dragID, hypot(dragDelta.x, dragDelta.y) > 2 { store.move(id, to: world(convert(event.locationInWindow, from: nil)), delta: dragDelta) }
        clearGesture()
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            adjustZoom(zoom * exp(-event.scrollingDeltaY * 0.015), anchor: convert(event.locationInWindow, from: nil))
        } else { offset.x -= event.scrollingDeltaX; offset.y -= event.scrollingDeltaY; needsDisplay = true }
    }
    override func magnify(with event: NSEvent) { adjustZoom(zoom * (1 + event.magnification), anchor: convert(event.locationInWindow, from: nil)) }
    private func adjustZoom(_ next: CGFloat, anchor: CGPoint) {
        let p = world(anchor); zoom = min(3, max(0.2, next)); offset = CGPoint(x: anchor.x - p.x * zoom, y: anchor.y - p.y * zoom)
        publishZoom(); needsDisplay = true
    }
    private func publishZoom() {
        // NSViewRepresentable updates may be in progress; publish on the next UI cycle.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let scale = Double(self.zoom)
            if self.store.zoomScale != scale { self.store.zoomScale = scale }
        }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle both physical = and + keys even when an inspector field has focus.
        if window?.attachedSheet == nil, event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control) {
            if ["+", "="].contains(event.charactersIgnoringModifiers ?? "") { store.zoomIn(); return true }
            if event.charactersIgnoringModifiers == "-" { store.zoomOut(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command), step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
        if command && event.charactersIgnoringModifiers == "z" { event.modifierFlags.contains(.shift) ? store.redo() : store.undo(); return }
        if command && ["+", "="].contains(event.charactersIgnoringModifiers ?? "") { store.zoomIn(); return }
        if command && event.charactersIgnoringModifiers == "-" { store.zoomOut(); return }
        switch event.keyCode {
        case 51, 117: store.deleteSelection()
        case 123: store.nudge(-step, 0)
        case 124: store.nudge(step, 0)
        case 125: store.nudge(0, step)
        case 126: store.nudge(0, -step)
        case 53: store.cancelConnection(); store.selection = nil; clearGesture()
        default: super.keyDown(with: event)
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateLibraryDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateLibraryDrag(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { connectionDropTarget = nil; needsDisplay = true }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { connectionDropTarget = nil; needsDisplay = true }
    private func updateLibraryDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let id = sender.draggingPasteboard.string(forType: .string) else { return [] }
        connectionDropTarget = id == "__connector" ? connectionEndpoint(at: world(convert(sender.draggingLocation, from: nil))) : nil
        needsDisplay = true
        return id == "__connector" || id == "__container" || store.library.contains(where: { $0.id == id }) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { connectionDropTarget = nil; needsDisplay = true }
        guard let id = sender.draggingPasteboard.string(forType: .string) else { return false }
        let p = world(convert(sender.draggingLocation, from: nil))
        if id == "__connector" {
            clearGesture(); window?.makeFirstResponder(self)
            store.beginConnection(from: connectionEndpoint(at: p)); return true
        }
        let parent = store.scene.layout.order.reversed().first { store.document.containers[$0] != nil && store.scene.layout.frames[$0]!.contains(p) } ?? store.document.root
        if id == "__container" { store.addContainer(point: p, parent: parent); return true }
        guard let item = store.library.first(where: { $0.id == id }) else { return false }
        store.add(item, point: p, parent: parent); return true
    }
    private func distance(_ p: CGPoint, to a: CGPoint, and b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
        if length == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
}
