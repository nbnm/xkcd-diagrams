import Foundation
import CoreGraphics

/// Compact margins retain the comic figure while bringing its connection edges closer.
enum UserContent {
    static let horizontalInset: CGFloat = 6
    static let topInset: CGFloat = 74
    static let bottomInset: CGFloat = 4
    static var verticalPadding: CGFloat { topInset + bottomInset }
    static func labelRect(in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + horizontalInset, y: frame.minY + topInset,
               width: frame.width - horizontalInset * 2, height: frame.height - verticalPadding)
    }
}

/// Folded sheets keep space for their format details and optional logo above the label.
enum DocumentContent {
    static let horizontalInset: CGFloat = 22
    static let bottomInset: CGFloat = 12
    static let logoSpace: CGFloat = 43
    static let minimumLogoWidth: CGFloat = 144

    static func topInset(_ shape: Shape) -> CGFloat { shape == .file ? 24 : 108 }
    static func verticalPadding(_ shape: Shape, hasLogo: Bool) -> CGFloat {
        topInset(shape) + bottomInset + (hasLogo ? logoSpace : 0)
    }
    static func labelRect(_ shape: Shape, in frame: CGRect, hasLogo: Bool) -> CGRect {
        CGRect(x: frame.minX + horizontalInset,
               y: frame.minY + topInset(shape) + (hasLogo ? logoSpace : 0),
               width: frame.width - horizontalInset * 2,
               height: frame.height - verticalPadding(shape, hasLogo: hasLogo))
    }
}

/// Shared content space keeps database labels and logos below the curved lid.
enum DatabaseContent {
    static let topInset: CGFloat = 40
    static let bottomInset: CGFloat = 20
    static let horizontalInset: CGFloat = 20
    static let logoHeight: CGFloat = 34
    static let logoGap: CGFloat = 12
    static let minimumLogoWidth: CGFloat = 150

    static func verticalPadding(hasLogo: Bool) -> CGFloat {
        topInset + bottomInset + (hasLogo ? logoHeight + logoGap : 0)
    }
    static func labelRect(in frame: CGRect, hasLogo: Bool) -> CGRect {
        let logoSpace = hasLogo ? logoHeight + logoGap : 0
        return CGRect(x: frame.minX + horizontalInset, y: frame.minY + topInset + logoSpace,
                      width: frame.width - horizontalInset * 2, height: frame.height - verticalPadding(hasLogo: hasLogo))
    }
    static func logoRect(in frame: CGRect) -> CGRect {
        CGRect(x: frame.midX - 50, y: frame.minY + topInset, width: 100, height: logoHeight)
    }
}

