import AppKit

func draw(_ size: Int, _ file: String) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let base = NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 202, yRadius: 202)
    NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.39, blue: 0.95, alpha: 1), ending: NSColor(srgbRed: 0.17, green: 0.76, blue: 0.88, alpha: 1))!.draw(in: base, angle: 40)
    let bar = NSBezierPath(roundedRect: NSRect(x: 170, y: 300, width: 684, height: 430), xRadius: 76, yRadius: 76)
    NSColor.white.withAlphaComponent(0.96).setFill()
    bar.fill()
    let notch = NSBezierPath(roundedRect: NSRect(x: 407, y: 658, width: 210, height: 112), xRadius: 30, yRadius: 30)
    NSColor(srgbRed: 0.10, green: 0.22, blue: 0.48, alpha: 1).setFill()
    notch.fill()
    let arrow = NSBezierPath()
    arrow.lineWidth = 38
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 296, y: 501)); arrow.line(to: NSPoint(x: 728, y: 501))
    arrow.move(to: NSPoint(x: 369, y: 574)); arrow.line(to: NSPoint(x: 296, y: 501)); arrow.line(to: NSPoint(x: 369, y: 428))
    arrow.move(to: NSPoint(x: 655, y: 574)); arrow.line(to: NSPoint(x: 728, y: 501)); arrow.line(to: NSPoint(x: 655, y: 428))
    NSColor(srgbRed: 0.12, green: 0.38, blue: 0.84, alpha: 1).setStroke()
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: file))
}
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try draw(points, "\(directory)/icon_\(points)x\(points).png")
    try draw(points * 2, "\(directory)/icon_\(points)x\(points)@2x.png")
}
