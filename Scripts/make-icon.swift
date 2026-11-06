// Draws the GuitarX app icon (1024×1024 PNG). Usage: swift Scripts/make-icon.swift out.png
import AppKit

let size = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let gctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// Squircle background
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0, 0, 0, 0.45))
ctx.addPath(tilePath)
ctx.setFillColor(color(0.08, 0.08, 0.1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [color(0.17, 0.17, 0.21), color(0.06, 0.06, 0.08)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// Fretboard slab
let board = CGRect(x: 100, y: 312, width: 824, height: 400)
let wood = CGGradient(colorsSpace: space, colors: [color(0.38, 0.22, 0.13), color(0.22, 0.12, 0.07)] as CFArray,
                      locations: [0, 1])!
ctx.saveGState()
ctx.clip(to: board)
ctx.drawLinearGradient(wood, start: CGPoint(x: 512, y: board.maxY), end: CGPoint(x: 512, y: board.minY), options: [])
ctx.restoreGState()

// Frets
let fretXs: [CGFloat] = [230, 395, 545, 680, 800]
for x in fretXs {
    ctx.setFillColor(color(0.85, 0.85, 0.83))
    ctx.fill(CGRect(x: x - 6, y: board.minY, width: 12, height: board.height))
}

// Strings
for i in 0..<6 {
    let y = board.minY + 40 + CGFloat(i) * 64
    let w = 4 + CGFloat(i) * 1.6
    ctx.setFillColor(i >= 3 ? color(0.88, 0.78, 0.6) : color(0.93, 0.93, 0.96))
    ctx.fill(CGRect(x: 100, y: y - w / 2, width: 824, height: w))
}

// Note markers
let dots: [(CGFloat, Int, (CGFloat, CGFloat, CGFloat))] = [
    (312, 1, (1.00, 0.42, 0.35)),
    (470, 3, (1.00, 0.80, 0.32)),
    (612, 2, (0.32, 0.83, 0.80)),
    (470, 5, (0.71, 0.60, 1.00)),
    (740, 4, (0.40, 0.71, 1.00)),
]
for (x, s, c) in dots {
    let y = board.minY + 40 + CGFloat(s) * 64
    let r: CGFloat = 46
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: color(0, 0, 0, 0.5))
    ctx.setFillColor(color(c.0, c.1, c.2))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard CommandLine.arguments.count > 1,
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
