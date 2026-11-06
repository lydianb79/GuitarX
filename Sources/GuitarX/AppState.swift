import SwiftUI
import Combine
import QuartzCore

enum ViewMode: String, CaseIterable, Identifiable {
    case scale = "Scale", chord = "Chord", progression = "Progression"
    var id: String { rawValue }
}

enum LabelMode: String, CaseIterable, Identifiable {
    case notes = "Notes", intervals = "Intervals", degrees = "Degrees", none = "None"
    var id: String { rawValue }
}

enum Spelling: String, CaseIterable, Identifiable {
    case auto = "Auto", sharps = "♯", flats = "♭"
    var id: String { rawValue }
}

enum ChordDisplay: String, CaseIterable, Identifiable {
    case voicings = "Voicings", allTones = "All Tones", caged = "CAGED"
    var id: String { rawValue }
}

enum PositionSystem: String, CaseIterable, Identifiable {
    case boxes = "Boxes", caged = "CAGED"
    var id: String { rawValue }
}

enum ProgressionDisplay: String, CaseIterable, Identifiable {
    case voicings = "Voicings", allTones = "All Tones"
    var id: String { rawValue }
}

enum WoodStyle: String, CaseIterable, Identifiable {
    case rosewood = "Rosewood", ebony = "Ebony", maple = "Maple"
    var id: String { rawValue }
}

enum MarkerRole { case active, bass, accent, ghost, chromatic }

struct Marker {
    let pos: FretPos
    let label: String
    let degree: Int      // 1...7, 0 = chromatic
    let isRoot: Bool
    let role: MarkerRole
    let midi: Int
}

struct HarmonyChord: Identifiable {
    let id: Int
    let numeral: String
    let interval: Interval
    let root: NoteName
    let chord: ChordType?
    var name: String { root.text + (chord?.symbol ?? " ?") }
    var token: String? { chord.map { ProgressionParser.token(interval: interval, chord: $0) } }
}

struct NoteEvent {
    let pos: FretPos?
    let midi: Int
    let time: Double
}

/// Everything the fretboard needs to know about what is currently shown.
struct DisplayContext {
    var rootPC: Int
    var rootName: NoteName
    var intervals: [Interval]
    var isScale: Bool
    var voicing: Voicing? = nil
    var useVoicing = false
    var window: ClosedRange<Int>? = nil
    var accent: Set<FretPos> = []
    var bassRel: Int? = nil
}

final class AppState: ObservableObject {
    // Selection
    @Published var mode: ViewMode = .scale { didSet { hiddenPCs = []; if isPlaying { stopPlayback() } } }
    @Published var rootPC: Int = 0 { didSet { voicingIndex = 0; cagedIndex = 0 } }
    @Published var spelling: Spelling = .auto
    @Published var scaleID: String = ScaleLibrary.all[0].id { didSet { hiddenPCs = []; scalePosition = 0 } }
    @Published var chordID: String = ChordLibrary.all[0].id {
        didSet { hiddenPCs = []; inversion = 0; voicingIndex = 0; cagedIndex = 0 }
    }
    @Published var inversion: Int = 0 { didSet { voicingIndex = 0 } }
    @Published var chordDisplay: ChordDisplay = .voicings
    @Published var voicingStrings: Int = 0 { didSet { voicingIndex = 0 } }
    @Published var voicingIndex: Int = 0
    @Published var cagedIndex: Int = 0
    @Published var scalePosition: Int = 0
    @Published var positionSystem: PositionSystem = .boxes { didSet { scalePosition = 0 } }

    // Progression
    @Published var progressionText: String = "I V vi IV" { didSet { progressionStep = 0; hiddenPCs = [] } }
    @Published var progressionStep: Int = 0
    @Published var progressionDisplay: ProgressionDisplay = .voicings
    @Published var progressionFret: Int = 0
    @Published var allowInversions = true
    @Published var harmonySevenths = false
    @Published var tempo: Double = 96
    @Published var beatsPerChord: Int = 4
    @Published var loopProgression = false
    @Published var isPlaying = false

