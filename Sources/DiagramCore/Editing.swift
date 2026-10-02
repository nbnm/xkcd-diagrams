import Foundation
import CoreGraphics

public enum DiagramEditing {
    public static func configureGrid(rows: Int, columns: Int, container id: String, document: inout Diagram) throws {
        guard (1...32).contains(rows), (1...32).contains(columns), let container = document.containers[id] else {
            throw DiagramError.message("Choose an existing container and 1–32 rows and columns.")
        }
        var next = document
        next.containers[id]?.layout.mode = .grid
        next.containers[id]?.layout.rows = rows; next.containers[id]?.layout.columns = columns
        next.containers[id]?.layout.cells = container.layout.cells?.filter { _, cell in
            cell.row <= rows && cell.rowSpan <= rows - cell.row + 1 && cell.column <= columns && cell.columnSpan <= columns - cell.column + 1
        }
        let issues = Validator.validate(next)
        guard issues.isEmpty else { throw DiagramError.invalid(issues) }
        rerouteConnections(in: id, document: &next)
        document = next
    }

    public static func ensureGridRoom(container id: String, document: inout Diagram) throws {
        guard let container = document.containers[id], container.layout.mode == .grid else { return }
        var next = document
        let columns = container.layout.columns ?? 3
        guard (1...32).contains(columns) else { throw DiagramError.message("Choose 1–32 columns.") }
        next.containers[id]?.layout.columns = columns
        let start = container.layout.rows ?? max(2, (container.children.count + columns - 1) / columns)
        guard (1...32).contains(start) else { throw DiagramError.message("The grid supports up to 32 rows. Add columns to make room for more items.") }
        for rows in start...32 {
            next.containers[id]?.layout.rows = rows
            do { _ = try GridLayout.plan(next.containers[id]!, id: id); document = next; return }
            catch DiagramError.invalid(let issues) where issues.allSatisfy({ $0.code == "grid-capacity" }) { continue }
        }
        throw DiagramError.message("The grid supports up to 32 rows. Add columns to make room for more items.")
    }

    public static func setGridCell(_ cell: GridCell, element id: String, document: inout Diagram) throws {
        guard let parent = document.parent(of: id), let container = document.containers[parent], container.layout.mode == .grid else {
            throw DiagramError.message("Select an item inside a custom grid.")
        }
        let plan = try GridLayout.plan(container, id: parent)
        guard [cell.row, cell.column, cell.rowSpan, cell.columnSpan].allSatisfy({ (1...32).contains($0) }),
              cell.rowSpan <= 33 - cell.row, cell.column <= plan.columns, cell.columnSpan <= plan.columns - cell.column + 1 else {
            throw DiagramError.message("The cell and its span must fit the grid's columns and up to 32 rows.")
        }
        var next = document, cells = plan.cells
        func overlaps(_ a: GridCell, _ b: GridCell) -> Bool {
            a.row < b.row + b.rowSpan && b.row < a.row + a.rowSpan && a.column < b.column + b.columnSpan && b.column < a.column + a.columnSpan
        }
        let conflicts = plan.cells.keys.filter { $0 != id && overlaps(plan.cells[$0]!, cell) }
        if conflicts.count == 1, cell.rowSpan == 1, cell.columnSpan == 1,
           let other = conflicts.first, plan.cells[other]?.rowSpan == 1, plan.cells[other]?.columnSpan == 1,
           plan.cells[id]?.rowSpan == 1, plan.cells[id]?.columnSpan == 1 {
            cells[other] = plan.cells[id]
        } else { for child in conflicts { cells.removeValue(forKey: child) } }
        cells[id] = cell
        next.containers[parent]?.layout.cells = cells
        next.containers[parent]?.layout.rows = max(plan.rows, cell.row + cell.rowSpan - 1)
        try ensureGridRoom(container: parent, document: &next)
        let issues = Validator.validate(next)
        guard issues.isEmpty else { throw DiagramError.invalid(issues) }
        rerouteConnections(in: parent, document: &next)
        document = next
    }

    /// Moves a top-level boundary below its siblings, preserving the existing main layout.
    public static func placeContainerBelow(_ id: String, document: inout Diagram) throws {
        guard id != document.root, document.containers[id] != nil, document.parent(of: id) == document.root else {
            throw DiagramError.message("Choose a top-level container to place below the diagram.")
        }
        var next = document
        if next.containers[next.root]?.layout.mode == .grid {
            let plan = try GridLayout.plan(next.containers[next.root]!, id: next.root)
            let bottom = plan.cells.filter { $0.key != id }.values.map { $0.row + $0.rowSpan - 1 }.max() ?? 0
            try setGridCell(GridCell(row: bottom + 1, column: 1, columnSpan: plan.columns), element: id, document: &next)
            document = next; return
        }
        try setLayout(.free, container: next.root, document: &next)
        let layout = try LayoutEngine.layout(next), root = next.containers[next.root]!
        let origin = CGPoint(x: root.layout.padding, y: root.layout.padding)
        // Normalize root positions to the current frames, including files with negative positions.
        // This prevents moving the leftmost item from shifting all its siblings.
        for child in root.children {
            let frame = layout.frames[child]!
            let point = Point(x: frame.minX - origin.x, y: frame.minY - origin.y)
            if next.nodes[child] != nil { next.nodes[child]?.position = point }
            else { next.containers[child]?.position = point }
        }
        let siblings = root.children.filter { $0 != id }.reduce(CGRect.null) { $0.union(layout.frames[$1]!) }
        let position = siblings.isNull ? Point() : Point(x: siblings.minX - origin.x, y: siblings.maxY + max(48, root.layout.gap) - origin.y)
        let width = max(next.containers[id]?.width ?? 0, siblings.isNull ? 640 : siblings.width)
        next.containers[id]?.position = position
        next.containers[id]?.width = width
        let issues = Validator.validate(next)
        guard issues.isEmpty else { throw DiagramError.invalid(issues) }
        document = next
    }

