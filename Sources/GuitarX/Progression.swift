import Foundation

/// One chord of a progression, resolved against the current key.
struct ProgressionChord: Identifiable {
    let id: Int
    let token: String
    let interval: Interval      // from the key root
    let chord: ChordType
    let root: NoteName

    var rootPC: Int { root.pitchClass }
    var name: String { root.text + chord.symbol }
}

struct ProgressionPreset: Identifiable {
    let name: String
    let text: String
    var id: String { name }
}

enum ProgressionLibrary {
    static let presets: [ProgressionPreset] = [
        ProgressionPreset(name: "Pop  I–V–vi–IV", text: "I V vi IV"),
        ProgressionPreset(name: "Sensitive  vi–IV–I–V", text: "vi IV I V"),
        ProgressionPreset(name: "50s  I–vi–IV–V", text: "I vi IV V"),
        ProgressionPreset(name: "Plagal Rock  I–IV", text: "I IV I IV"),
        ProgressionPreset(name: "Mixolydian Rock  I–♭VII–IV", text: "I bVII IV I"),
        ProgressionPreset(name: "Aeolian  i–♭VI–♭III–♭VII", text: "i bVI bIII bVII"),
        ProgressionPreset(name: "Andalusian Cadence", text: "i bVII bVI V"),
        ProgressionPreset(name: "Minor  i–iv–v–i", text: "i iv v i"),
        ProgressionPreset(name: "Pachelbel Canon", text: "I V vi iii IV I IV V"),
        ProgressionPreset(name: "Jazz  ii–V–I", text: "ii7 V7 Imaj7"),
        ProgressionPreset(name: "Minor  iiø–V–i", text: "iiø7 V7b9 i7"),
        ProgressionPreset(name: "Turnaround  I–vi–ii–V", text: "Imaj7 vi7 ii7 V7"),
        ProgressionPreset(name: "Circle  iii–vi–ii–V–I", text: "iii7 vi7 ii7 V7 Imaj7"),
        ProgressionPreset(name: "Bossa  ii–V–I–VI", text: "ii7 V7 Imaj7 VI7"),
        ProgressionPreset(name: "Royal Road  IV–V–iii–vi", text: "IVmaj7 V7 iii7 vi"),
        ProgressionPreset(name: "12-Bar Blues", text: "I7 I7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7"),
        ProgressionPreset(name: "12-Bar Blues (quick change)", text: "I7 IV7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7"),
        ProgressionPreset(name: "Minor Blues", text: "i7 i7 i7 i7 iv7 iv7 i7 i7 bVI7 V7 i7 V7"),
    ]
}

enum ProgressionParser {
    private static let romans = ["I", "II", "III", "IV", "V", "VI", "VII"]

    /// Splits text into tokens and resolves each against the key.
    static func parse(_ text: String, key: NoteName) -> (chords: [ProgressionChord], invalid: [String]) {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—|,"))
        let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }
        var chords: [ProgressionChord] = []
        var invalid: [String] = []
        for tok in tokens {
            if let resolved = resolve(tok) {
                let iv = resolved.0
                chords.append(ProgressionChord(id: chords.count, token: tok, interval: iv, chord: resolved.1,
                                               root: key.adding(iv)))
            } else {
                invalid.append(tok)
            }
        }
        return (chords, invalid)
    }

    static func resolve(_ token: String) -> (Interval, ChordType)? {
        var chars = Array(token)
        var acc = 0
        while let c = chars.first, "b♭#♯".contains(c) {
            acc += (c == "b" || c == "♭") ? -1 : 1
            chars.removeFirst()
        }
        var run = 0
        while run < chars.count, "IViv".contains(chars[run]) { run += 1 }
        guard run > 0 else { return nil }
        var degree = 0
        var used = 0
        for len in stride(from: min(run, 3), through: 1, by: -1) {
            let s = String(chars[0..<len]).uppercased()
            if let i = romans.firstIndex(of: s) { degree = i + 1; used = len; break }
        }
        guard degree > 0 else { return nil }
        let upper = chars[0].isUppercase
        let suffix = normalize(String(chars[used...]))

        var candidates: [String] = []
        if upper {
            candidates = [suffix]
        } else {
            switch suffix {
            case "": candidates = ["m"]
            case "maj7": candidates = ["m(maj7)"]
            case "maj9": candidates = ["m(maj9)"]
            case "add9": candidates = ["m(add9)"]
            default:
                if suffix.hasPrefix("ø") || suffix.hasPrefix("°") { candidates = [suffix] }
                else { candidates = ["m" + suffix, suffix] }
            }
        }
        for sym in candidates {
            if let c = ChordLibrary.all.first(where: { $0.symbol == sym }) {
                return (Interval(degree: degree, accidental: acc), c)
            }
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        let whole: [String: String] = [
            "M7": "maj7", "Δ": "maj7", "Δ7": "maj7", "ma7": "maj7", "M9": "maj9",
            "dim": "°", "o": "°", "dim7": "°7", "o7": "°7",
            "m7b5": "ø7", "m7♭5": "ø7", "ø": "ø7", "h7": "ø7",
            "aug": "+", "aug7": "+7",
        ]
        if let w = whole[s] { return w }
        return s.replacingOccurrences(of: "b", with: "♭").replacingOccurrences(of: "#", with: "♯")
    }

    /// Roman-numeral token for a chord built on a scale degree (inverse of `resolve`).
    static func token(interval: Interval, chord: ChordType) -> String {
        let prefix = interval.accidental < 0
            ? String(repeating: "b", count: -interval.accidental)
            : String(repeating: "#", count: interval.accidental)
        var numeral = romans[interval.simpleDegree - 1]
        var suffix = chord.symbol
        let pcs = Set(chord.intervals.map(\.pitchClass))
        if pcs.contains(3) && !pcs.contains(4) {
            numeral = numeral.lowercased()
            switch chord.symbol {
            case "m": suffix = ""
            case "m(maj7)": suffix = "maj7"
            case "m(maj9)": suffix = "maj9"
            case "m(add9)": suffix = "add9"
            default:
                if suffix.hasPrefix("m") { suffix.removeFirst() }
            }
        }
        return prefix + numeral + suffix.replacingOccurrences(of: "♭", with: "b").replacingOccurrences(of: "♯", with: "#")
    }
}
