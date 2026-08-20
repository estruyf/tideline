// Draws the app icon into an .iconset folder. Run via: swift Tools/make-icon.swift <output.iconset>
// No assets, no dependencies — the artwork is drawn with Bezier paths.

import AppKit
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func squircle(in rect: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
}

func draw(size: CGFloat) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = size * 0.055
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    // Body
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.38, green: 0.60, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.13, green: 0.33, blue: 0.87, alpha: 1),
    ])
    gradient?.draw(in: squircle(in: plate), angle: -90)

    // Top highlight
    let highlight = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.28),
        NSColor(white: 1, alpha: 0.0),
    ])
    let clip = squircle(in: plate)
    NSGraphicsContext.current?.saveGraphicsState()
    clip.addClip()
    highlight?.draw(in: NSRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    let u = size            // work in fractions of the full canvas
    let centerX = size / 2
    NSColor.white.setFill()

    // Downward arrow
    let shaft = NSRect(x: centerX - u * 0.055, y: u * 0.475, width: u * 0.11, height: u * 0.235)
    NSBezierPath(roundedRect: shaft, xRadius: u * 0.055, yRadius: u * 0.055).fill()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: centerX - u * 0.155, y: u * 0.505))
    head.line(to: NSPoint(x: centerX + u * 0.155, y: u * 0.505))
    head.line(to: NSPoint(x: centerX, y: u * 0.335))
    head.close()
    head.fill()

    // Tray it drops into
    let tray = NSBezierPath()
    let left = u * 0.235, right = u * 0.765
    let top = u * 0.335, bottom = u * 0.235
    let thickness = u * 0.075
    tray.move(to: NSPoint(x: left, y: top))
    tray.line(to: NSPoint(x: left, y: bottom))
    tray.line(to: NSPoint(x: right, y: bottom))
    tray.line(to: NSPoint(x: right, y: top))
    tray.lineWidth = thickness
    tray.lineCapStyle = .round
    tray.lineJoinStyle = .round
    NSColor.white.setStroke()
    tray.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, size) in variants {
    guard let data = draw(size: size) else {
        FileHandle.standardError.write("could not render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: outputURL.appendingPathComponent(name))
}

print("wrote \(variants.count) images to \(outputURL.path)")