    // Instrument
    @Published var tuningID: String = TuningLibrary.all[0].id {
        didSet {
            voicingIndex = 0
            cagedIndex = 0
            scalePosition = 0
            if voicingStrings > tuning.notes.count { voicingStrings = 0 }
        }
    }
    @Published var fretCount: Int = 22 { didSet { voicingIndex = 0 } }
    @Published var wood: WoodStyle = .rosewood

    // Display
    @Published var labelMode: LabelMode = .notes
    @Published var colorByInterval = true
    @Published var showGhostNotes = true
    @Published var showChromatic = false
    @Published var leftHanded = false
    @Published var hiddenPCs: Set<Int> = []
    @Published var hover: FretPos? = nil

    /// Fret position → time a "played" pulse starts (read by the renderer).
    var pulses: [FretPos: Double] = [:]

    private var voicingKey = ""
    private var voicingCache: [Voicing] = []
    private var progressionKey = ""
    private var progressionCache: (chords: [ProgressionChord], invalid: [String]) = ([], [])
    private var progVoicingKey = ""
    private var progVoicingCache: [Voicing?] = []
    private var playbackToken = 0
    private lazy var synth = GuitarSynth()

    // MARK: - Basic derived values

    var scale: ScaleType { ScaleLibrary.byID[scaleID] ?? ScaleLibrary.all[0] }
    var chord: ChordType { ChordLibrary.byID[chordID] ?? ChordLibrary.all[0] }
    var tuning: Tuning { TuningLibrary.all.first { $0.id == tuningID } ?? TuningLibrary.all[0] }

    func keyName(_ pc: Int) -> NoteName {
        switch spelling {
        case .sharps: return NoteName.from(pitchClass: pc, preferFlats: false)
        case .flats: return NoteName.from(pitchClass: pc, preferFlats: true)
        case .auto: return NoteName.from(pitchClass: pc, preferFlats: [1, 3, 8, 10].contains(mod12(pc)))
        }
    }

    /// The key / selected root.
    var rootName: NoteName { keyName(rootPC) }

    /// Root of what is shown right now (the current chord in progression mode).
    var activeRootName: NoteName {
        if mode == .progression, let s = currentStep { return s.root }
        return rootName
    }
    var activeRootPC: Int { activeRootName.pitchClass }

    var currentIntervals: [Interval] {
        switch mode {
        case .scale: return scale.intervals
        case .chord: return chord.intervals
        case .progression: return currentStep?.chord.intervals ?? []
        }
    }

    var spelledNotes: [NoteName] { currentIntervals.map { activeRootName.adding($0) } }
    var bassInterval: Interval { chord.intervals[min(inversion, chord.intervals.count - 1)] }

    func inversionName(_ i: Int) -> String {
        if i == 0 { return "Root Position" }
        let ord = ["1st", "2nd", "3rd", "4th", "5th", "6th"]
        return "\(ord[min(i - 1, ord.count - 1)]) Inversion"
    }

    // MARK: - Titles

    var title: String {
        switch mode {
        case .scale:
            var t = "\(rootName.text) \(scale.name)"
            if positionSystem == .caged, let s = selectedScaleShape { t += "  ·  \(s.shape.rawValue) shape" }
            return t
        case .chord:
            let base = "\(rootName.text)\(chord.symbol)"
            if chordDisplay == .caged {
                if let s = currentChordShape { return "\(base)  ·  \(s.shape.rawValue) shape" }
                return base
            }
            return inversion > 0 ? "\(base) / \(rootName.adding(bassInterval).text)" : base
        case .progression:
            guard let s = currentStep else { return "Progression in \(rootName.text)" }
            return "\(displayToken(s.token))   \(s.name)\(progressionSlash(s))"
        }
    }

    var subtitle: String {
        switch mode {
        case .scale:
            return "\(scale.category)   ·   \(scale.formula)"
        case .chord:
            if chordDisplay == .caged {
                return "\(chord.name)   ·   CAGED system   ·   \(chord.formula)"
            }
            return "\(chord.name)   ·   \(inversionName(inversion))   ·   \(chord.formula)"
        case .progression:
            let steps = progression
            guard let s = currentStep else { return "Type Roman numerals in the sidebar, e.g. ii7 V7 Imaj7" }
            return "Key of \(rootName.text)   ·   chord \(s.id + 1) of \(steps.count)   ·   \(s.chord.name)"
        }
    }

