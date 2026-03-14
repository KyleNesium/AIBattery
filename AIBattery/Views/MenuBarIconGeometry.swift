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

    /// 4 triangular fragments of the star, each offset outward from center.
    static func brokenStarFragments(
        center: NSPoint,
        outerRadius: CGFloat,
        innerRadius: CGFloat,
        offset: CGFloat
    ) -> [NSBezierPath] {
        var vertices: [NSPoint] = []
        for i in 0..<8 {
            let angle = (CGFloat(i) * .pi / 4) - (.pi / 2)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            vertices.append(NSPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            ))
        }

        var fragments: [NSBezierPath] = []
        for k in 0..<4 {
            let outerIdx = k * 2
            let prevInner = (outerIdx + 7) % 8
            let nextInner = (outerIdx + 1) % 8

            let outerAngle = (CGFloat(outerIdx) * .pi / 4) - (.pi / 2)
            let dx = offset * cos(outerAngle)
            let dy = offset * sin(outerAngle)

            let path = NSBezierPath()
            path.move(to: NSPoint(x: vertices[outerIdx].x + dx, y: vertices[outerIdx].y + dy))
            path.line(to: NSPoint(x: vertices[prevInner].x + dx, y: vertices[prevInner].y + dy))
            path.line(to: NSPoint(x: vertices[nextInner].x + dx, y: vertices[nextInner].y + dy))
            path.close()
            fragments.append(path)
        }

        return fragments
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
