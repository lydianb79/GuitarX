import Foundation

// MARK: - Scales

struct ScaleType: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let intervals: [Interval]

    var isHeptatonic: Bool { intervals.map(\.degree) == [1, 2, 3, 4, 5, 6, 7] }
    var formula: String { intervals.map(\.label).joined(separator: "  ") }
}

enum ScaleLibrary {
    static let all: [ScaleType] = build()
    static let byID: [String: ScaleType] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    static let categories: [String] = {
        var seen: [String] = []
        for s in all where !seen.contains(s.category) { seen.append(s.category) }
        return seen
    }()

    private static func heptatonic(_ semis: [Int]) -> [Interval] {
        semis.enumerated().map { i, s in
            Interval(degree: i + 1, accidental: s - Interval.naturalSemitones(i + 1))
        }
    }

    private static func modes(_ category: String, _ parent: [Int], _ names: [String]) -> [ScaleType] {
        names.enumerated().map { i, name in
            let rotated = (0..<7).map { mod12(parent[(i + $0) % 7] - parent[i]) }
            return ScaleType(id: "\(category)/\(name)", name: name, category: category, intervals: heptatonic(rotated))
        }
    }

    private static func hept(_ category: String, _ name: String, _ semis: [Int]) -> ScaleType {
        ScaleType(id: "\(category)/\(name)", name: name, category: category, intervals: heptatonic(semis))
    }

    private static func f(_ category: String, _ name: String, _ formula: String) -> ScaleType {
        ScaleType(id: "\(category)/\(name)", name: name, category: category,
                  intervals: formula.split(separator: " ").map { Interval(String($0)) })
    }

    private static func build() -> [ScaleType] {
        var s: [ScaleType] = []
        s += modes("Major Modes", [0, 2, 4, 5, 7, 9, 11],
                   ["Ionian (Major)", "Dorian", "Phrygian", "Lydian", "Mixolydian", "Aeolian (Natural Minor)", "Locrian"])
        s += modes("Melodic Minor Modes", [0, 2, 3, 5, 7, 9, 11],
                   ["Melodic Minor", "Dorian ♭2", "Lydian Augmented", "Lydian Dominant", "Mixolydian ♭6", "Locrian ♮2", "Altered (Super Locrian)"])
        s += modes("Harmonic Minor Modes", [0, 2, 3, 5, 7, 8, 11],
                   ["Harmonic Minor", "Locrian ♮6", "Ionian ♯5", "Dorian ♯4", "Phrygian Dominant", "Lydian ♯2", "Altered ♭♭7"])
        s += modes("Harmonic Major Modes", [0, 2, 4, 5, 7, 8, 11],
                   ["Harmonic Major", "Dorian ♭5", "Phrygian ♭4", "Lydian ♭3", "Mixolydian ♭2", "Lydian Augmented ♯2", "Locrian ♭♭7"])
        s += modes("Double Harmonic Modes", [0, 1, 4, 5, 7, 8, 11],
                   ["Double Harmonic Major", "Lydian ♯2 ♯6", "Ultraphrygian", "Hungarian Minor", "Oriental", "Ionian ♯2 ♯5", "Locrian ♭♭3 ♭♭7"])

        let pent = "Pentatonic & Blues"
        s += [
            f(pent, "Major Pentatonic", "1 2 3 5 6"),
            f(pent, "Minor Pentatonic", "1 b3 4 5 b7"),
            f(pent, "Minor Blues", "1 b3 4 b5 5 b7"),
            f(pent, "Major Blues", "1 2 b3 3 5 6"),
            f(pent, "Suspended (Egyptian)", "1 2 4 5 b7"),
            f(pent, "Dominant Pentatonic", "1 2 3 5 b7"),
            f(pent, "Hirajoshi", "1 2 b3 5 b6"),
            f(pent, "Kumoi", "1 2 b3 5 6"),
            f(pent, "In Sen", "1 b2 4 5 b7"),
            f(pent, "Iwato", "1 b2 4 b5 b7"),
        ]

        let bebop = "Bebop"
        s += [
            f(bebop, "Bebop Dominant", "1 2 3 4 5 6 b7 7"),
            f(bebop, "Bebop Major", "1 2 3 4 5 #5 6 7"),
            f(bebop, "Bebop Dorian", "1 2 b3 3 4 5 6 b7"),
            f(bebop, "Bebop Melodic Minor", "1 2 b3 4 5 #5 6 7"),
        ]

        let sym = "Symmetric"
        s += [
            f(sym, "Whole Tone", "1 2 3 #4 #5 b7"),
            f(sym, "Diminished (Half-Whole)", "1 b2 #2 3 #4 5 6 b7"),
            f(sym, "Diminished (Whole-Half)", "1 2 b3 4 b5 #5 6 7"),
            f(sym, "Augmented", "1 #2 3 5 #5 7"),
            f(sym, "Chromatic", "1 b2 2 b3 3 4 #4 5 b6 6 b7 7"),
        ]

        let ex = "Exotic"
        s += [
            hept(ex, "Neapolitan Major", [0, 1, 3, 5, 7, 9, 11]),
            hept(ex, "Neapolitan Minor", [0, 1, 3, 5, 7, 8, 11]),
            hept(ex, "Hungarian Major", [0, 3, 4, 6, 7, 9, 10]),
            hept(ex, "Enigmatic", [0, 1, 4, 6, 8, 10, 11]),
            hept(ex, "Persian", [0, 1, 4, 5, 6, 8, 11]),
            f(ex, "Prometheus", "1 2 3 #4 6 b7"),
            f(ex, "Spanish 8-Tone", "1 b2 #2 3 4 b5 b6 b7"),
        ]
        return s
    }
}

