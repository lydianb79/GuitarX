import SwiftUI
import Combine
import QuartzCore

enum ViewMode: String, CaseIterable, Identifiable {
    case scale = "Scale", chord = "Chord"
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
    case voicings = "Voicings", allTones = "All Tones"
    var id: String { rawValue }
}

enum WoodStyle: String, CaseIterable, Identifiable {
    case rosewood = "Rosewood", ebony = "Ebony", maple = "Maple"
    var id: String { rawValue }
}

enum MarkerRole { case active, bass, ghost, chromatic }

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
    let root: NoteName
    let chord: ChordType?
    var name: String { root.text + (chord?.symbol ?? " ?") }
}

struct NoteEvent {
    let pos: FretPos?
    let midi: Int
    let time: Double
}

final class AppState: ObservableObject {
    // Selection
    @Published var mode: ViewMode = .scale { didSet { hiddenPCs = [] } }
    @Published var rootPC: Int = 0 { didSet { voicingIndex = 0 } }
    @Published var spelling: Spelling = .auto
    @Published var scaleID: String = ScaleLibrary.all[0].id { didSet { hiddenPCs = []; scalePosition = 0 } }
    @Published var chordID: String = ChordLibrary.all[0].id { didSet { hiddenPCs = []; inversion = 0; voicingIndex = 0 } }
    @Published var inversion: Int = 0 { didSet { voicingIndex = 0 } }
    @Published var chordDisplay: ChordDisplay = .voicings
    @Published var voicingStrings: Int = 0 { didSet { voicingIndex = 0 } }
    @Published var voicingIndex: Int = 0
    @Published var scalePosition: Int = 0

