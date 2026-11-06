import Foundation

@inline(__always) func mod12(_ x: Int) -> Int { ((x % 12) + 12) % 12 }

// MARK: - Letters & note names

enum Letter: Int, CaseIterable {
    case C = 0, D, E, F, G, A, B

    var semitones: Int { [0, 2, 4, 5, 7, 9, 11][rawValue] }
    var symbol: String { ["C", "D", "E", "F", "G", "A", "B"][rawValue] }
}

struct NoteName: Hashable {
    var letter: Letter
    var accidental: Int

    var pitchClass: Int { mod12(letter.semitones + accidental) }
    var text: String { letter.symbol + NoteName.accidentalText(accidental) }

    static func accidentalText(_ a: Int) -> String {
        if a < 0 { return String(repeating: "♭", count: -a) }
        if a > 0 { return String(repeating: "♯", count: a) }
        return ""
    }

    /// Plain spelling of a pitch class using either sharps or flats.
    static func from(pitchClass: Int, preferFlats: Bool) -> NoteName {
        let pc = mod12(pitchClass)
        if let natural = Letter.allCases.first(where: { $0.semitones == pc }) {
            return NoteName(letter: natural, accidental: 0)
        }
        if preferFlats {
            let l = Letter.allCases.first(where: { $0.semitones == mod12(pc + 1) })!
            return NoteName(letter: l, accidental: -1)
        }
        let l = Letter.allCases.first(where: { $0.semitones == mod12(pc - 1) })!
        return NoteName(letter: l, accidental: 1)
    }

    /// Theory-correct spelling: the interval's degree decides the letter.
    func adding(_ interval: Interval) -> NoteName {
        let l = Letter(rawValue: (letter.rawValue + interval.degree - 1) % 7)!
        let target = mod12(pitchClass + interval.semitones)
        var acc = mod12(target - l.semitones)
        if acc > 6 { acc -= 12 }
        if abs(acc) > 2 {
            return NoteName.from(pitchClass: target, preferFlats: accidental < 0)
        }
        return NoteName(letter: l, accidental: acc)
    }
}

// MARK: - Intervals

struct Interval: Hashable {
    let degree: Int        // 1...13
    let accidental: Int    // -2...+2

    init(degree: Int, accidental: Int) {
        self.degree = degree
        self.accidental = accidental
    }

    /// Parses "1", "b3", "#11", "bb7", "♭9" …
    init(_ text: String) {
        var acc = 0
        var digits = ""
        for ch in text {
            switch ch {
            case "b", "♭": acc -= 1
            case "#", "♯": acc += 1
            default: digits.append(ch)
            }
        }
        self.degree = Int(digits) ?? 1
        self.accidental = acc
    }

    static func naturalSemitones(_ degree: Int) -> Int {
        let i = max(degree - 1, 0)
        return [0, 2, 4, 5, 7, 9, 11][i % 7] + 12 * (i / 7)
    }

    var semitones: Int { Interval.naturalSemitones(degree) + accidental }
    var pitchClass: Int { mod12(semitones) }
    var simpleDegree: Int { (degree - 1) % 7 + 1 }

    var label: String {
        if degree == 1 && accidental == 0 { return "R" }
        return NoteName.accidentalText(accidental) + "\(degree)"
    }
}