    public static func setFontSize(_ size: Double?, element id: String, document: inout Diagram) throws {
        guard id != document.root, document.nodes[id] != nil || document.containers[id] != nil || document.connectors[id] != nil else {
            throw DiagramError.message("Select an existing object or connector.")
        }
        if let size, !size.isFinite || !(10...36).contains(size) {
            throw DiagramError.message("Text size must be between 10 and 36.")
        }
        if document.nodes[id] != nil { document.nodes[id]?.fontSize = size }
        else if document.containers[id] != nil { document.containers[id]?.fontSize = size }
        else { document.connectors[id]?.fontSize = size }
    }

    public static func setStrokeWidth(_ width: Double?, element id: String, document: inout Diagram) throws {
        guard id != document.root, document.nodes[id] != nil || document.containers[id] != nil || document.connectors[id] != nil else {
            throw DiagramError.message("Select an existing object or connector.")
        }
        if let width, !width.isFinite || !(0.5...8).contains(width) {
            throw DiagramError.message("Line width must be between 0.5 and 8.")
        }
        if document.nodes[id] != nil { document.nodes[id]?.strokeWidth = width }
        else if document.containers[id] != nil { document.containers[id]?.strokeWidth = width }
        else { document.connectors[id]?.strokeWidth = width }
    }

    public static func reparent(_ id: String, into parent: String, position: Point?, index: Int? = nil, document: inout Diagram) throws {
        guard id != document.root, document.nodes[id] != nil || document.containers[id] != nil,
              let target = document.containers[parent] else { throw DiagramError.message("Choose an existing element and target container.") }
        guard !document.descendants(of: id).contains(parent) else { throw DiagramError.message("A container cannot be moved inside itself or its descendants.") }
        let type = document.nodes[id]?.type ?? "container"
        if let allowed = target.allowedChildTypes, !allowed.contains(type) { throw DiagramError.message("This container accepts \(allowed.joined(separator: ", ")); '\(type)' is not allowed.") }
        let old = document
        let owner = document.parent(of: id), previousCell = owner == parent ? target.layout.cells?[id] : nil
        if let owner {
            document.containers[owner]?.children.removeAll { $0 == id }
            document.containers[owner]?.layout.cells?.removeValue(forKey: id)
        }
        let count = document.containers[parent]!.children.count
        document.containers[parent]?.children.insert(id, at: min(count, max(0, index ?? count)))
        if document.nodes[id] != nil { document.nodes[id]?.position = target.layout.mode == .free ? position : nil }
        else { document.containers[id]?.position = target.layout.mode == .free ? position : nil }
        if let previousCell { document.containers[parent]?.layout.cells?[id] = previousCell }
        do { try ensureGridRoom(container: parent, document: &document) }
        catch { document = old; throw error }
        let issues = Validator.validate(document)
        if !issues.isEmpty { document = old; throw DiagramError.invalid(issues) }
    }

    public static func setLayout(_ mode: LayoutMode, container id: String, document: inout Diagram) throws {
        guard let container = document.containers[id], mode != container.layout.mode else { return }
        var next = document
        if mode == .free {
            let layout = try LayoutEngine.layout(document), rect = layout.frames[id]!
            let origin = CGPoint(x: rect.minX + container.layout.padding, y: rect.minY + container.layout.padding + (id == document.root ? 0 : 36))
            for child in container.children {
                let frame = layout.frames[child]!, point = Point(x: frame.minX - origin.x, y: frame.minY - origin.y)
                if next.nodes[child] != nil { next.nodes[child]?.position = point }
                else {
                    next.containers[child]?.position = point
                    if container.layout.mode == .grid {
                        next.containers[child]?.width = frame.width; next.containers[child]?.height = frame.height
                    }
                }
            }
        }
        next.containers[id]?.layout.mode = mode
        if mode == .grid { try ensureGridRoom(container: id, document: &next) }
        if mode != .free { rerouteConnections(in: id, document: &next) }
        let issues = Validator.validate(next)
        guard issues.isEmpty else { throw DiagramError.invalid(issues) }
        document = next
    }

    private static func rerouteConnections(in id: String, document: inout Diagram) {
        let affected = document.descendants(of: id)
        for key in document.connectors.keys.sorted() {
            guard var edge = document.connectors[key], affected.contains(edge.from.element) || affected.contains(edge.to.element) else { continue }
            if affected.contains(edge.from.element) { edge.from.side = .auto }
            if affected.contains(edge.to.element) { edge.to.side = .auto }
            edge.waypoints = nil
            document.connectors[key] = edge
        }
    }
}