    /// Pretty-prints accidentals in Roman numerals: bVII → ♭VII.
    func displayToken(_ t: String) -> String {
        var out = ""
        var leading = true
        for ch in t {
            if leading && ch == "b" { out.append("♭"); continue }
            if leading && ch == "#" { out.append("♯"); continue }
            leading = false
            out.append(ch)
        }
        return out
    }

    private func progressionSlash(_ s: ProgressionChord) -> String {
        guard progressionDisplay == .voicings, s.id < progressionVoicings.count,
              let v = progressionVoicings[s.id], let bass = v.bassPosition(tuning: tuning.notes) else { return "" }
        let rel = mod12(tuning.notes[bass.string] + bass.fret - s.rootPC)
        guard rel != 0, let iv = s.chord.intervals.first(where: { $0.pitchClass == rel }) else { return "" }
        return "/\(s.root.adding(iv).text)"
    }

    // MARK: - Scale positions

    var scalePositions: [ClosedRange<Int>] {
        let open = tuning.notes[0]
        let starts = Set(scale.intervals.map { mod12(rootPC + $0.semitones - open) }).sorted()
        return starts.map { $0...min($0 + 4, fretCount) }
    }

    var scaleCAGEDShapes: [PlacedShape] {
        let pcs = Set(scale.intervals.map(\.pitchClass))
        let q = CAGED.frameQuality(minorThird: pcs.contains(3) && !pcs.contains(4))
        return CAGED.place(tuning: tuning.notes, rootPC: rootPC, quality: q, fretCount: fretCount)
    }

    var selectedScaleShape: PlacedShape? {
        guard mode == .scale, positionSystem == .caged, scalePosition > 0 else { return nil }
        let shapes = scaleCAGEDShapes
        return scalePosition <= shapes.count ? shapes[scalePosition - 1] : nil
    }

    // MARK: - Chord voicings & CAGED

    var voicings: [Voicing] {
        let key = "\(tuningID)|\(rootPC)|\(chordID)|\(inversion)|\(voicingStrings)|\(fretCount)"
        if key != voicingKey {
            voicingKey = key
            voicingCache = VoicingGenerator.generate(tuning: tuning.notes, rootPC: rootPC, chord: chord,
                                                     inversion: inversion, strings: voicingStrings,
                                                     fretCount: fretCount)
        }
        return voicingCache
    }

    var currentVoicing: Voicing? {
        let v = voicings
        guard !v.isEmpty else { return nil }
        return v[min(max(voicingIndex, 0), v.count - 1)]
    }

    var chordHasExactCAGED: Bool { CAGED.quality(of: chord) != nil }

    var chordCAGEDShapes: [PlacedShape] {
        let pcs = Set(chord.intervals.map(\.pitchClass))
        let q = CAGED.quality(of: chord) ?? CAGED.frameQuality(minorThird: pcs.contains(3) && !pcs.contains(4))
        return CAGED.place(tuning: tuning.notes, rootPC: rootPC, quality: q, fretCount: fretCount)
    }

    var currentChordShape: PlacedShape? {
        let s = chordCAGEDShapes
        guard !s.isEmpty else { return nil }
        return s[min(max(cagedIndex, 0), s.count - 1)]
    }

    // MARK: - Progression

    var parsedProgression: (chords: [ProgressionChord], invalid: [String]) {
        let key = "\(progressionText)|\(rootPC)|\(spelling.rawValue)"
        if key != progressionKey {
            progressionKey = key
            progressionCache = ProgressionParser.parse(progressionText, key: rootName)
        }
        return progressionCache
    }

    var progression: [ProgressionChord] { parsedProgression.chords }

    var currentStep: ProgressionChord? {
        let p = progression
        guard !p.isEmpty else { return nil }
        return p[min(max(progressionStep, 0), p.count - 1)]
    }

