import Foundation

enum CAGEDShape: String, CaseIterable, Identifiable {
    case C, A, G, E, D
    var id: String { rawValue }
}

enum CAGEDQuality {
    case major, minor, dom7, maj7, min7
}

/// A CAGED shape placed on the neck for a given root.
struct PlacedShape: Identifiable {
    let shape: CAGEDShape
    let frets: [Int?]          // one entry per tuning string, nil = not part of the shape

    var id: String { shape.rawValue }
    var minFret: Int { frets.compactMap { $0 }.min() ?? 0 }
    var maxFret: Int { frets.compactMap { $0 }.max() ?? 0 }
    var positions: [FretPos] {
        frets.enumerated().compactMap { s, f in f.map { FretPos(string: s, fret: $0) } }
    }
    var voicing: Voicing { Voicing(frets: frets) }
}

enum CAGED {
    /// Which of the 6 standard strings (0 = low E) carries the shape's anchoring root.
    static let anchorString: [CAGEDShape: Int] = [.C: 1, .A: 1, .G: 0, .E: 0, .D: 2]

    /// Fret offsets relative to the anchor root, low E → high e. nil = muted.
    static func template(_ shape: CAGEDShape, _ q: CAGEDQuality) -> [Int?] {
        switch q {
        case .major:
            switch shape {
            case .C: return [nil, 0, -1, -3, -2, -3]
            case .A: return [nil, 0, 2, 2, 2, 0]
            case .G: return [0, -1, -3, -3, -3, 0]
            case .E: return [0, 2, 2, 1, 0, 0]
            case .D: return [nil, nil, 0, 2, 3, 2]
            }
        case .minor:
            switch shape {
            case .C: return [nil, 0, -2, -3, -2, 0]
            case .A: return [nil, 0, 2, 2, 1, 0]
            case .G: return [0, -2, -3, -3, 0, 0]
            case .E: return [0, 2, 2, 0, 0, 0]
            case .D: return [nil, nil, 0, 2, 3, 1]
            }
        case .dom7:
            switch shape {
            case .C: return [nil, 0, -1, 0, -2, -3]
            case .A: return [nil, 0, 2, 0, 2, 0]
            case .G: return [0, -1, -3, -3, -3, -2]
            case .E: return [0, 2, 0, 1, 0, 0]
            case .D: return [nil, nil, 0, 2, 1, 2]
            }
        case .maj7:
            switch shape {
            case .C: return [nil, 0, -1, -3, -3, -3]
            case .A: return [nil, 0, 2, 1, 2, 0]
            case .G: return [0, -1, -3, -3, -3, -1]
            case .E: return [0, 2, 1, 1, 0, 0]
            case .D: return [nil, nil, 0, 2, 2, 2]
            }
        case .min7:
            switch shape {
            case .C: return [nil, 0, -2, 0, -2, 0]
            case .A: return [nil, 0, 2, 0, 1, 0]
            case .G: return [0, -2, 0, 0, 0, 0]
            case .E: return [0, 2, 0, 0, 0, 0]
            case .D: return [nil, nil, 0, 2, 1, 1]
            }
        }
    }

    /// Exact CAGED grips exist for these chord qualities.
    static func quality(of chord: ChordType) -> CAGEDQuality? {
        let pcs = Set(chord.intervals.map(\.pitchClass))
        guard pcs.count == chord.intervals.count else { return nil }
        if pcs == Set([0, 4, 7]) { return .major }
        if pcs == Set([0, 3, 7]) { return .minor }
        if pcs == Set([0, 4, 7, 10]) { return .dom7 }
        if pcs == Set([0, 4, 7, 11]) { return .maj7 }
        if pcs == Set([0, 3, 7, 10]) { return .min7 }
        return nil
    }

    /// Major or minor frame used for regions when there's no exact grip.
    static func frameQuality(minorThird: Bool) -> CAGEDQuality { minorThird ? .minor : .major }

    /// Index of the lowest of six consecutive strings tuned in standard intervals (4 4 4 M3 4), if any.
    static func stringOffset(_ tuning: [Int]) -> Int? {
        guard tuning.count >= 6 else { return nil }
        for o in stride(from: tuning.count - 6, through: 0, by: -1) {
            let d = (0..<5).map { tuning[o + $0 + 1] - tuning[o + $0] }
            if d == [5, 5, 5, 4, 5] { return o }
        }
        return nil
    }

    /// The five shapes for a root, ordered from nut to body.
    static func place(tuning: [Int], rootPC: Int, quality: CAGEDQuality, fretCount: Int) -> [PlacedShape] {
        guard let o = stringOffset(tuning) else { return [] }
        var out: [PlacedShape] = []
        for shape in CAGEDShape.allCases {
            let t = template(shape, quality)
            let anchor = o + (anchorString[shape] ?? 0)
            let offs = t.compactMap { $0 }
            let minOff = offs.min() ?? 0
            let maxOff = offs.max() ?? 0
            var r = mod12(rootPC - tuning[anchor])
            while r + minOff < 0 { r += 12 }
            guard r + maxOff <= fretCount else { continue }
            var frets = [Int?](repeating: nil, count: tuning.count)
            for i in 0..<6 {
                if let off = t[i] { frets[o + i] = r + off }
            }
            out.append(PlacedShape(shape: shape, frets: frets))
        }
        return out.sorted { $0.minFret < $1.minFret }
    }
}
