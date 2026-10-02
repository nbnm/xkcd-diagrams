import Foundation
import CoreGraphics

/// Shared drafting paper: fine 20-point squares, with a slightly stronger 100-point grid.
enum BlueprintGrid {
    static func draw(in context: CGContext, bounds: CGRect) {
        context.saveGState()
        context.setLineDash(phase: 0, lengths: [])
        context.setLineCap(.butt)
        let minor = CGMutablePath(), major = CGMutablePath()
        for x in stride(from: floor(bounds.minX / 20) * 20, through: bounds.maxX, by: 20) {
            let path = Int((x / 20).rounded()) % 5 == 0 ? major : minor
            path.move(to: CGPoint(x: x, y: bounds.minY)); path.addLine(to: CGPoint(x: x, y: bounds.maxY))
        }
        for y in stride(from: floor(bounds.minY / 20) * 20, through: bounds.maxY, by: 20) {
            let path = Int((y / 20).rounded()) % 5 == 0 ? major : minor
            path.move(to: CGPoint(x: bounds.minX, y: y)); path.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); context.setLineWidth(0.35)
        context.addPath(minor); context.strokePath()
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.18)); context.setLineWidth(0.55)
        context.addPath(major); context.strokePath()
        context.restoreGState()
    }
    static func svgDefinitions(background: String) -> String {
        """
        <defs>
        <pattern id="blueprint-grid" patternUnits="userSpaceOnUse" width="100" height="100">
        <path d="M20 0V100 M40 0V100 M60 0V100 M80 0V100 M0 20H100 M0 40H100 M0 60H100 M0 80H100" fill="none" stroke="#ffffff" stroke-opacity="0.10" stroke-width="0.35"/>
        <path d="M0 0H100V100H0Z" fill="none" stroke="#ffffff" stroke-opacity="0.18" stroke-width="0.55"/>
        </pattern>
        <pattern id="blueprint-paper" patternUnits="userSpaceOnUse" width="100" height="100">
        <rect width="100" height="100" fill="\(background)"/>
        <rect width="100" height="100" fill="url(#blueprint-grid)"/>
        </pattern>
        </defs>
        """
    }
}
