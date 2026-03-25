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

    /// Shattered 4-point star fragments for exhausted/throttled state.
    /// Each arm is detached and pushed slightly outward so the center reads as "broken"
    /// even at menu bar size.
    static func brokenStarFragments(center: NSPoint, outerRadius: CGFloat, innerRadius: CGFloat, offset: CGFloat) -> [NSBezierPath] {
        let top = NSPoint(x: center.x, y: center.y + outerRadius)
        let topRight = NSPoint(x: center.x + innerRadius, y: center.y + innerRadius)
        let right = NSPoint(x: center.x + outerRadius, y: center.y)
        let bottomRight = NSPoint(x: center.x + innerRadius, y: center.y - innerRadius)
        let bottom = NSPoint(x: center.x, y: center.y - outerRadius)
        let bottomLeft = NSPoint(x: center.x - innerRadius, y: center.y - innerRadius)
        let left = NSPoint(x: center.x - outerRadius, y: center.y)
        let topLeft = NSPoint(x: center.x - innerRadius, y: center.y + innerRadius)

        func translated(_ point: NSPoint, dx: CGFloat, dy: CGFloat) -> NSPoint {
            NSPoint(x: point.x + dx, y: point.y + dy)
        }

        func fragment(_ points: [NSPoint], dx: CGFloat, dy: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            for (index, point) in points.enumerated() {
                let shifted = translated(point, dx: dx, dy: dy)
                if index == 0 {
                    path.move(to: shifted)
                } else {
                    path.line(to: shifted)
                }
            }
            path.close()
            return path
        }

        return [
            fragment([topLeft, top, topRight], dx: 0, dy: offset),
            fragment([topRight, right, bottomRight], dx: offset, dy: 0),
            fragment([bottomRight, bottom, bottomLeft], dx: 0, dy: -offset),
            fragment([bottomLeft, left, topLeft], dx: -offset, dy: 0),
        ]
    }

    /// Shared stroke drawing via CGContext.
    static func drawStroke(ctx: CGContext, path: CGPath, color: NSColor, highContrast: Bool, isDarkMode: Bool) {
        if highContrast {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1.0)
        } else if !isDarkMode {
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(0.75)
        } else {
            ctx.setStrokeColor(color.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(0.5)
        }
        ctx.addPath(path)
        ctx.strokePath()
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