/// The library previews and diagram renderer use the same shape geometry.
public enum SymbolGeometry {
    public static func isFilledDetail(_ shape: Shape, index: Int) -> Bool {
        shape.isDocument && shape != .file && index == 2
    }
    public static func paths(_ shape: Shape, in r: CGRect) -> [CGPath] {
        switch shape {
        case .rectangle: return [CGPath(rect: r, transform: nil)]
        case .roundedRectangle: return [CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)]
        case .file, .xlsx, .pdf, .docx:
            let body = CGMutablePath(), fold = CGMutablePath(), size = min(24, r.width / 4, r.height / 3)
            body.move(to: CGPoint(x: r.minX, y: r.minY))
            body.addLine(to: CGPoint(x: r.maxX - size, y: r.minY))
            body.addLine(to: CGPoint(x: r.maxX, y: r.minY + size))
            body.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            body.addLine(to: CGPoint(x: r.minX, y: r.maxY)); body.closeSubpath()
            fold.move(to: CGPoint(x: r.maxX - size, y: r.minY))
            fold.addLine(to: CGPoint(x: r.maxX - size, y: r.minY + size))
            fold.addLine(to: CGPoint(x: r.maxX, y: r.minY + size))
            guard shape != .file else { return [body, fold] }
            let mark = shape == .xlsx ? "X" : shape == .docx ? "W" : "PDF"
            let font = Typography.font(Theme(preset: .standard, fontFamily: "Helvetica-Bold"), size: min(26, max(6, (r.width - 32) / 2.4)))
            let badge = Typography.paths(mark, in: CGRect(x: r.minX + 16, y: r.minY + 32, width: r.width - 32, height: 32), font: font)
            var details: [CGPath] = [body, fold, badge]
            let w = min(64, max(20, r.width - 36)), x = r.midX - w / 2
            if shape == .xlsx {
                let grid = CGMutablePath(), y = r.minY + 70, h: CGFloat = 28
                grid.addRect(CGRect(x: x, y: y, width: w, height: h))
                for i in 1...2 {
                    grid.move(to: CGPoint(x: x + w * CGFloat(i) / 3, y: y)); grid.addLine(to: CGPoint(x: x + w * CGFloat(i) / 3, y: y + h))
                    grid.move(to: CGPoint(x: x, y: y + h * CGFloat(i) / 3)); grid.addLine(to: CGPoint(x: x + w, y: y + h * CGFloat(i) / 3))
                }
                details.append(grid)
            } else {
                let lines = CGMutablePath()
                for i in 0..<3 {
                    let y = r.minY + 73 + CGFloat(i) * 10
                    lines.move(to: CGPoint(x: x, y: y)); lines.addLine(to: CGPoint(x: x + w * (i == 2 ? 0.7 : 1), y: y))
                }
                details.append(lines)
            }
            return details
        case .queue:
            return [12.0, 6.0, 0.0].map { offset in
                CGPath(rect: CGRect(x: r.minX + offset, y: r.minY + 12 - offset, width: r.width - 12, height: r.height - 12), transform: nil)
            }
        case .cylinder:
            let body = CGMutablePath(), lip = CGMutablePath(), h: CGFloat = 12
            body.move(to: CGPoint(x: r.minX, y: r.minY + h))
            body.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h), control1: CGPoint(x: r.minX, y: r.minY - h / 2), control2: CGPoint(x: r.maxX, y: r.minY - h / 2))
            body.addLine(to: CGPoint(x: r.maxX, y: r.maxY - h))
            body.addCurve(to: CGPoint(x: r.minX, y: r.maxY - h), control1: CGPoint(x: r.maxX, y: r.maxY + h / 2), control2: CGPoint(x: r.minX, y: r.maxY + h / 2))
            body.closeSubpath()
            lip.move(to: CGPoint(x: r.minX, y: r.minY + h))
            lip.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h), control1: CGPoint(x: r.minX, y: r.minY + h * 2.4), control2: CGPoint(x: r.maxX, y: r.minY + h * 2.4))
            return [body, lip]
        case .actor:
            let p = CGMutablePath(), cx = r.midX, y = r.minY - 7.5
            // A blank, slightly irregular head and a relaxed pose give the person a comic character.
            p.move(to: CGPoint(x: cx - 10.8, y: y + 21.5))
            p.addCurve(to: CGPoint(x: cx - 0.8, y: y + 10.5), control1: CGPoint(x: cx - 11.6, y: y + 15.5), control2: CGPoint(x: cx - 7, y: y + 10))
            p.addCurve(to: CGPoint(x: cx + 10.5, y: y + 21.1), control1: CGPoint(x: cx + 6.4, y: y + 9.8), control2: CGPoint(x: cx + 11.3, y: y + 15.4))
            p.addCurve(to: CGPoint(x: cx + 0.2, y: y + 33.6), control1: CGPoint(x: cx + 11.6, y: y + 28.1), control2: CGPoint(x: cx + 6.6, y: y + 33.5))
            p.addCurve(to: CGPoint(x: cx - 10.8, y: y + 21.5), control1: CGPoint(x: cx - 7, y: y + 34.5), control2: CGPoint(x: cx - 11.8, y: y + 29))
            p.closeSubpath()
            p.move(to: CGPoint(x: cx + 0.2, y: y + 33.6))
            p.addCurve(to: CGPoint(x: cx + 1.2, y: y + 55), control1: CGPoint(x: cx - 0.8, y: y + 41), control2: CGPoint(x: cx + 2.8, y: y + 48))
            p.move(to: CGPoint(x: cx + 0.2, y: y + 38))
            p.addQuadCurve(to: CGPoint(x: cx - 12.5, y: y + 54), control: CGPoint(x: cx - 8.5, y: y + 43.5))
            p.move(to: CGPoint(x: cx + 0.2, y: y + 38))
            p.addQuadCurve(to: CGPoint(x: cx + 9, y: y + 45), control: CGPoint(x: cx + 5.5, y: y + 42))
            p.addQuadCurve(to: CGPoint(x: cx + 16, y: y + 39), control: CGPoint(x: cx + 12.5, y: y + 43))
            p.move(to: CGPoint(x: cx + 1.2, y: y + 55))
            p.addQuadCurve(to: CGPoint(x: cx - 11.5, y: y + 76), control: CGPoint(x: cx - 7, y: y + 65))
            p.move(to: CGPoint(x: cx + 1.2, y: y + 55))
            p.addQuadCurve(to: CGPoint(x: cx + 14, y: y + 75.5), control: CGPoint(x: cx + 7, y: y + 67))
            return [p]
        case .text: return []
        }
    }
}

