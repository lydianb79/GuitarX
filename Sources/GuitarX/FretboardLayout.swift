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

        let topMargin: Float = 26
        let bottomMargin: Float = 44
        let availH = max(height - topMargin - bottomMargin, 60)
        let n = Float(s)
        let sp = min(availH / (n - 1 + 1.2), 50)
        spacing = sp
        edgePad = sp * 0.6
        let boardH = sp * (n - 1) + sp * 1.2
        boardTop = topMargin + (availH - boardH) * 0.5
        boardBottom = boardTop + boardH

        let narrow = (right - 10 - 92) * (FretboardLayout.norm(f, f) - FretboardLayout.norm(f - 1, f))
        markerRadius = max(6, min(sp * 0.40, narrow * 0.44, 17))
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
    /// index 0 = neutral, 1...7 = interval degree colours
    static let degreeColors: [SIMD3<Float>] = [
        SIMD3(0.93, 0.91, 0.86),
        SIMD3(1.00, 0.42, 0.35),   // 1  coral
        SIMD3(0.40, 0.71, 1.00),   // 2  sky
        SIMD3(1.00, 0.80, 0.32),   // 3  gold
        SIMD3(0.47, 0.87, 0.56),   // 4  green
        SIMD3(0.32, 0.83, 0.80),   // 5  teal
        SIMD3(1.00, 0.56, 0.79),   // 6  pink
        SIMD3(0.71, 0.60, 1.00),   // 7  violet
    ]

    static func rgb(degree: Int, isRoot: Bool, colorful: Bool) -> SIMD3<Float> {
        if isRoot { return degreeColors[1] }
        if !colorful { return degreeColors[0] }
        return degreeColors[max(0, min(7, degree))]
    }

    static func color(degree: Int, isRoot: Bool, colorful: Bool) -> Color {
        let c = rgb(degree: degree, isRoot: isRoot, colorful: colorful)
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }
}

struct WoodTheme {
    let wood1: SIMD4<Float>
    let wood2: SIMD4<Float>
    let inlay1: SIMD4<Float>
    let inlay2: SIMD4<Float>

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
                             inlay1: [0.10, 0.09, 0.08, 1], inlay2: [0.22, 0.19, 0.17, 1])
        }
    }
}
