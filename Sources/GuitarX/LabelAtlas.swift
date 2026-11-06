import AppKit
import Metal
import CoreText

/// Rasterises label strings on demand (CoreText) into a single-channel Metal texture atlas.
final class LabelAtlas {
    let texture: MTLTexture
    private let size = 2048
    private let cellW = 128
    private let cellH = 64
    private var next = 0
    private var cache: [String: SIMD4<Float>] = [:]

    init?(device: MTLDevice) {
        let size = 2048
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: size, height: size, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .managed
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        texture = t
        let zeros = [UInt8](repeating: 0, count: size * size)
        zeros.withUnsafeBytes { raw in
            t.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                      withBytes: raw.baseAddress!, bytesPerRow: size)
        }
    }

    func uv(for text: String, bold: Bool) -> SIMD4<Float> {
        let key = (bold ? "B|" : "R|") + text
        if let hit = cache[key] { return hit }

        let cols = size / cellW
        let rows = size / cellH
        if next >= cols * rows {          // atlas full: start over
            next = 0
            cache.removeAll()
        }
        let slot = next
        next += 1
        let x = (slot % cols) * cellW
        let y = (slot / cols) * cellH

        let pixels = render(text, bold: bold)
        pixels.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(x, y, cellW, cellH), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: cellW)
        }
        let s = Float(size)
        let inset: Float = 0.5
        let uv = SIMD4<Float>((Float(x) + inset) / s, (Float(y) + inset) / s,
                              (Float(x + cellW) - inset) / s, (Float(y + cellH) - inset) / s)
        cache[key] = uv
        return uv
    }

    private func render(_ text: String, bold: Bool) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: cellW * cellH)
        let w = cellW, h = cellH
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setShouldAntialias(true)
            ctx.setAllowsFontSmoothing(false)
            ctx.textMatrix = .identity

            func makeLine(_ fontSize: CGFloat) -> (CTLine, NSFont, CGFloat) {
                let font = NSFont.systemFont(ofSize: fontSize, weight: bold ? .semibold : .regular)
                let attr = NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.white
                ])
                let line = CTLineCreateWithAttributedString(attr)
                let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                return (line, font, width)
            }

            var fontSize: CGFloat = 40
            var (line, font, width) = makeLine(fontSize)
            while width > CGFloat(w - 8) && fontSize > 12 {
                fontSize -= 2
                (line, font, width) = makeLine(fontSize)
            }

            let baseline = (CGFloat(h) - font.capHeight) * 0.5
            ctx.textPosition = CGPoint(x: (CGFloat(w) - width) * 0.5, y: baseline)
            CTLineDraw(line, ctx)
        }
        return bytes
    }
}
