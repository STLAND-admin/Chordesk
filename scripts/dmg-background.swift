import AppKit

let output = CommandLine.arguments[1]
let scale = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 720 * scale, pixelsHigh: 420 * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 720, height: 420)).fill()
func text(_ value: String, y: CGFloat, size: CGFloat, secondary: Bool = false) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: secondary ? .regular : .semibold),
        .foregroundColor: NSColor(calibratedWhite: secondary ? 0.45 : 0.15, alpha: 1)]
    let string = NSAttributedString(string: value, attributes: attributes)
    string.draw(at: NSPoint(x: (720 - string.size().width) / 2, y: y))
}
text("Chordesk", y: 354, size: 28)
text("拖入 Applications 即可安装", y: 317, size: 19)
text("Drag Chordesk to Applications", y: 291, size: 13, secondary: true)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 294, y: 240)); arrow.line(to: NSPoint(x: 426, y: 240))
arrow.move(to: NSPoint(x: 409, y: 254)); arrow.line(to: NSPoint(x: 426, y: 240)); arrow.line(to: NSPoint(x: 409, y: 226))
arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(calibratedWhite: 0.6, alpha: 1).setStroke(); arrow.stroke()
text("安装后，从“应用程序”打开 Chordesk", y: 65, size: 14, secondary: true)
text("Then open Chordesk from Applications", y: 43, size: 12, secondary: true)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
