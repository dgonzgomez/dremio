import AppKit

// Renders assets/icon.png (1024², macOS icon grid) from assets/dremio-mark.svg.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024.0
guard let mark = NSImage(contentsOf: root.appendingPathComponent("assets/dremio-mark.svg")) else { fatalError("mark") }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(srgbRed: 0.09, green: 0.15, blue: 0.11, alpha: 1), ending: NSColor(srgbRed: 0.027, green: 0.047, blue: 0.035, alpha: 1))!.draw(in: shape, angle: -90)
NSGraphicsContext.current!.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.74, green: 1, blue: 0.35, alpha: 0.28), NSColor(srgbRed: 0.74, green: 1, blue: 0.35, alpha: 0)])!
  .draw(fromCenter: NSPoint(x: 512, y: 250), radius: 0, toCenter: NSPoint(x: 512, y: 250), radius: 380, options: [])
NSGraphicsContext.current!.restoreGraphicsState()
NSColor(srgbRed: 0.3, green: 0.41, blue: 0.32, alpha: 0.35).setStroke()
shape.lineWidth = 3
shape.stroke()

let h = 520.0, w = h * 48 / 56
mark.draw(in: NSRect(x: 512 - w / 2, y: 512 - h / 2 + 20, width: w, height: h))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("assets/icon.png"))