/// Semantic colors let brand themes accent relationships without coloring body text or logos.
public enum PaintRole: Equatable { case neutral, container, surface, accent, outline }

public struct RenderPalette {
    public let preset: ThemePreset
    public let blueprint: Bool
    public let dark: Bool
    public var lightInk: Bool { blueprint || dark }
    public init(_ preset: ThemePreset) {
        self.preset = preset; blueprint = preset == .blueprint
        dark = preset == .dark || preset == .secondStack
    }
    public var background: CGColor {
        if preset == .secondStack { return rgb(backgroundHex) }
        if blueprint { return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [11 / 255, 61 / 255, 145 / 255, 1])! }
        if dark { return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [24 / 255, 24 / 255, 24 / 255, 1])! }
        return CGColor(gray: 1, alpha: 1)
    }
    public var backgroundHex: String { preset == .secondStack ? "#0b0d10" : blueprint ? "#0b3d91" : dark ? "#181818" : "#ffffff" }
    private func brandHex(_ gray: CGFloat, role: PaintRole) -> String? {
        guard preset == .secondStack || preset == .eightFDE else { return nil }
        let secondStack = preset == .secondStack
        switch role {
        case .accent: return secondStack ? "#2fb5f4" : "#5d4be8"
        case .outline: return secondStack ? "#f4f6f8" : "#0c6e85"
        case .container: return backgroundHex
        case .surface: return secondStack ? "#14171b" : "#ffffff"
        case .neutral:
            if gray >= 0.99 { return backgroundHex }
            if gray <= 0.15 { return secondStack ? "#f4f6f8" : "#111827" }
            return secondStack ? "#a7aeb6" : "#5f6878"
        }
    }
    private func rgb(_ hex: String) -> CGColor {
        let value = UInt32(hex.dropFirst(), radix: 16)!
        return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components:
            [CGFloat((value >> 16) & 255) / 255, CGFloat((value >> 8) & 255) / 255, CGFloat(value & 255) / 255, 1])!
    }
    private func ink(_ gray: CGFloat) -> CGFloat { blueprint ? 1 : dark ? 1 - gray : gray }
    public func color(_ gray: CGFloat, role: PaintRole = .neutral) -> CGColor {
        if let hex = brandHex(gray, role: role) { return rgb(hex) }
        if lightInk && gray >= 0.99 { return background }
        if dark { let value = ink(gray); return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [value, value, value, 1])! }
        return CGColor(gray: ink(gray), alpha: 1)
    }
    public func hex(_ gray: CGFloat, role: PaintRole = .neutral) -> String {
        if let hex = brandHex(gray, role: role) { return hex }
        if lightInk && gray >= 0.99 { return backgroundHex }
        let c = Int((ink(gray) * 255).rounded()); return String(format: "#%02x%02x%02x", c, c, c)
    }
}
