// Run from the repository root: swift Scripts/GenerateIcon.swift
// Vector artwork rendered with AppKit; no external assets or dependencies.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("MoriPlayer/Resources/Assets.xcassets")
let iconDirectory = assets.appendingPathComponent("AppIcon.appiconset")
let markDirectory = assets.appendingPathComponent("AppMark.imageset")
try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: markDirectory, withIntermediateDirectories: true)

func tree(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: x, y: y + height))
    path.line(to: NSPoint(x: x - width * 0.38, y: y + height * 0.48))
    path.line(to: NSPoint(x: x - width * 0.22, y: y + height * 0.48))
    path.line(to: NSPoint(x: x - width * 0.5, y: y + height * 0.16))
    path.line(to: NSPoint(x: x - width * 0.08, y: y + height * 0.16))
    path.line(to: NSPoint(x: x - width * 0.08, y: y))
    path.line(to: NSPoint(x: x + width * 0.08, y: y))
    path.line(to: NSPoint(x: x + width * 0.08, y: y + height * 0.16))
    path.line(to: NSPoint(x: x + width * 0.5, y: y + height * 0.16))
    path.line(to: NSPoint(x: x + width * 0.22, y: y + height * 0.48))
    path.line(to: NSPoint(x: x + width * 0.38, y: y + height * 0.48))
    path.close()
    path.fill()
}

func png(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSColor(srgbRed: 0.075, green: 0.20, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202).fill()
    NSColor(srgbRed: 0.25, green: 0.46, blue: 0.34, alpha: 1).setFill()
    tree(x: 310, y: 280, width: 230, height: 390)
    tree(x: 710, y: 280, width: 230, height: 390)
    tree(x: 510, y: 280, width: 300, height: 520)
    NSColor(srgbRed: 0.94, green: 0.97, blue: 0.86, alpha: 1).setFill()
    let play = NSBezierPath()
    play.move(to: NSPoint(x: 427, y: 346))
    play.curve(to: NSPoint(x: 449, y: 333), controlPoint1: NSPoint(x: 427, y: 332), controlPoint2: NSPoint(x: 438, y: 327))
    play.line(to: NSPoint(x: 678, y: 497))
    play.curve(to: NSPoint(x: 678, y: 525), controlPoint1: NSPoint(x: 691, y: 505), controlPoint2: NSPoint(x: 691, y: 517))
    play.line(to: NSPoint(x: 449, y: 689))
    play.curve(to: NSPoint(x: 427, y: 676), controlPoint1: NSPoint(x: 438, y: 695), controlPoint2: NSPoint(x: 427, y: 690))
    play.close()
    play.fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

var icons: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        try png(size: points * scale).write(to: iconDirectory.appendingPathComponent(name))
        icons.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try JSONSerialization.data(withJSONObject: ["images": icons, "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: iconDirectory.appendingPathComponent("Contents.json"))
try png(size: 512).write(to: markDirectory.appendingPathComponent("AppMark.png"))
try JSONSerialization.data(withJSONObject: ["images": [["idiom": "universal", "filename": "AppMark.png"]], "info": info], options: [.prettyPrinted, .sortedKeys])
    .write(to: markDirectory.appendingPathComponent("Contents.json"))
print("Generated macOS app icon (16–1024 px) and AppMark.")
