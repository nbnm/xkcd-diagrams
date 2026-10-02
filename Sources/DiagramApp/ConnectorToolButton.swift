import AppKit
import SwiftUI

/// Track the palette gesture directly so a button press cannot swallow the drag.
struct ConnectorToolButton: NSViewRepresentable {
    @ObservedObject var store: EditorStore
    var toolbar = false
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> ConnectorToolView { ConnectorToolView(store: store) }
    func updateNSView(_ view: ConnectorToolView, context: Context) {
        view.store = store
        view.label.rootView = AnyView(HStack(spacing: toolbar ? 6 : 10) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: toolbar ? 16 : 18)).frame(width: toolbar ? 20 : 28)
            Text("Connector").font(.system(size: toolbar ? 13 : 12, weight: toolbar ? .regular : .semibold))
            if !toolbar { Spacer() }
        }.foregroundStyle(store.connecting ? Color.accentColor : .primary)
            .padding(.horizontal, toolbar ? 4 : 7)
            .environment(\.colorScheme, colorScheme))
    }
}

@MainActor final class ConnectorToolView: NSView {
    var store: EditorStore
    let label = NSHostingView(rootView: AnyView(EmptyView()))
    private var pressPoint: CGPoint?, dragged = false
    private var previousCursor: NSCursor?
    private var canvas: CanvasView? {
        func find(in view: NSView) -> CanvasView? {
            if let canvas = view as? CanvasView { return canvas }
            for child in view.subviews { if let canvas = find(in: child) { return canvas } }
            return nil
        }
        return window?.contentView.flatMap { find(in: $0) }
    }
    override var acceptsFirstResponder: Bool { true }
    init(store: EditorStore) {
        self.store = store
        super.init(frame: .zero)
        addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor), label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("Connector")
        toolTip = "Drag Connector onto a source, then click or drag to its destination (⌘K)"
        setAccessibilityHelp(toolTip)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); pressPoint = convert(event.locationInWindow, from: nil); dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = pressPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        if !dragged {
            guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            dragged = true; previousCursor = NSCursor.current; NSCursor.crosshair.set()
        }
        canvas?.updateConnectorToolDrag(at: event.locationInWindow)
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { canvas?.dropConnectorTool(at: event.locationInWindow) }
        else if pressPoint != nil, bounds.contains(convert(event.locationInWindow, from: nil)) { store.toggleConnector() }
        canvas?.clearConnectorToolDrag(); previousCursor?.set(); previousCursor = nil; pressPoint = nil; dragged = false
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.characters == " " { store.toggleConnector() }
        else if event.keyCode == 53 {
            store.cancelConnection(); canvas?.clearConnectorToolDrag(); previousCursor?.set(); previousCursor = nil; pressPoint = nil; dragged = false
        }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { store.toggleConnector(); return true }
}
