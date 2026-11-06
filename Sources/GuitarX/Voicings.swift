import Foundation

struct FretPos: Hashable {
    var string: Int   // 0 = physically lowest string (drawn at the bottom)
    var fret: Int     // 0 = open
}

struct Voicing: Hashable {
    let frets: [Int?]   // per string, lowest string first; nil = muted

    var minFret: Int { frets.compactMap { $0 }.filter { $0 > 0 }.min() ?? 0 }
    var maxFret: Int { frets.compactMap { $0 }.max() ?? 0 }

    /// Classic chord-box shorthand, low string first: "x32010".
    var shorthand: String {
        frets.map { f -> String in
            guard let f else { return "x" }
            return f >= 10 ? "(\(f))" : "\(f)"
        }.joined()
    }

    func bassPosition(tuning: [Int]) -> FretPos? {
        var best: (midi: Int, pos: FretPos)? = nil
        for (s, fret) in frets.enumerated() {
            guard let fret, s < tuning.count else { continue }
            let m = tuning[s] + fret
            if best == nil || m < best!.midi { best = (m, FretPos(string: s, fret: fret)) }
        }
        return best?.pos
    }
}

/// Finds playable voicings of a chord in a given inversion (= the lowest sounding note).
enum VoicingGenerator {
    static func generate(tuning: [Int], rootPC: Int, chord: ChordType, inversion: Int,
                         strings: Int, fretCount: Int, limit: Int = 400) -> [Voicing] {
        let n = tuning.count
        guard n >= 2, !chord.intervals.isEmpty else { return [] }

        let chordPCs = Set(chord.intervals.map { mod12(rootPC + $0.semitones) })
        let required = Set(chord.intervals
            .filter { !chord.optional.contains($0.pitchClass) }
            .map { mod12(rootPC + $0.semitones) })
        let inv = min(max(inversion, 0), chord.intervals.count - 1)
        let bassPC = mod12(rootPC + chord.intervals[inv].semitones)

        let minStrings: Int
        let maxStrings: Int
        if strings > 0 {
            minStrings = strings
            maxStrings = strings
        } else {
            let base = chord.intervals.count <= 2 ? 2 : max(4, required.count)
            minStrings = min(n, base)
            maxStrings = min(n, 6)
        }
        guard required.count <= maxStrings, minStrings <= n else { return [] }

        var seen = Set<[Int]>()
        var results: [Voicing] = []
        var current = [Int](repeating: -1, count: n)

        let maxStart = max(0, fretCount - 3)
        for w in 0...maxStart {
            let lo = max(1, w)
            let hi = min(fretCount, w + 3)
            let allowOpen = w <= 3

            var options: [[Int]] = []
            for s in 0..<n {
                var o: [Int] = [-1]
                if allowOpen && chordPCs.contains(mod12(tuning[s])) { o.append(0) }
                if lo <= hi {
                    for f in lo...hi where chordPCs.contains(mod12(tuning[s] + f)) { o.append(f) }
                }
                options.append(o)
            }

            func validate() {
                var pcs = Set<Int>()
                var midis = Set<Int>()
                var lowestMidi = Int.max
                var lowestPC = -1
                var fretted: [Int] = []
                var count = 0
                var first = -1, last = -1
                for s in 0..<n where current[s] >= 0 {
                    let m = tuning[s] + current[s]
                    if midis.contains(m) { return }          // no identical unisons
                    midis.insert(m)
                    pcs.insert(mod12(m))
                    if m < lowestMidi { lowestMidi = m; lowestPC = mod12(m) }
                    if current[s] > 0 { fretted.append(current[s]) }
                    if first < 0 { first = s }
                    last = s
                    count += 1
                }
                guard lowestPC == bassPC, required.isSubset(of: pcs) else { return }
                // Skipped (muted) inner strings only for 4+ note grips.
                if (last - first + 1) - count > 0 && count < 4 { return }
                if let mn = fretted.min(), let mx = fretted.max() {
                    if mx - mn > 3 { return }
                    let atMin = fretted.filter { $0 == mn }.count
                    let fingers = fretted.count - atMin + (atMin > 0 ? 1 : 0)
                    if fingers > 4 { return }
                }
                if seen.insert(current).inserted {
                    results.append(Voicing(frets: current.map { $0 >= 0 ? $0 : nil }))
                }
            }

            func recurse(_ s: Int, played: Int, started: Bool, pendingMuted: Int, skips: Int) {
                if s == n {
                    if played >= minStrings && played <= maxStrings { validate() }
                    return
                }
                // Not enough strings left to reach the minimum.
                if played + (n - s) < minStrings { return }
                for f in options[s] {
                    if f < 0 {
                        current[s] = -1
                        recurse(s + 1, played: played, started: started,
                                pendingMuted: started ? pendingMuted + 1 : 0, skips: skips)
                    } else {
                        if played + 1 > maxStrings { continue }
                        let newSkips = skips + (started ? pendingMuted : 0)
                        if newSkips > 1 { continue }
                        current[s] = f
                        recurse(s + 1, played: played + 1, started: true, pendingMuted: 0, skips: newSkips)
                    }
                }
                current[s] = -1
            }

            recurse(0, played: 0, started: false, pendingMuted: 0, skips: 0)
        }

        results.sort { a, b in
            if a.minFret != b.minFret { return a.minFret < b.minFret }
            let ca = a.frets.compactMap { $0 }.count, cb = b.frets.compactMap { $0 }.count
            if ca != cb { return ca > cb }
            let la = a.frets.firstIndex(where: { $0 != nil }) ?? 0
            let lb = b.frets.firstIndex(where: { $0 != nil }) ?? 0
            return la < lb
        }
        return Array(results.prefix(limit))
    }
}