// MARK: - Chords

struct ChordType: Identifiable, Hashable {
    let id: String
    let symbol: String
    let name: String
    let category: String
    let intervals: [Interval]
    /// Pitch classes (relative to root) that may be omitted in voicings.
    let optional: Set<Int>

    var formula: String { intervals.map(\.label).joined(separator: "  ") }
}

enum ChordLibrary {
    static let all: [ChordType] = build()
    static let byID: [String: ChordType] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    static let categories: [String] = {
        var seen: [String] = []
        for c in all where !seen.contains(c.category) { seen.append(c.category) }
        return seen
    }()

    static func match(pcs: [Int]) -> ChordType? {
        let set = Set(pcs)
        return all.first { $0.intervals.count == pcs.count && Set($0.intervals.map(\.pitchClass)) == set }
    }

    private static func c(_ cat: String, _ symbol: String, _ name: String, _ formula: String, opt: String = "") -> ChordType {
        let ivs = formula.split(separator: " ").map { Interval(String($0)) }
        let optional = Set(opt.split(separator: " ").map { Interval(String($0)).pitchClass })
        return ChordType(id: "\(cat)/\(name)", symbol: symbol, name: name, category: cat, intervals: ivs, optional: optional)
    }

    private static func build() -> [ChordType] {
        let tri = "Triads", six = "Sixths", sev = "Sevenths", add = "Added Tones"
        let nin = "Ninths", ele = "Elevenths", thi = "Thirteenths", alt = "Altered Dominants"
        return [
            c(tri, "", "Major", "1 3 5"),
            c(tri, "m", "Minor", "1 b3 5"),
            c(tri, "°", "Diminished", "1 b3 b5"),
            c(tri, "+", "Augmented", "1 3 #5"),
            c(tri, "sus2", "Suspended 2nd", "1 2 5"),
            c(tri, "sus4", "Suspended 4th", "1 4 5"),
            c(tri, "5", "Power Chord", "1 5"),
            c(tri, "(♭5)", "Major ♭5", "1 3 b5"),

            c(six, "6", "Major 6th", "1 3 5 6"),
            c(six, "m6", "Minor 6th", "1 b3 5 6"),
            c(six, "6/9", "Six-Nine", "1 3 5 6 9", opt: "5"),
            c(six, "m6/9", "Minor Six-Nine", "1 b3 5 6 9", opt: "5"),

            c(sev, "maj7", "Major 7th", "1 3 5 7", opt: "5"),
            c(sev, "7", "Dominant 7th", "1 3 5 b7", opt: "5"),
            c(sev, "m7", "Minor 7th", "1 b3 5 b7", opt: "5"),
            c(sev, "m(maj7)", "Minor-Major 7th", "1 b3 5 7", opt: "5"),
            c(sev, "ø7", "Half-Diminished (m7♭5)", "1 b3 b5 b7"),
            c(sev, "°7", "Diminished 7th", "1 b3 b5 bb7"),
            c(sev, "+7", "Augmented 7th", "1 3 #5 b7"),
            c(sev, "+maj7", "Augmented Major 7th", "1 3 #5 7"),
            c(sev, "7sus4", "Dominant 7th sus4", "1 4 5 b7", opt: "5"),
            c(sev, "7sus2", "Dominant 7th sus2", "1 2 5 b7", opt: "5"),
            c(sev, "7♭5", "Dominant 7th ♭5", "1 3 b5 b7"),
            c(sev, "maj7♭5", "Major 7th ♭5", "1 3 b5 7"),

            c(add, "add9", "Add 9", "1 3 5 9"),
            c(add, "m(add9)", "Minor Add 9", "1 b3 5 9"),
            c(add, "add11", "Add 11", "1 3 5 11"),
            c(add, "add♯11", "Add ♯11", "1 3 5 #11"),

            c(nin, "maj9", "Major 9th", "1 3 5 7 9", opt: "5"),
            c(nin, "9", "Dominant 9th", "1 3 5 b7 9", opt: "5"),
            c(nin, "m9", "Minor 9th", "1 b3 5 b7 9", opt: "5"),
            c(nin, "m(maj9)", "Minor-Major 9th", "1 b3 5 7 9", opt: "5"),
            c(nin, "9sus4", "Dominant 9th sus4", "1 4 5 b7 9", opt: "5"),
            c(nin, "ø9", "Half-Diminished 9th", "1 b3 b5 b7 9"),
            c(nin, "+9", "Augmented 9th", "1 3 #5 b7 9"),

            c(ele, "11", "Dominant 11th", "1 3 5 b7 9 11", opt: "3 5 9"),
            c(ele, "m11", "Minor 11th", "1 b3 5 b7 9 11", opt: "5 9"),
            c(ele, "maj7♯11", "Major 7th ♯11", "1 3 5 7 #11", opt: "5"),
            c(ele, "maj9♯11", "Major 9th ♯11", "1 3 5 7 9 #11", opt: "5 9"),
            c(ele, "7♯11", "Dominant 7th ♯11", "1 3 5 b7 #11", opt: "5"),
            c(ele, "9♯11", "Dominant 9th ♯11", "1 3 5 b7 9 #11", opt: "5 9"),

            c(thi, "13", "Dominant 13th", "1 3 5 b7 9 13", opt: "5 9"),
            c(thi, "maj13", "Major 13th", "1 3 5 7 9 13", opt: "5 9"),
            c(thi, "m13", "Minor 13th", "1 b3 5 b7 9 11 13", opt: "5 9 11"),
            c(thi, "13♭9", "Dominant 13th ♭9", "1 3 5 b7 b9 13", opt: "5"),
            c(thi, "13♯11", "Dominant 13th ♯11", "1 3 5 b7 9 #11 13", opt: "5 9"),

            c(alt, "7♭9", "Dominant 7th ♭9", "1 3 5 b7 b9", opt: "5"),
            c(alt, "7♯9", "Dominant 7th ♯9", "1 3 5 b7 #9", opt: "5"),
            c(alt, "7♯5", "Dominant 7th ♯5", "1 3 #5 b7"),
            c(alt, "7♯5♯9", "Dominant 7th ♯5♯9", "1 3 #5 b7 #9"),
            c(alt, "7♭5♭9", "Dominant 7th ♭5♭9", "1 3 b5 b7 b9"),
            c(alt, "7♭9♭13", "Dominant 7th ♭9♭13", "1 3 5 b7 b9 b13", opt: "5"),
            c(alt, "7alt", "Altered Dominant", "1 3 b7 b9 #9 b13", opt: "#9 b13"),
        ]
    }
}