    // Instrument
    @Published var tuningID: String = TuningLibrary.all[0].id {
        didSet {
            voicingIndex = 0
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
    private lazy var synth = GuitarSynth()

    // MARK: Derived

    var scale: ScaleType { ScaleLibrary.byID[scaleID] ?? ScaleLibrary.all[0] }
    var chord: ChordType { ChordLibrary.byID[chordID] ?? ChordLibrary.all[0] }
    var tuning: Tuning { TuningLibrary.all.first { $0.id == tuningID } ?? TuningLibrary.all[0] }
    var currentIntervals: [Interval] { mode == .scale ? scale.intervals : chord.intervals }

    func keyName(_ pc: Int) -> NoteName {
        switch spelling {
        case .sharps: return NoteName.from(pitchClass: pc, preferFlats: false)
        case .flats: return NoteName.from(pitchClass: pc, preferFlats: true)
        case .auto: return NoteName.from(pitchClass: pc, preferFlats: [1, 3, 8, 10].contains(mod12(pc)))
        }
    }

    var rootName: NoteName { keyName(rootPC) }
    var spelledNotes: [NoteName] { currentIntervals.map { rootName.adding($0) } }
    var bassInterval: Interval { chord.intervals[min(inversion, chord.intervals.count - 1)] }

    func inversionName(_ i: Int) -> String {
        if i == 0 { return "Root Position" }
        let ord = ["1st", "2nd", "3rd", "4th", "5th", "6th"]
        return "\(ord[min(i - 1, ord.count - 1)]) Inversion"
    }

    var title: String {
        switch mode {
        case .scale:
            return "\(rootName.text) \(scale.name)"
        case .chord:
            let base = "\(rootName.text)\(chord.symbol)"
            return inversion > 0 ? "\(base) / \(rootName.adding(bassInterval).text)" : base
        }
    }

    var subtitle: String {
        switch mode {
        case .scale: return "\(scale.category)   ·   \(scale.formula)"
        case .chord: return "\(chord.name)   ·   \(inversionName(inversion))   ·   \(chord.formula)"
        }
    }

    var scalePositions: [ClosedRange<Int>] {
        let open = tuning.notes[0]
        let starts = Set(scale.intervals.map { mod12(rootPC + $0.semitones - open) }).sorted()
        return starts.map { $0...min($0 + 4, fretCount) }
    }

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

    var harmonized: [HarmonyChord] {
        guard mode == .scale, scale.isHeptatonic else { return [] }
        let ivs = scale.intervals
        let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
        return (0..<7).map { i in
            let base = ivs[i]
            let tones = [0, 2, 4, 6].map { ivs[(i + $0) % 7] }
            let rels = tones.map { mod12($0.semitones - base.semitones) }
            let chord = ChordLibrary.match(pcs: rels) ?? ChordLibrary.match(pcs: Array(rels.prefix(3)))
            let numeral = rels[1] == 4 ? numerals[i] : numerals[i].lowercased()
            return HarmonyChord(id: i, numeral: numeral, root: rootName.adding(base), chord: chord)
        }
    }

    // MARK: Fretboard model

    func computeMarkers() -> [Marker] {
        let ivs = currentIntervals
        var lookup: [Int: (index: Int, interval: Interval)] = [:]
        for (i, iv) in ivs.enumerated() where lookup[iv.pitchClass] == nil {
            lookup[iv.pitchClass] = (i, iv)
        }
        let names = spelledNotes
        let positions = scalePositions
        let window: ClosedRange<Int>? =
            (mode == .scale && scalePosition > 0 && scalePosition <= positions.count) ? positions[scalePosition - 1] : nil
        let useVoicing = mode == .chord && chordDisplay == .voicings
        let voicing: Voicing? = useVoicing ? currentVoicing : nil
        let voicingBass = voicing?.bassPosition(tuning: tuning.notes)
        let bassRel = bassInterval.pitchClass
        let preferFlats = rootName.accidental < 0 || spelling == .flats || (spelling == .auto && tuning.prefersFlats)
        let notes = tuning.notes

        var out: [Marker] = []
        for s in 0..<notes.count {
            for f in 0...fretCount {
                let midi = notes[s] + f
                let rel = mod12(midi - rootPC)
                let pos = FretPos(string: s, fret: f)
                if let hit = lookup[rel], !hiddenPCs.contains(rel) {
                    var role: MarkerRole = .active
                    if let w = window, !w.contains(f) { role = .ghost }
                    if mode == .chord {
                        if useVoicing {
                            if let v = voicing, s < v.frets.count, v.frets[s] == f {
                                role = (pos == voicingBass) ? .bass : .active
                            } else {
                                role = .ghost
                            }
                        } else if inversion > 0 && rel == bassRel {
                            role = .bass
                        }
                    }
                    if role == .ghost && !showGhostNotes { continue }

                    let label: String
                    switch labelMode {
                    case .notes: label = names[hit.index].text
                    case .intervals: label = hit.interval.label
                    case .degrees: label = mode == .scale ? "\(hit.index + 1)" : "\(hit.interval.degree)"
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
        let rel = mod12(midi - rootPC)
        let octave = midi / 12 - 1
        let where_ = "string \(tuning.notes.count - pos.string) · fret \(pos.fret)"
        if let i = currentIntervals.firstIndex(where: { $0.pitchClass == rel }) {
            return "\(spelledNotes[i].text)\(octave)  ·  \(currentIntervals[i].label)  ·  \(where_)"
        }
        let n = NoteName.from(pitchClass: midi, preferFlats: rootName.accidental < 0)
        return "\(n.text)\(octave)  ·  \(where_)"
    }

    // MARK: Actions

    func shiftKey(_ d: Int) { rootPC = mod12(rootPC + d) }

    func step(_ d: Int) {
        if mode == .chord {
            let n = voicings.count
            guard n > 0 else { return }
            if chordDisplay != .voicings { chordDisplay = .voicings }
            voicingIndex = ((voicingIndex + d) % n + n) % n
        } else {
            let n = scalePositions.count + 1
            scalePosition = ((scalePosition + d) % n + n) % n
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

    // MARK: Sound

    func playNote(at pos: FretPos) {
        guard pos.string < tuning.notes.count else { return }
        trigger([NoteEvent(pos: pos, midi: tuning.notes[pos.string] + pos.fret, time: 0)])
    }

    func playSelection() {
        var events: [NoteEvent] = []
        if mode == .chord {
            if chordDisplay == .voicings, let v = currentVoicing {
                var played: [(pos: FretPos, midi: Int)] = []
                for (s, f) in v.frets.enumerated() {
                    if let f, s < tuning.notes.count { played.append((FretPos(string: s, fret: f), tuning.notes[s] + f)) }
                }
                played.sort { $0.midi < $1.midi }
                for (i, p) in played.enumerated() {
                    events.append(NoteEvent(pos: p.pos, midi: p.midi, time: Double(i) * 0.045))
                }
            } else {
                let count = chord.intervals.count
                let bassPC = rootPC + bassInterval.semitones
                var prev = 40 + mod12(bassPC - 40)
                events.append(NoteEvent(pos: nil, midi: prev, time: 0))
                if count > 1 {
                    for k in 1..<count {
                        let iv = chord.intervals[(inversion + k) % count]
                        var m = prev + mod12(rootPC + iv.semitones - prev)
                        if m == prev { m += 12 }
                        events.append(NoteEvent(pos: nil, midi: m, time: Double(k) * 0.05))
                        prev = m
                    }
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

    private func scaleRun() -> [(pos: FretPos, midi: Int)] {
        let active = computeMarkers().filter { $0.role == .active || $0.role == .bass }
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
}