    /// One voicing per progression chord, chosen for smooth voice leading near `progressionFret`.
    var progressionVoicings: [Voicing?] {
        let key = "\(progressionKey)|\(progressionText)|\(rootPC)|\(tuningID)|\(fretCount)|\(voicingStrings)|\(progressionFret)|\(allowInversions)"
        if key != progVoicingKey {
            progVoicingKey = key
            progVoicingCache = computeProgressionVoicings(progression)
        }
        return progVoicingCache
    }

    private func computeProgressionVoicings(_ steps: [ProgressionChord]) -> [Voicing?] {
        let notes = tuning.notes
        var cache: [String: [Voicing]] = [:]
        var result: [Voicing?] = []
        var prevCenter: Double? = nil
        let anchor = Double(progressionFret) + 1.5

        func center(_ v: Voicing) -> Double {
            let fretted = v.frets.compactMap { $0 }.filter { $0 > 0 }
            guard !fretted.isEmpty else { return 0.5 }
            return Double(fretted.reduce(0, +)) / Double(fretted.count)
        }

        for step in steps {
            let key = "\(step.rootPC)|\(step.chord.id)"
            let options: [Voicing]
            if let cached = cache[key] {
                options = cached
            } else {
                let invs = allowInversions ? Array(0..<step.chord.intervals.count) : [0]
                var all: [Voicing] = []
                for inv in invs {
                    all += VoicingGenerator.generate(tuning: notes, rootPC: step.rootPC, chord: step.chord,
                                                     inversion: inv, strings: voicingStrings,
                                                     fretCount: fretCount, limit: 300)
                }
                cache[key] = all
                options = all
            }

            var best: Voicing? = nil
            var bestCost = Double.infinity
            for v in options {
                let c = center(v)
                var cost = abs(c - anchor) * 0.6
                if let p = prevCenter { cost += abs(c - p) }
                cost -= 0.25 * Double(v.frets.compactMap { $0 }.count)
                if v.maxFret - v.minFret > 3 && v.minFret > 0 { cost += 0.5 }
                if let b = v.bassPosition(tuning: notes), mod12(notes[b.string] + b.fret) != step.rootPC {
                    cost += 0.9
                }
                if cost < bestCost { bestCost = cost; best = v }
            }
            result.append(best)
            if let b = best { prevCenter = center(b) }
        }
        return result
    }

    // MARK: - Harmonisation

    func harmonize(sevenths: Bool) -> [HarmonyChord] {
        guard scale.isHeptatonic else { return [] }
        let ivs = scale.intervals
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        return (0..<7).map { i in
            let base = ivs[i]
            let tones = (sevenths ? [0, 2, 4, 6] : [0, 2, 4]).map { ivs[(i + $0) % 7] }
            let rels = tones.map { mod12($0.semitones - base.semitones) }
            var chord = ChordLibrary.match(pcs: rels)
            if chord == nil && sevenths { chord = ChordLibrary.match(pcs: Array(rels.prefix(3))) }
            let acc = NoteName.accidentalText(base.accidental)
            let numeral = acc + (rels[1] == 4 ? numerals[i] : numerals[i].lowercased())
            return HarmonyChord(id: i, numeral: numeral, interval: base, root: rootName.adding(base), chord: chord)
        }
    }

    var harmonized: [HarmonyChord] { mode == .scale ? harmonize(sevenths: true) : [] }

    // MARK: - Display context & fretboard model

