import CoreGraphics

/// Frozen geometry from T1A's official logo: https://t1a.com/images/t1a-LOGO.svg
enum T1AWatermark {
    static let aspectRatio: CGFloat = 911 / 350
    private static let logo = try! SVGPath.parse("M112 66H9.49949e-08V-2.38419e-05H305V66H193V350H112V66ZM481.602 -2.38419e-05V350H400.602V65H330.602V-2.38419e-05H481.602ZM794.902 275H632.402L601.402 350H518.402L674.402 -2.38419e-05H754.402L910.902 350H825.902L794.902 275ZM769.402 213.5L713.902 79.5L658.402 213.5H769.402Z")

    static func path(in rect: CGRect) -> CGPath {
        var transform = CGAffineTransform(a: rect.width / 911, b: 0, c: 0, d: rect.height / 350, tx: rect.minX, ty: rect.minY)
        return logo.copy(using: &transform)!
    }
}
