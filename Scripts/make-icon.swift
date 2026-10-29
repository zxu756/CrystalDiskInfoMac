#!/usr/bin/env swift

import AppKit
import Foundation

let scriptURL = URL(fileURLWithPath: #filePath)
let root = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let pngURL = resources.appendingPathComponent("AppIcon-1024.png")
let icnsURL = resources.appendingPathComponent("AppIcon.icns")

let fileManager = FileManager.default
try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

func makeCanvas(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    return rep
}

let size = 1024
let rep = makeCanvas(pixels: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let backgroundRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 184, yRadius: 184)
let backgroundGradient = NSGradient(
    starting: NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.19, alpha: 1),
    ending: NSColor(calibratedRed: 0.035, green: 0.04, blue: 0.055, alpha: 1)
)!
backgroundGradient.draw(in: backgroundPath, angle: -90)

NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
backgroundPath.lineWidth = 5
backgroundPath.stroke()

let highlightRect = NSRect(x: 148, y: 770, width: 728, height: 100)
let highlightPath = NSBezierPath(roundedRect: highlightRect, xRadius: 50, yRadius: 50)
NSColor(calibratedWhite: 1, alpha: 0.045).setFill()
highlightPath.fill()

let healthColors: [NSColor] = [
    NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
]

let barWidth: CGFloat = 620
let barHeight: CGFloat = 150
let gap: CGFloat = 42
let stackHeight = 3 * barHeight + 2 * gap
var barY = (CGFloat(size) - stackHeight) / 2

for color in healthColors {
    let barRect = NSRect(x: 202, y: barY, width: barWidth, height: barHeight)
    let barPath = NSBezierPath(roundedRect: barRect, xRadius: 38, yRadius: 38)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.set()
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    barPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let bodyGradient = NSGradient(
        starting: NSColor(calibratedWhite: 0.23, alpha: 1),
        ending: NSColor(calibratedWhite: 0.12, alpha: 1)
    )!
    bodyGradient.draw(in: barPath, angle: -90)

    NSColor(calibratedWhite: 1, alpha: 0.09).setStroke()
    barPath.lineWidth = 3
    barPath.stroke()

    let platterRect = NSRect(
        x: barRect.minX + 34,
        y: barRect.minY + 32,
        width: 86,
        height: 86
    )
    let platter = NSBezierPath(ovalIn: platterRect)
    let platterGradient = NSGradient(
        starting: color.blended(withFraction: 0.18, of: .white) ?? color,
        ending: color.blended(withFraction: 0.35, of: .black) ?? color
    )!
    platterGradient.draw(in: platter, angle: -90)

    NSColor(calibratedWhite: 0, alpha: 0.35).setStroke()
    platter.lineWidth = 4
    platter.stroke()

    let centerRect = NSRect(
        x: platterRect.midX - 12,
        y: platterRect.midY - 12,
        width: 24,
        height: 24
    )
    let center = NSBezierPath(ovalIn: centerRect)
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    center.fill()

    let slot = NSBezierPath(
        roundedRect: NSRect(
            x: barRect.minX + 150,
            y: barRect.midY - 8,
            width: 330,
            height: 16
        ),
        xRadius: 8,
        yRadius: 8
    )
    NSColor(calibratedWhite: 0, alpha: 0.30).setFill()
    slot.fill()

    let ledRect = NSRect(
        x: barRect.maxX - 74,
        y: barRect.midY - 18,
        width: 36,
        height: 36
    )
    let led = NSBezierPath(ovalIn: ledRect)

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color.withAlphaComponent(0.85)
    glow.shadowBlurRadius = 24
    glow.shadowOffset = .zero
    glow.set()
    color.setFill()
    led.fill()
    NSGraphicsContext.restoreGraphicsState()

    let ledGradient = NSGradient(
        starting: color.blended(withFraction: 0.30, of: .white) ?? color,
        ending: color
    )!
    ledGradient.draw(in: led, angle: -90)

    barY += barHeight + gap
}

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not render the icon PNG")
}
try pngData.write(to: pngURL)

try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

guard let source = NSImage(data: pngData) else {
    fatalError("Could not load the rendered icon")
}

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in variants {
    let resizedRep = makeCanvas(pixels: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resizedRep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    source.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let resizedData = resizedRep.representation(using: .png, properties: [:]) else {
        fatalError("Could not render \(name)")
    }
    try resizedData.write(to: iconset.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(iconutil.terminationStatus)")
}

print("Wrote \(pngURL.path)")
print("Wrote \(icnsURL.path)")