    var displayContext: DisplayContext {
        switch mode {
        case .scale:
            var ctx = DisplayContext(rootPC: rootPC, rootName: rootName, intervals: scale.intervals, isScale: true)
            if scalePosition > 0 {
                switch positionSystem {
                case .boxes:
                    let p = scalePositions
                    if scalePosition <= p.count { ctx.window = p[scalePosition - 1] }
                case .caged:
                    if let s = selectedScaleShape {
                        ctx.window = max(0, s.minFret - 1)...min(fretCount, s.maxFret + 1)
                        ctx.accent = Set(s.positions)
                    }
                }
            }
            return ctx

        case .chord:
            var ctx = DisplayContext(rootPC: rootPC, rootName: rootName, intervals: chord.intervals, isScale: false)
            switch chordDisplay {
            case .voicings:
                ctx.useVoicing = true
                ctx.voicing = currentVoicing
            case .allTones:
                if inversion > 0 { ctx.bassRel = bassInterval.pitchClass }
            case .caged:
                if let s = currentChordShape {
                    if chordHasExactCAGED {
                        ctx.useVoicing = true
                        ctx.voicing = s.voicing
                    } else {
                        ctx.window = s.minFret...s.maxFret
                    }
                }
            }
            return ctx

        case .progression:
            guard let step = currentStep else {
                return DisplayContext(rootPC: rootPC, rootName: rootName, intervals: [], isScale: false)
            }
            var ctx = DisplayContext(rootPC: step.rootPC, rootName: step.root, intervals: step.chord.intervals, isScale: false)
            if progressionDisplay == .voicings {
                let vs = progressionVoicings
                ctx.useVoicing = true
                ctx.voicing = step.id < vs.count ? vs[step.id] : nil
            }
            return ctx
        }
    }

    /// The grip currently drawn (used for muted-string marks and strumming).
    var displayedVoicing: Voicing? {
        let c = displayContext
        return c.useVoicing ? c.voicing : nil
    }

    func computeMarkers() -> [Marker] {
        let ctx = displayContext
        var lookup: [Int: (index: Int, interval: Interval)] = [:]
        for (i, iv) in ctx.intervals.enumerated() where lookup[iv.pitchClass] == nil {
            lookup[iv.pitchClass] = (i, iv)
        }
        let names = ctx.intervals.map { ctx.rootName.adding($0) }
        let notes = tuning.notes
        let voicingBass = ctx.voicing?.bassPosition(tuning: notes)
        let preferFlats = ctx.rootName.accidental < 0 || spelling == .flats || (spelling == .auto && tuning.prefersFlats)

        var out: [Marker] = []
        for s in 0..<notes.count {
            for f in 0...fretCount {
                let midi = notes[s] + f
                let rel = mod12(midi - ctx.rootPC)
                let pos = FretPos(string: s, fret: f)
                if let hit = lookup[rel], !hiddenPCs.contains(rel) {
                    var role: MarkerRole = .active
                    if ctx.useVoicing {
                        if let v = ctx.voicing, s < v.frets.count, v.frets[s] == f {
                            role = (pos == voicingBass) ? .bass : .active
                        } else {
                            role = .ghost
                        }
                    } else {
                        if let w = ctx.window, !w.contains(f) {
                            role = .ghost
                        } else if ctx.accent.contains(pos) {
                            role = .accent
                        }
                        if role != .ghost, let b = ctx.bassRel, rel == b { role = .bass }
                    }
                    if role == .ghost && !showGhostNotes { continue }

                    let label: String
                    switch labelMode {
                    case .notes: label = names[hit.index].text
                    case .intervals: label = hit.interval.label
                    case .degrees: label = ctx.isScale ? "\(hit.index + 1)" : "\(hit.interval.degree)"
                    case .none: label = ""
                    }
                    out.append(Marker(pos: pos, label: label, degree: hit.interval.simpleDegree,
                                      isRoot: rel == 0, role: role, midi: midi))
                } else if showChromatic {
                    let label = labelMode == .none ? "" : NoteName.from(pitchClass: midi, preferFlats: preferFlats).text
                    out.append(Marker(pos: pos, label: label, degree: 0, isRoot: false, role: .chromatic, midi: midi))
                }
            }
        }
        return out
    }

    func describe(_ pos: FretPos) -> String {
        guard pos.string < tuning.notes.count else { return "" }
        let midi = tuning.notes[pos.string] + pos.fret
        let rel = mod12(midi - activeRootPC)
        let octave = midi / 12 - 1
        let place = "string \(tuning.notes.count - pos.string) · fret \(pos.fret)"
        let ivs = currentIntervals
        if let i = ivs.firstIndex(where: { $0.pitchClass == rel }) {
            return "\(spelledNotes[i].text)\(octave)  ·  \(ivs[i].label)  ·  \(place)"
        }
        let n = NoteName.from(pitchClass: midi, preferFlats: activeRootName.accidental < 0)
        return "\(n.text)\(octave)  ·  \(place)"
    }

