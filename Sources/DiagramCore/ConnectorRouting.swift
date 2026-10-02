import Foundation
import CoreGraphics

/// Attachments carry an edge normal, so distance-based bends cannot turn a port sideways.
enum ConnectorRouter {
    struct Attachment {
        var point: CGPoint
        var normal: CGPoint
    }
    static func route(_ edge: Connector, frames: [String: CGRect], document: Diagram) -> [CGPoint]? {
        guard let from = frames[edge.from.element], let to = frames[edge.to.element] else { return nil }
        let insideSource = document.containers[edge.from.element] != nil && document.descendants(of: edge.from.element).contains(edge.to.element)
        let insideTarget = document.containers[edge.to.element] != nil && document.descendants(of: edge.to.element).contains(edge.from.element)
        let a = attachment(edge.from.side, frame: from, toward: to, shape: document.nodes[edge.from.element]?.shape, inward: insideSource)
        let b = attachment(edge.to.side, frame: to, toward: from, shape: document.nodes[edge.to.element]?.shape, inward: insideTarget)
        var obstacles = document.nodes.keys.sorted().compactMap { frames[$0]?.insetBy(dx: -8, dy: -8) }
        if document.containers[edge.from.element] != nil && !insideSource { obstacles.append(from.insetBy(dx: -8, dy: -8)) }
        if document.containers[edge.to.element] != nil && !insideTarget { obstacles.append(to.insetBy(dx: -8, dy: -8)) }
        return route(from: a, to: b, waypoints: edge.waypoints, obstacles: obstacles, envelope: from.union(to))
    }
    static func attachment(_ requested: Side, frame: CGRect, toward other: CGRect, shape: Shape?, inward: Bool) -> Attachment {
        var side = requested
        if side == .auto {
            let dx = other.midX - frame.midX, dy = other.midY - frame.midY
            side = abs(dx) >= abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .bottom : .top)
        }
        // The database's curved top and bottom extend slightly beyond its layout rectangle.
        let outline = shape == .cylinder ? SymbolGeometry.paths(.cylinder, in: frame)[0].boundingBoxOfPath : frame
        let point: CGPoint, normal: CGPoint
        switch side {
        case .left: point = CGPoint(x: frame.minX, y: frame.midY); normal = CGPoint(x: -1, y: 0)
        case .right: point = CGPoint(x: frame.maxX, y: frame.midY); normal = CGPoint(x: 1, y: 0)
        case .top: point = CGPoint(x: frame.midX, y: outline.minY); normal = CGPoint(x: 0, y: -1)
        case .bottom: point = CGPoint(x: frame.midX, y: outline.maxY); normal = CGPoint(x: 0, y: 1)
        case .auto: preconditionFailure("Automatic side must be resolved")
        }
        return Attachment(point: point, normal: inward ? CGPoint(x: -normal.x, y: -normal.y) : normal)
    }

    static func route(from a: Attachment, to b: Attachment, waypoints: [Point]?, obstacles: [CGRect], envelope: CGRect) -> [CGPoint] {
        let manual = (waypoints ?? []).map { CGPoint(x: $0.x, y: $0.y) }
        var clearance: CGFloat = 24
        let gap = (b.point.x - a.point.x) * a.normal.x + (b.point.y - a.point.y) * a.normal.y
        if manual.isEmpty && a.normal.x == -b.normal.x && a.normal.y == -b.normal.y && gap > 0 {
            clearance = min(clearance, gap / 2)
        }
        func departureDistance(_ port: Attachment) -> CGFloat {
            var distance = clearance
            for r in obstacles {
                let p = port.point, n = port.normal
                var gap: CGFloat?
                if n.x != 0 && p.y > r.minY && p.y < r.maxY {
                    if n.x > 0 && r.minX > p.x { gap = r.minX - p.x }
                    if n.x < 0 && r.maxX < p.x { gap = p.x - r.maxX }
                } else if n.y != 0 && p.x > r.minX && p.x < r.maxX {
                    if n.y > 0 && r.minY > p.y { gap = r.minY - p.y }
                    if n.y < 0 && r.maxY < p.y { gap = p.y - r.maxY }
                }
                if let gap { distance = min(distance, max(1, gap - 2)) }
            }
            return distance
        }
        let sourceDistance = departureDistance(a), destinationDistance = departureDistance(b)
        let start = CGPoint(x: a.point.x + a.normal.x * sourceDistance, y: a.point.y + a.normal.y * sourceDistance)
        let end = CGPoint(x: b.point.x + b.normal.x * destinationDistance, y: b.point.y + b.normal.y * destinationDistance)
        var points = [a.point, start]
        for (index, stop) in (manual + [end]).enumerated() {
            let previous = points.count > 1 ? CGPoint(x: points.last!.x - points[points.count - 2].x, y: points.last!.y - points[points.count - 2].y) : a.normal
            let outgoing = index == manual.count ? CGPoint(x: -b.normal.x, y: -b.normal.y) : nil
            let leg = bestLeg(from: points.last!, to: stop, incoming: previous, outgoing: outgoing, obstacles: obstacles, envelope: envelope)
            points += leg.dropFirst()
        }
        points.append(b.point)
        return simplify(points, preserving: manual)
    }

    private static func bestLeg(from a: CGPoint, to b: CGPoint, incoming: CGPoint, outgoing: CGPoint?, obstacles: [CGRect], envelope: CGRect) -> [CGPoint] {
        if a == b { return [a] }
        var candidates: [[CGPoint]] = []
        if a.x == b.x || a.y == b.y { candidates.append([a, b]) }
        candidates += [[a, CGPoint(x: b.x, y: a.y), b], [a, CGPoint(x: a.x, y: b.y), b]]
        for x in [(a.x + b.x) / 2, envelope.minX - 24, envelope.maxX + 24, a.x - 24, a.x + 24, b.x - 24, b.x + 24] {
            candidates.append([a, CGPoint(x: x, y: a.y), CGPoint(x: x, y: b.y), b])
        }
        for y in [(a.y + b.y) / 2, envelope.minY - 24, envelope.maxY + 24, a.y - 24, a.y + 24, b.y - 24, b.y + 24] {
            candidates.append([a, CGPoint(x: a.x, y: y), CGPoint(x: b.x, y: y), b])
        }
        func reverses(_ a: CGPoint, _ b: CGPoint) -> Bool { a.x * b.y == a.y * b.x && a.x * b.x + a.y * b.y < 0 }
        func score(_ points: [CGPoint]) -> CGFloat {
            var cost = CGFloat(points.count - 2) * 8
            var previous = incoming
            for (a, b) in zip(points, points.dropFirst()) {
                let delta = CGPoint(x: b.x - a.x, y: b.y - a.y)
                cost += abs(delta.x) + abs(delta.y)
                if reverses(previous, delta) { cost += 100_000 }
                previous = delta
                for r in obstacles {
                    let crosses = a.y == b.y
                        ? a.y > r.minY && a.y < r.maxY && min(a.x, b.x) < r.maxX && max(a.x, b.x) > r.minX
                        : a.x > r.minX && a.x < r.maxX && min(a.y, b.y) < r.maxY && max(a.y, b.y) > r.minY
                    if crosses { cost += 10_000 }
                }
            }
            if let outgoing, reverses(previous, outgoing) { cost += 100_000 }
            return cost
        }
        var best = [CGPoint](), bestScore = CGFloat.infinity
        for candidate in candidates {
            let candidate = simplify(candidate), value = score(candidate)
            if value < bestScore { best = candidate; bestScore = value }
        }
        return best
    }

    private static func simplify(_ points: [CGPoint], preserving pinned: [CGPoint] = []) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if result.last == point { continue }
            while result.count >= 2 {
                let a = result[result.count - 2], b = result.last!
                let dx = b.x - a.x, dy = b.y - a.y, ex = point.x - b.x, ey = point.y - b.y
                guard !pinned.contains(b), dx * ey == dy * ex, dx * ex + dy * ey > 0 else { break }
                result.removeLast()
            }
            result.append(point)
        }
        return result
    }
}
