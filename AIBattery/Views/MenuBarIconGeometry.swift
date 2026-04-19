import AppKit

// MARK: - Star geometry helpers (extracted from MenuBarIcon)

extension MenuBarIcon {

    /// N-pointed star path for glow effects: alternating outer/inner vertices.
    static func multiPointStarPath(center: NSPoint, outerRadius: CGFloat, innerRadius: CGFloat, points: Int) -> NSBezierPath {
        let path = NSBezierPath()
        let totalVertices = points * 2
        for i in 0..<totalVertices {
            let angle = (CGFloat(i) * .pi / CGFloat(points)) - (.pi / 2)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let point = NSPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()
        return path
    }

    /// 4-pointed star path: 8 vertices alternating outer/inner radius.
    static func starPath(center: NSPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for i in 0..<8 {
            let angle = (CGFloat(i) * .pi / 4) - (.pi / 2)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let point = NSPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }
        path.close()
        return path
    }
}

// MARK: - NSBezierPath → CGPath

extension NSBezierPath {
    /// Converts an NSBezierPath to a CGPath for use with CGContext drawing.
    /// macOS 14+ has a native `.cgPath` — this provides the same for macOS 13.
    var asCGPath: CGPath {
        if #available(macOS 14.0, *) {
            return cgPath
        }
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            case .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            @unknown default: break
            }
        }
        return path
    }
}