    // MARK: - Actions

    func shiftKey(_ d: Int) { rootPC = mod12(rootPC + d) }

    private func wrap(_ x: Int, _ n: Int) -> Int { ((x % n) + n) % n }

    func step(_ d: Int) {
        switch mode {
        case .chord:
            if chordDisplay == .caged {
                let n = chordCAGEDShapes.count
                guard n > 0 else { return }
                cagedIndex = wrap(cagedIndex + d, n)
            } else {
                let n = voicings.count
                guard n > 0 else { return }
                if chordDisplay != .voicings { chordDisplay = .voicings }
                voicingIndex = wrap(voicingIndex + d, n)
            }
        case .scale:
            let count = positionSystem == .boxes ? scalePositions.count : scaleCAGEDShapes.count
            scalePosition = wrap(scalePosition + d, count + 1)
        case .progression:
            let n = progression.count
            guard n > 0 else { return }
            progressionStep = wrap(progressionStep + d, n)
        }
    }

    func nextInversion() {
        guard mode == .chord else { return }
        inversion = (inversion + 1) % chord.intervals.count
    }

    func toggleHidden(_ pc: Int) {
        if hiddenPCs.contains(pc) { hiddenPCs.remove(pc) } else { hiddenPCs.insert(pc) }
    }

    func select(_ h: HarmonyChord) {
        guard let c = h.chord else { return }
        if h.root.accidental > 0 { spelling = .sharps } else if h.root.accidental < 0 { spelling = .flats }
        mode = .chord
        rootPC = h.root.pitchClass
        chordID = c.id
    }

    func appendToProgression(_ token: String) {
        let trimmed = progressionText.trimmingCharacters(in: .whitespacesAndNewlines)
        progressionText = trimmed.isEmpty ? token : trimmed + " " + token
        progressionStep = max(0, progression.count - 1)
    }

    func removeLastFromProgression() {
        var parts = progressionText.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard !parts.isEmpty else { return }
        parts.removeLast()
        progressionText = parts.joined(separator: " ")
    }

    // MARK: - Sound

    func playNote(at pos: FretPos) {
        guard pos.string < tuning.notes.count else { return }
        trigger([NoteEvent(pos: pos, midi: tuning.notes[pos.string] + pos.fret, time: 0)])
    }

    func playSelection() {
        if mode == .progression {
            if isPlaying { stopPlayback() } else { playProgression() }
            return
        }
        var events: [NoteEvent] = []
        if mode == .chord {
            if let v = displayedVoicing {
                for (i, p) in strum(v).enumerated() {
                    events.append(NoteEvent(pos: p.pos, midi: p.midi, time: Double(i) * 0.045))
                }
            } else {
                let inv = chordDisplay == .allTones ? inversion : 0
                for (i, m) in closePosition(rootPC: rootPC, chord: chord, inversion: inv).enumerated() {
                    events.append(NoteEvent(pos: nil, midi: m, time: Double(i) * 0.05))
                }
            }
        } else {
            for (i, n) in scaleRun().enumerated() {
                events.append(NoteEvent(pos: n.pos, midi: n.midi, time: Double(i) * 0.2))
            }
        }
        guard !events.isEmpty else { return }
        trigger(events)
    }

    private func strum(_ v: Voicing) -> [(pos: FretPos, midi: Int)] {
        var played: [(pos: FretPos, midi: Int)] = []
        for (s, f) in v.frets.enumerated() {
            if let f, s < tuning.notes.count { played.append((FretPos(string: s, fret: f), tuning.notes[s] + f)) }
        }
        return played.sorted { $0.midi < $1.midi }
    }

