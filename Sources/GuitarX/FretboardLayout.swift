import Foundation
import SwiftUI

/// Geometry of the fretboard in view points (top-left origin), before left-hand mirroring.
struct FretboardLayout {
    let width: Float
    let height: Float
    let strings: Int
    let frets: Int
    let leftHanded: Bool

    let labelX: Float = 22
    let openX: Float = 64
    let nutX: Float = 92
    let boardRight: Float
    let lastFretX: Float
    let boardTop: Float
    let boardBottom: Float
    let spacing: Float
    let edgePad: Float
    let markerRadius: Float

    init(width: Float, height: Float, strings: Int, frets: Int, leftHanded: Bool) {
        let s = max(strings, 1)
        let f = max(frets, 1)
        self.width = width
        self.height = height
        self.strings = s
        self.frets = f
        self.leftHanded = leftHanded

        let right = width - 22
        boardRight = right
        lastFretX = right - 10

        let topMargin: Float = FretboardLayout.topMargin
        let bottomMargin: Float = FretboardLayout.bottomMargin
        let availH = max(height - topMargin - bottomMargin, 60)
        let n = Float(s)
        let sp = min(availH / (n - 1 + 1.2), FretboardLayout.maxSpacing)
        spacing = sp
        edgePad = sp * 0.6
        let boardH = sp * (n - 1) + sp * 1.2
        boardTop = topMargin + max(0, availH - boardH) * 0.5
        boardBottom = boardTop + boardH

        let narrow = (right - 10 - 92) * (FretboardLayout.norm(f, f) - FretboardLayout.norm(f - 1, f))
        markerRadius = max(6, min(sp * 0.38, narrow * 0.44, 16))
    }

    static let topMargin: Float = 14
    static let bottomMargin: Float = 36
    static let maxSpacing: Float = 46

    /// View height at which the board uses its full string spacing.
    static func idealHeight(strings: Int) -> CGFloat {
        CGFloat(topMargin + bottomMargin + maxSpacing * (Float(max(strings, 1)) - 1 + 1.2))
    }

    /// Blend of real (equal-tempered) fret spacing and linear spacing, so high frets stay usable.
    static func norm(_ n: Int, _ total: Int) -> Float {
        let real = (1 - pow(2, -Float(n) / 12)) / (1 - pow(2, -Float(total) / 12))
        let lin = Float(n) / Float(total)
        return 0.62 * real + 0.38 * lin
    }

    func fretX(_ n: Int) -> Float { nutX + (lastFretX - nutX) * FretboardLayout.norm(n, frets) }

    func noteX(_ fret: Int) -> Float {
        if fret == 0 { return openX }
        let a = fretX(fret - 1), b = fretX(fret)
        return a + (b - a) * 0.56
    }

    func cellCenterX(_ fret: Int) -> Float { (fretX(fret - 1) + fretX(fret)) * 0.5 }

    func stringY(_ s: Int) -> Float { boardTop + edgePad + Float(strings - 1 - s) * spacing }

    var boardCenterY: Float { (boardTop + boardBottom) * 0.5 }

    func hitTest(x rawX: Float, y: Float) -> FretPos? {
        let x = leftHanded ? width - rawX : rawX
        guard y > boardTop - 6, y < boardBottom + 6 else { return nil }
        let sf = (boardTop + edgePad + Float(strings - 1) * spacing - y) / spacing
        let s = Int(sf.rounded())
        guard s >= 0, s < strings, abs(sf - Float(s)) < 0.5 else { return nil }
        if x >= openX - 22 && x < nutX { return FretPos(string: s, fret: 0) }
        guard x >= nutX, x <= lastFretX else { return nil }
        for f in 1...frets where x <= fretX(f) {
            return FretPos(string: s, fret: f)
        }
        return nil
    }
}

// MARK: - Colors

enum Palette {
    static let root = SIMD3<Float>(0.91, 0.33, 0.25)        // vermilion
    static let neutral = SIMD3<Float>(0.80, 0.80, 0.78)     // warm light grey

    /// Function scheme: only root, 3rd, 5th and 7th carry colour.
    static let function: [Int: SIMD3<Float>] = [
        3: SIMD3(0.95, 0.73, 0.27),     // amber
        5: SIMD3(0.27, 0.60, 0.92),     // blue
        7: SIMD3(0.60, 0.45, 0.90),     // violet
    ]

    /// Spectrum scheme: one restrained hue per degree.
    static let spectrum: [SIMD3<Float>] = [
        neutral,
        root,
        SIMD3(0.90, 0.54, 0.24),    // 2
        SIMD3(0.95, 0.75, 0.28),    // 3
        SIMD3(0.42, 0.74, 0.43),    // 4
        SIMD3(0.27, 0.64, 0.86),    // 5
        SIMD3(0.40, 0.48, 0.90),    // 6
        SIMD3(0.65, 0.45, 0.88),    // 7
    ]

    static func rgb(degree: Int, isRoot: Bool, mode: ColorMode) -> SIMD3<Float> {
        if isRoot { return root }
        switch mode {
        case .function: return function[degree] ?? neutral
        case .spectrum: return spectrum[max(0, min(7, degree))]
        case .rootOnly: return neutral
        }
    }

    /// Dark text on light fills, white on saturated/dark ones.
    static func textRGB(on c: SIMD3<Float>) -> SIMD3<Float> {
        let lum = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
        return lum > 0.55 ? SIMD3(0.09, 0.09, 0.10) : SIMD3(1, 1, 1)
    }

    static func color(_ c: SIMD3<Float>) -> Color {
        Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }

    static func color(degree: Int, isRoot: Bool, mode: ColorMode) -> Color {
        color(rgb(degree: degree, isRoot: isRoot, mode: mode))
    }

    static func textColor(degree: Int, isRoot: Bool, mode: ColorMode) -> Color {
        color(textRGB(on: rgb(degree: degree, isRoot: isRoot, mode: mode)))
    }
}

struct WoodTheme {
    let wood1: SIMD4<Float>
    let wood2: SIMD4<Float>
    let inlay1: SIMD4<Float>
    let inlay2: SIMD4<Float>
    var binding: SIMD4<Float> = [0.86, 0.83, 0.74, 0.55]

    static func of(_ style: WoodStyle) -> WoodTheme {
        switch style {
        case .rosewood:
            return WoodTheme(wood1: [0.19, 0.105, 0.065, 1], wood2: [0.33, 0.19, 0.11, 1],
                             inlay1: [0.95, 0.94, 0.90, 1], inlay2: [0.78, 0.86, 0.93, 1])
        case .ebony:
            return WoodTheme(wood1: [0.065, 0.058, 0.055, 1], wood2: [0.15, 0.125, 0.11, 1],
                             inlay1: [0.95, 0.94, 0.90, 1], inlay2: [0.80, 0.88, 0.95, 1])
        case .maple:
            return WoodTheme(wood1: [0.78, 0.60, 0.38, 1], wood2: [0.93, 0.78, 0.56, 1],
                             inlay1: [0.10, 0.09, 0.08, 1], inlay2: [0.22, 0.19, 0.17, 1],
                             binding: [0.30, 0.22, 0.14, 0.6])
        }
    }
}
