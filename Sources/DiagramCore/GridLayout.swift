import Foundation
import CoreGraphics

public struct GridPlan {
    public var rows: Int
    public var columns: Int
    public var cells: [String: GridCell]
}

public struct GridGeometry {
    public var columnWidths: [CGFloat]
    public var rowHeights: [CGFloat]
    public var gap: CGFloat
    public var cells: [String: GridCell]
    public var size: CGSize {
        CGSize(width: columnWidths.reduce(0, +) + gap * CGFloat(max(0, columnWidths.count - 1)),
               height: rowHeights.reduce(0, +) + gap * CGFloat(max(0, rowHeights.count - 1)))
    }
    public func frame(_ cell: GridCell) -> CGRect {
        CGRect(x: columnWidths.prefix(cell.column - 1).reduce(0, +) + gap * CGFloat(cell.column - 1),
               y: rowHeights.prefix(cell.row - 1).reduce(0, +) + gap * CGFloat(cell.row - 1),
               width: columnWidths.dropFirst(cell.column - 1).prefix(cell.columnSpan).reduce(0, +) + gap * CGFloat(cell.columnSpan - 1),
               height: rowHeights.dropFirst(cell.row - 1).prefix(cell.rowSpan).reduce(0, +) + gap * CGFloat(cell.rowSpan - 1))
    }
    public func cell(at point: CGPoint) -> GridCell {
        func nearest(_ coordinate: CGFloat, tracks: [CGFloat]) -> Int {
            var cursor: CGFloat = 0
            for (index, width) in tracks.enumerated() {
                if coordinate < cursor + width + gap / 2 { return index + 1 }
                cursor += width + gap
            }
            return tracks.count
        }
        return GridCell(row: nearest(point.y, tracks: rowHeights), column: nearest(point.x, tracks: columnWidths))
    }
}

public enum GridLayout {
    public static func plan(_ container: Container, id: String) throws -> GridPlan {
        let columns = container.layout.columns ?? 3
        let rows = container.layout.rows ?? max(2, (container.children.count + max(columns, 1) - 1) / max(columns, 1))
        let path = "$.containers.\(id).layout"
        func fail(_ code: String, _ field: String, _ message: String) throws -> Never {
            throw DiagramError.invalid([Diagnostic(code, path + field, message, element: id)])
        }
        guard (1...32).contains(rows), (1...32).contains(columns) else { try fail("numeric-range", "", "Choose 1–32 rows and columns.") }
        var occupied: Set<Int> = [], cells: [String: GridCell] = [:]
        for child in (container.layout.cells ?? [:]).keys.sorted() {
            guard container.children.contains(child) else { try fail("grid-child", ".cells.\(child)", "Grid cells must reference this container's direct children.") }
            let cell = container.layout.cells![child]!
            guard [cell.row, cell.column, cell.rowSpan, cell.columnSpan].allSatisfy({ (1...32).contains($0) }),
                  cell.row <= rows, cell.rowSpan <= rows - cell.row + 1,
                  cell.column <= columns, cell.columnSpan <= columns - cell.column + 1 else {
                try fail("grid-bounds", ".cells.\(child)", "The cell and its span must fit within the configured rows and columns.")
            }
            for row in (cell.row - 1)..<(cell.row - 1 + cell.rowSpan) {
                for column in (cell.column - 1)..<(cell.column - 1 + cell.columnSpan) {
                    guard occupied.insert(row * columns + column).inserted else { try fail("grid-overlap", ".cells.\(child)", "Grid items cannot occupy the same cell.") }
                }
            }
            cells[child] = cell
        }
        for child in container.children where cells[child] == nil {
            guard let slot = (0..<(rows * columns)).first(where: { !occupied.contains($0) }) else {
                try fail("grid-capacity", "", "Add rows or columns to make room for all items and their spans.")
            }
            occupied.insert(slot); cells[child] = GridCell(row: slot / columns + 1, column: slot % columns + 1)
        }
        return GridPlan(rows: rows, columns: columns, cells: cells)
    }

    static func geometry(_ plan: GridPlan, sizes: [String: CGSize], gap: CGFloat) -> GridGeometry {
        var geometry = GridGeometry(columnWidths: Array(repeating: 120, count: plan.columns), rowHeights: Array(repeating: 80, count: plan.rows), gap: gap, cells: plan.cells)
        // Satisfy small spans before large spans so a full-width band uses the columns above it.
        let order = plan.cells.keys.sorted {
            let a = plan.cells[$0]!, b = plan.cells[$1]!
            return a.columnSpan + a.rowSpan == b.columnSpan + b.rowSpan ? $0 < $1 : a.columnSpan + a.rowSpan < b.columnSpan + b.rowSpan
        }
        for id in order {
            let cell = plan.cells[id]!, size = sizes[id]!, rect = geometry.frame(cell)
            let extraWidth = max(0, size.width - rect.width) / CGFloat(cell.columnSpan)
            let extraHeight = max(0, size.height - rect.height) / CGFloat(cell.rowSpan)
            for index in (cell.column - 1)..<(cell.column - 1 + cell.columnSpan) { geometry.columnWidths[index] += extraWidth }
            for index in (cell.row - 1)..<(cell.row - 1 + cell.rowSpan) { geometry.rowHeights[index] += extraHeight }
        }
        return geometry
    }
}