// MARK: - Tunings

struct Tuning: Identifiable, Hashable {
    let id: String
    let notes: [Int]          // MIDI notes, physical lowest (bottom) string first
    let prefersFlats: Bool

    var name: String { id }
}

enum TuningLibrary {
    static let all: [Tuning] = [
        Tuning(id: "Standard (E A D G B E)", notes: [40, 45, 50, 55, 59, 64], prefersFlats: false),
        Tuning(id: "Drop D", notes: [38, 45, 50, 55, 59, 64], prefersFlats: false),
        Tuning(id: "E♭ Standard", notes: [39, 44, 49, 54, 58, 63], prefersFlats: true),
        Tuning(id: "D Standard", notes: [38, 43, 48, 53, 57, 62], prefersFlats: false),
        Tuning(id: "Drop C", notes: [36, 43, 48, 53, 57, 62], prefersFlats: false),
        Tuning(id: "DADGAD", notes: [38, 45, 50, 55, 57, 62], prefersFlats: false),
        Tuning(id: "Open G", notes: [38, 43, 50, 55, 59, 62], prefersFlats: false),
        Tuning(id: "Open D", notes: [38, 45, 50, 54, 57, 62], prefersFlats: false),
        Tuning(id: "Open E", notes: [40, 47, 52, 56, 59, 64], prefersFlats: false),
        Tuning(id: "Open C", notes: [36, 43, 48, 55, 60, 64], prefersFlats: false),
        Tuning(id: "All Fourths", notes: [40, 45, 50, 55, 60, 65], prefersFlats: true),
        Tuning(id: "7-String (B)", notes: [35, 40, 45, 50, 55, 59, 64], prefersFlats: false),
        Tuning(id: "8-String (F♯)", notes: [30, 35, 40, 45, 50, 55, 59, 64], prefersFlats: false),
        Tuning(id: "Bass 4-String", notes: [28, 33, 38, 43], prefersFlats: false),
        Tuning(id: "Bass 5-String", notes: [23, 28, 33, 38, 43], prefersFlats: false),
        Tuning(id: "Ukulele (G C E A)", notes: [67, 60, 64, 69], prefersFlats: false),
    ]
}
