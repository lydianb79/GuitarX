import MetalKit
import Combine
import QuartzCore

struct GPUInstance {
    var rect: SIMD4<Float>
    var color: SIMD4<Float>
    var color2: SIMD4<Float>
    var params: SIMD4<Float>
    var uv: SIMD4<Float>
}

struct GPUUniforms {
    var viewport: SIMD2<Float>
    var time: Float
    var scale: Float
}

private enum Kind: Float {
    case wood = 0, rect = 1, string = 2, marker = 3, text = 4, ring = 5, inlay = 6, vignette = 7
}

private struct MarkerAnim {
    var presence: Float
    var key: String
}

@inline(__always) private func rgba(_ c: SIMD3<Float>, _ a: Float) -> SIMD4<Float> { SIMD4<Float>(c.x, c.y, c.z, a) }

private func desaturate(_ c: SIMD3<Float>, _ amount: Float) -> SIMD3<Float> {
    let g = (c.x + c.y + c.z) / 3
    return c + (SIMD3<Float>(repeating: g) - c) * amount
}

final class FretboardRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let atlas: LabelAtlas
    private weak var state: AppState?
    private var cancellable: AnyCancellable?

    private var dirty = true
    private var markers: [Marker] = []
    private var anim: [FretPos: MarkerAnim] = [:]
    private var instances: [GPUInstance] = []
    private var layout: FretboardLayout?
    private var lastTime = CACurrentMediaTime()
    private var mirrorWidth: Float = 0
    private var mirrorOn = false
    /// Print-friendly palette (white background, light board) — used for PDF export.
    private var lightMode = false

    init?(view: MTKView, state: AppState) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let atlas = LabelAtlas(device: device) else { return nil }
        self.device = device
        self.queue = queue
        self.atlas = atlas
        self.state = state
        do {
            let lib = try device.makeLibrary(source: ShaderSource.code, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "vmain")
            d.fragmentFunction = lib.makeFunction(name: "fmain")
            let ca = d.colorAttachments[0]!
            ca.pixelFormat = view.colorPixelFormat
            ca.isBlendingEnabled = true
            ca.rgbBlendOperation = .add
            ca.alphaBlendOperation = .add
            ca.sourceRGBBlendFactor = .one
            ca.sourceAlphaBlendFactor = .one
            ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
            ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: d)
        } catch {
            NSLog("GuitarX: Metal pipeline error: \(error)")
            return nil
        }
        super.init()
        cancellable = state.objectWillChange.sink { [weak self] _ in self?.dirty = true }
    }

    func hitTest(x: Float, y: Float) -> FretPos? { layout?.hitTest(x: x, y: y) }

    /// Renders the current state off-screen (no animation, hover or pulses) for export.
    func renderImage(width: Int, height: Int, scale: Int = 3, light: Bool = false) -> CGImage? {
        guard let state = state, width > 0, height > 0 else { return nil }
        let pw = width * scale
        let ph = height * scale
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pw, height: ph, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .managed
        guard let target = device.makeTexture(descriptor: desc),
              let cmd = queue.makeCommandBuffer() else { return nil }

        let savedMarkers = markers
        let savedWidth = mirrorWidth
        let savedMirror = mirrorOn
        markers = state.computeMarkers()
        let L = FretboardLayout(width: Float(width), height: Float(height),
                                strings: state.tuning.notes.count, frets: state.fretCount,
                                leftHanded: state.leftHanded)
        mirrorWidth = L.width
        mirrorOn = L.leftHanded
        instances.removeAll(keepingCapacity: true)
        lightMode = light
        buildScene(L, state: state, now: CACurrentMediaTime(), dt: 0, export: true)
        lightMode = false
        markers = savedMarkers
        mirrorWidth = savedWidth
        mirrorOn = savedMirror
        dirty = true

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = light ? MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
                                                   : MTLClearColor(red: 0.055, green: 0.055, blue: 0.065, alpha: 1)
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
        let byteCount = MemoryLayout<GPUInstance>.stride * instances.count
        if byteCount > 0,
           let buffer = instances.withUnsafeBytes({ raw in
               device.makeBuffer(bytes: raw.baseAddress!, length: byteCount, options: .storageModeShared)
           }) {
            var u = GPUUniforms(viewport: SIMD2<Float>(L.width, L.height), time: 0, scale: Float(scale))
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBuffer(buffer, offset: 0, index: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<GPUUniforms>.stride, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<GPUUniforms>.stride, index: 1)
            enc.setFragmentTexture(atlas.texture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
        }
        enc.endEncoding()
        if let blit = cmd.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        cmd.commit()
        cmd.waitUntilCompleted()

        let bytesPerRow = pw * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * ph)
        pixels.withUnsafeMutableBytes { raw in
            target.getBytes(raw.baseAddress!, bytesPerRow: bytesPerRow,
                            from: MTLRegionMake2D(0, 0, pw, ph), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: pw, height: ph, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let state = state,
              let rpd = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let cmd = queue.makeCommandBuffer() else { return }

        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, max(0, now - lastTime)))
        lastTime = now

        if dirty {
            markers = state.computeMarkers()
            dirty = false
        }

        let size = view.bounds.size
        let L = FretboardLayout(width: Float(max(size.width, 1)), height: Float(max(size.height, 1)),
                                strings: state.tuning.notes.count, frets: state.fretCount,
                                leftHanded: state.leftHanded)
        layout = L
        mirrorWidth = L.width
        mirrorOn = L.leftHanded

        instances.removeAll(keepingCapacity: true)
        buildScene(L, state: state, now: now, dt: dt, export: false)

        rpd.colorAttachments[0].loadAction = .clear
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        let byteCount = MemoryLayout<GPUInstance>.stride * instances.count
        if byteCount > 0,
           let buffer = instances.withUnsafeBytes({ raw in
               device.makeBuffer(bytes: raw.baseAddress!, length: byteCount, options: .storageModeShared)
           }) {
            var u = GPUUniforms(viewport: SIMD2<Float>(L.width, L.height),
                                time: Float(now.truncatingRemainder(dividingBy: 1000)),
                                scale: Float(view.window?.backingScaleFactor ?? 2))
            enc.setRenderPipelineState(pipeline)
            enc.setVertexBuffer(buffer, offset: 0, index: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<GPUUniforms>.stride, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<GPUUniforms>.stride, index: 1)
            enc.setFragmentTexture(atlas.texture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: instances.count)
        }
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Scene

    private func emit(_ kind: Kind, x: Float, y: Float, w: Float, h: Float,
                      c1: SIMD4<Float>, c2: SIMD4<Float>? = nil,
                      p1: Float = 0, soft: Float = 0, p3: Float = 0,
                      uv: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0), mirror: Bool = true) {
        let mx = (mirror && mirrorOn) ? mirrorWidth - x : x
        instances.append(GPUInstance(rect: SIMD4<Float>(mx, y, w, h),
                                     color: c1, color2: c2 ?? c1,
                                     params: SIMD4<Float>(kind.rawValue, p1, soft, p3),
                                     uv: uv))
    }

    private func text(_ s: String, x: Float, y: Float, height: Float, color: SIMD4<Float>, bold: Bool = true) {
        guard !s.isEmpty, color.w > 0.01 else { return }
        let uv = atlas.uv(for: s, bold: bold)
        emit(.text, x: x, y: y, w: height * 2, h: height, c1: color, uv: uv)
    }

    private func buildScene(_ L: FretboardLayout, state: AppState, now: Double, dt: Float, export: Bool) {
        let light = lightMode
        let theme = WoodTheme.of(state.wood)
        let tuning = state.tuning

        // Background
        if light {
            emit(.vignette, x: L.width / 2, y: L.height / 2, w: L.width, h: L.height,
                 c1: [1, 1, 1, 1], c2: [1, 1, 1, 1], mirror: false)
        } else {
            emit(.vignette, x: L.width / 2, y: L.height / 2, w: L.width, h: L.height,
                 c1: [0.105, 0.105, 0.115, 1], c2: [0.085, 0.085, 0.095, 1], mirror: false)
        }

        let boardW = L.boardRight - L.nutX
        let cx = L.nutX + boardW / 2
        let cy = L.boardCenterY
        let bh = L.boardBottom - L.boardTop

        // Board shadow + wood
        if light {
            emit(.rect, x: cx, y: cy, w: boardW, h: bh, c1: [0.965, 0.962, 0.955, 1], p1: 2)
            emit(.rect, x: cx, y: L.boardTop + 0.6, w: boardW, h: 1.2, c1: [0.55, 0.55, 0.55, 1])
            emit(.rect, x: cx, y: L.boardBottom - 0.6, w: boardW, h: 1.2, c1: [0.55, 0.55, 0.55, 1])
        } else {
            emit(.rect, x: cx, y: cy + 6, w: boardW, h: bh, c1: [0, 0, 0, 0.55], p1: 4, soft: 12)
            emit(.wood, x: cx, y: cy, w: boardW, h: bh, c1: theme.wood1, c2: theme.wood2, p1: 2)
            // Binding along both long edges
            emit(.rect, x: cx, y: L.boardTop + 0.9, w: boardW, h: 1.8, c1: theme.binding)
            emit(.rect, x: cx, y: L.boardBottom - 0.9, w: boardW, h: 1.8, c1: theme.binding)
        }
        let inlay1: SIMD4<Float> = light ? [0.84, 0.84, 0.82, 1] : theme.inlay1
        let inlay2: SIMD4<Float> = light ? [0.80, 0.80, 0.79, 1] : theme.inlay2

        // Inlays
        let single: Set<Int> = [3, 5, 7, 9, 15, 17, 19, 21]
        let double: Set<Int> = [12, 24]
        let ir = min(L.spacing * 0.2, 7)
        for f in 1...L.frets {
            let x = L.cellCenterX(f)
            if single.contains(f) {
                emit(.inlay, x: x, y: cy, w: ir * 2, h: ir * 2, c1: inlay1, c2: inlay2)
            } else if double.contains(f) {
                let off = bh * 0.25
                emit(.inlay, x: x, y: cy - off, w: ir * 2, h: ir * 2, c1: inlay1, c2: inlay2)
                emit(.inlay, x: x, y: cy + off, w: ir * 2, h: ir * 2, c1: inlay1, c2: inlay2)
            }
        }

        // Frets
        for f in 1...L.frets {
            let x = L.fretX(f)
            let w: Float = f > 16 ? 2.0 : 2.5
            if light {
                emit(.rect, x: x, y: cy, w: w * 0.8, h: bh - 2.4, c1: [0.62, 0.62, 0.62, 1])
            } else {
                emit(.rect, x: x + 1.6, y: cy, w: w, h: bh, c1: [0, 0, 0, 0.3], soft: 1.5)
                emit(.rect, x: x, y: cy, w: w, h: bh - 3.6, c1: [0.56, 0.56, 0.55, 1], c2: [0.95, 0.95, 0.93, 1], p1: 1, p3: 1)
            }
        }

        // Nut
        if light {
            emit(.rect, x: L.nutX - 3, y: cy, w: 6, h: bh + 2, c1: [0.22, 0.22, 0.24, 1], p1: 1)
        } else {
            emit(.rect, x: L.nutX + 2, y: cy, w: 7, h: bh + 4, c1: [0, 0, 0, 0.5], soft: 3)
            emit(.rect, x: L.nutX - 4, y: cy, w: 8, h: bh + 4, c1: [0.80, 0.77, 0.68, 1], c2: [0.99, 0.97, 0.91, 1], p1: 2, p3: 1)
        }

        // Strings
        let x0 = L.labelX + 20
        let x1 = L.boardRight
        let sw = x1 - x0
        let sxc = (x0 + x1) / 2
        for s in 0..<L.strings {
            let y = L.stringY(s)
            let midi = s < tuning.notes.count ? tuning.notes[s] : 52
            let t = max(0, min(1, (Float(midi) - 28) / 40))
            let th: Float = 3.8 - 2.6 * t
            let wound = midi < 55
            if light {
                emit(.rect, x: sxc, y: y, w: sw, h: max(1, th * 0.6), c1: [0.38, 0.38, 0.40, 1])
            } else {
                emit(.rect, x: sxc, y: y + 2.6, w: sw, h: th, c1: [0, 0, 0, 0.45], p1: th / 2, soft: 1.8)
                emit(.string, x: sxc, y: y, w: sw, h: th,
                     c1: wound ? [0.88, 0.78, 0.60, 1] : [0.94, 0.94, 0.97, 1],
                     c2: wound ? [0.30, 0.23, 0.15, 1] : [0.36, 0.36, 0.40, 1],
                     p3: wound ? 1 : 0)
            }
        }

        // Tuning labels
        for s in 0..<min(L.strings, tuning.notes.count) {
            let name = NoteName.from(pitchClass: tuning.notes[s], preferFlats: tuning.prefersFlats).text
            text(name, x: L.labelX, y: L.stringY(s), height: min(L.spacing * 0.62, 22),
                 color: light ? [0.30, 0.30, 0.32, 1] : [0.62, 0.62, 0.66, 1], bold: false)
        }

        // Fret numbers
        for f in 1...L.frets {
            let marked = single.contains(f) || double.contains(f)
            let numStrong: SIMD4<Float> = light ? [0.12, 0.12, 0.14, 1] : [0.78, 0.78, 0.81, 1]
            let numWeak: SIMD4<Float> = light ? [0.55, 0.55, 0.58, 1] : [0.40, 0.40, 0.44, 1]
            text("\(f)", x: L.noteX(f), y: L.boardBottom + 19, height: 15,
                 color: marked ? numStrong : numWeak, bold: false)
        }

        // Muted strings in voicing mode
        if let v = state.displayedVoicing {
            for s in 0..<min(L.strings, v.frets.count) where v.frets[s] == nil {
                text("×", x: L.openX, y: L.stringY(s), height: L.markerRadius * 1.6, color: [1.0, 0.45, 0.40, 0.9])
            }
        }

        // Markers
        if !export && !state.pulses.isEmpty {
            state.pulses = state.pulses.filter { now - $0.value < 2.0 }
        }
        var newAnim: [FretPos: MarkerAnim] = [:]
        let k = min(1, dt * 11)
        let orderedMarkers = markers.sorted { rank($0.role) < rank($1.role) }

        for m in orderedMarkers {
            let key = "\(m.label)|\(m.degree)|\(m.role)|\(m.isRoot)"
            var a = anim[m.pos] ?? MarkerAnim(presence: export ? 1 : 0, key: key)
            if export { a.presence = 1 }
            if a.key != key {
                a.presence = min(a.presence, 0.5)
                a.key = key
            }
            a.presence += (1 - a.presence) * k
            newAnim[m.pos] = a
            let e = 1 - pow(1 - a.presence, 3)

            let x = L.noteX(m.pos.fret)
            let y = L.stringY(m.pos.string)
            var r = L.markerRadius
            var base = Palette.rgb(degree: m.degree, isRoot: m.isRoot, mode: state.colorMode)
            var alpha: Float = 1
            var textRGB = Palette.textRGB(on: base)
            var glow: Float = 0

            switch m.role {
            case .active, .bass, .accent:
                break
            case .ghost:
                r *= 0.72
                alpha = light ? 0.4 : 0.3
                base = desaturate(base, 0.6)
            case .chromatic:
                r *= 0.6
                alpha = 0.85
                base = light ? SIMD3<Float>(0.86, 0.86, 0.87) : SIMD3<Float>(0.26, 0.26, 0.28)
                textRGB = light ? SIMD3<Float>(0.30, 0.30, 0.32) : SIMD3<Float>(0.80, 0.80, 0.83)
            }
            if m.pos.fret == 0 { r *= 0.92 }

            if !export, let t0 = state.pulses[m.pos] {
                let el = Float(now - t0)
                if el >= 0 && el < 0.7 {
                    let p = 1 - el / 0.7
                    r *= 1 + 0.2 * p
                    glow += 1.1 * p
                    alpha = max(alpha, p)
                }
            }

            r *= 0.55 + 0.45 * e
            alpha *= e

            emit(.rect, x: x, y: y + 1.5, w: r * 2, h: r * 2, c1: [0, 0, 0, (light ? 0.12 : 0.4) * alpha], p1: r, soft: 2.5)
            emit(.marker, x: x, y: y, w: r * 2, h: r * 2,
                 c1: rgba(base, alpha), c2: rgba(base * 0.62, alpha),
                 soft: glow > 0 ? r * 1.3 : 0, p3: glow)

            if m.role == .accent {
                let th: Float = 1.5
                let rr = r + 2.5
                emit(.ring, x: x, y: y, w: (rr + th) * 2, h: (rr + th) * 2, c1: light ? [0.80, 0.58, 0.10, 0.95 * alpha] : [0.96, 0.84, 0.52, 0.85 * alpha], p1: th)
            }

            if m.role == .bass {
                let th: Float = 1.8
                let rr = r + 3
                emit(.ring, x: x, y: y, w: (rr + th) * 2, h: (rr + th) * 2, c1: light ? [0.12, 0.12, 0.14, 0.9 * alpha] : [1, 1, 1, 0.9 * alpha], p1: th)
            }

            if !m.label.isEmpty {
                text(m.label, x: x, y: y + r * 0.02, height: r * 1.25, color: rgba(textRGB, alpha * (m.role == .ghost ? 0.85 : 1)))
            }
        }
        if !export { anim = newAnim }

        // Hover ring
        if !export, let h = state.hover, h.string < L.strings, h.fret <= L.frets {
            let x = L.noteX(h.fret)
            let y = L.stringY(h.string)
            let th: Float = 1.5
            let rr = L.markerRadius + 3.5
            emit(.ring, x: x, y: y, w: (rr + th) * 2, h: (rr + th) * 2, c1: [1, 1, 1, 0.55], p1: th)
        }
    }

    private func rank(_ r: MarkerRole) -> Int {
        switch r {
        case .chromatic: return 0
        case .ghost: return 1
        case .active: return 2
        case .accent: return 3
        case .bass: return 4
        }
    }
}
