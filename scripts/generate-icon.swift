#!/usr/bin/env swift
// Generates AppIcon.icns — the same 4-pointed sparkle star used in the menu bar.
// Usage: swift scripts/generate-icon.swift <output-dir>
//   Writes <output-dir>/AppIcon.icns

import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate-icon.swift <output-dir>\n", stderr)
    exit(1)
}

let outputDir = CommandLine.arguments[1]

// Sizes required for a modern macOS .icns
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x",1024),
]

// Draw the sparkle star into an image of the given pixel size
func renderIcon(px: Int) -> NSImage {
    let size = CGFloat(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Background: rounded-rect with subtle gradient
    let cornerRadius = size * 0.2
    let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Dark gradient background
    let bgTop = NSColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0)
    let bgBottom = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
    let gradient = NSGradient(starting: bgBottom, ending: bgTop)!
    gradient.draw(in: bgPath, angle: 90)

    // Subtle border
    NSColor(white: 1.0, alpha: 0.08).setStroke()
    bgPath.lineWidth = size * 0.01
    bgPath.stroke()

    // 4-pointed sparkle star — same geometry as MenuBarIcon.swift
    let center = NSPoint(x: size / 2, y: size / 2)
    let outerRadius = size * 0.38
    let innerRadius = size * 0.12

    let starPath = NSBezierPath()
    for i in 0..<8 {
        let angle = (CGFloat(i) * .pi / 4) - (.pi / 2)
        let radius = i % 2 == 0 ? outerRadius : innerRadius
        let point = NSPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
        if i == 0 {
            starPath.move(to: point)
        } else {
            starPath.line(to: point)
        }
    }
    starPath.close()

    // Green fill matching the app's "healthy" color
    let starColor = NSColor(red: 0.30, green: 0.85, blue: 0.45, alpha: 1.0)
    starColor.setFill()
    starPath.fill()

    // Soft glow behind the star
    ctx.saveGState()
    let glowColor = starColor.withAlphaComponent(0.3).cgColor
    ctx.setShadow(offset: .zero, blur: size * 0.08, color: glowColor)
    starColor.setFill()
    starPath.fill()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

// Create temporary .iconset directory
let iconsetPath = (outputDir as NSString).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for entry in sizes {
    let image = renderIcon(px: entry.px)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(entry.name)\n", stderr)
        exit(1)
    }
    let filePath = (iconsetPath as NSString).appendingPathComponent("\(entry.name).png")
    try png.write(to: URL(fileURLWithPath: filePath))
}

// Convert .iconset → .icns
let icnsPath = (outputDir as NSString).appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", icnsPath, iconsetPath]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    fputs("iconutil failed with exit code \(process.terminationStatus)\n", stderr)
    exit(1)
}

// Clean up .iconset
try FileManager.default.removeItem(atPath: iconsetPath)

print("Generated: \(icnsPath)")