    private func closePosition(rootPC: Int, chord: ChordType, inversion: Int) -> [Int] {
        let count = chord.intervals.count
        let inv = min(inversion, count - 1)
        var prev = 40 + mod12(rootPC + chord.intervals[inv].semitones - 40)
        var out = [prev]
        if count > 1 {
            for k in 1..<count {
                let iv = chord.intervals[(inv + k) % count]
                var m = prev + mod12(rootPC + iv.semitones - prev)
                if m == prev { m += 12 }
                out.append(m)
                prev = m
            }
        }
        return out
    }

    private func scaleRun() -> [(pos: FretPos, midi: Int)] {
        let active = computeMarkers().filter { $0.role == .active || $0.role == .bass || $0.role == .accent }
        guard !active.isEmpty else { return [] }

        if scalePosition > 0 {
            var seen = Set<Int>()
            var up: [(pos: FretPos, midi: Int)] = []
            let sorted = active.sorted { $0.midi != $1.midi ? $0.midi < $1.midi : $0.pos.string > $1.pos.string }
            for m in sorted where !seen.contains(m.midi) {
                seen.insert(m.midi)
                up.append((m.pos, m.midi))
            }
            return up + Array(up.dropLast().reversed())
        }

        guard let lowestRoot = active.filter({ $0.isRoot }).min(by: { $0.midi < $1.midi }) else { return [] }
        var run: [(pos: FretPos, midi: Int)] = [(lowestRoot.pos, lowestRoot.midi)]
        var last = lowestRoot.pos
        let byMidi = Dictionary(grouping: active, by: { $0.midi })
        for midi in (lowestRoot.midi + 1)...(lowestRoot.midi + 24) {
            guard let cands = byMidi[midi],
                  let best = cands.min(by: { abs($0.pos.fret - last.fret) < abs($1.pos.fret - last.fret) }) else { continue }
            run.append((best.pos, midi))
            last = best.pos
        }
        return run
    }

    private func trigger(_ events: [NoteEvent]) {
        synth.play(events.map { SynthNote(midi: $0.midi, time: $0.time) })
        let now = CACurrentMediaTime() + 0.05
        for e in events {
            if let p = e.pos { pulses[p] = now + e.time }
        }
    }

    func playProgression() {
        let steps = progression
        guard !steps.isEmpty else { return }
        playbackToken += 1
        let token = playbackToken
        let chordDur = 60.0 / max(tempo, 20) * Double(beatsPerChord)
        let vs = progressionVoicings
        let useVoicings = progressionDisplay == .voicings

        var notes: [SynthNote] = []
        var stepNotes: [[NoteEvent]] = []
        for (i, step) in steps.enumerated() {
            let t0 = Double(i) * chordDur
            var evs: [NoteEvent] = []
            if useVoicings, i < vs.count, let v = vs[i] {
                for (k, p) in strum(v).enumerated() {
                    evs.append(NoteEvent(pos: p.pos, midi: p.midi, time: Double(k) * 0.03))
                }
            } else {
                for (k, m) in closePosition(rootPC: step.rootPC, chord: step.chord, inversion: 0).enumerated() {
                    evs.append(NoteEvent(pos: nil, midi: m, time: Double(k) * 0.03))
                }
            }
            for e in evs { notes.append(SynthNote(midi: e.midi, time: t0 + e.time, length: chordDur + 0.35)) }
            stepNotes.append(evs)
        }

        isPlaying = true
        progressionStep = 0
        synth.play(notes)
        let start = DispatchTime.now() + 0.06
        for (i, evs) in stepNotes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: start + Double(i) * chordDur) { [weak self] in
                guard let self, self.playbackToken == token else { return }
                self.progressionStep = i
                let now = CACurrentMediaTime()
                for e in evs { if let p = e.pos { self.pulses[p] = now + e.time } }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: start + Double(steps.count) * chordDur) { [weak self] in
            guard let self, self.playbackToken == token else { return }
            if self.loopProgression {
                self.playProgression()
            } else {
                self.isPlaying = false
            }
        }
    }

    func stopPlayback() {
        playbackToken += 1
        isPlaying = false
        synth.stop()
    }
}
