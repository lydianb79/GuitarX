import SwiftUI
import AppKit

let appBackground = Color(red: 0.094, green: 0.094, blue: 0.104)
let surface = Color.white.opacity(0.045)
let hairline = Color.white.opacity(0.08)

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 360)
        } detail: {
            VStack(spacing: 0) {
                HeaderView()
                FretboardView(state: state)
                    .frame(height: FretboardLayout.idealHeight(strings: state.tuning.notes.count))
                StatusBar()
                Divider().overlay(hairline)
                ScrollView(.vertical) {
                    InfoPanel()
                }
            }
            .background(appBackground)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $state.mode) {
                        ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                    .help("Scale ⌘1 · Chord ⌘2 · Progression ⌘3")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button("This View…") { PDFExporter.exportCurrentView(state: state) }
                        Button("\(state.exportAllLabel)…") { PDFExporter.exportAll(state: state) }
                        Divider()
                        Toggle("Print-Friendly (Light)", isOn: $state.pdfPrintFriendly)
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                    .help("Export as PDF (⌘E, ⇧⌘E)")
                    Button {
                        state.playSelection()
                    } label: {
                        Label(state.isPlaying ? "Stop" : "Play",
                              systemImage: state.isPlaying ? "stop.fill" : "play.fill")
                    }
                    .help("Play / stop (Space)")
                }
            }
            .navigationTitle("GuitarX")
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Header

struct HeaderView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(state.title)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)
            Text(state.subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

// MARK: - Status bar under the fretboard

struct StatusBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 16) {
            if let h = state.hover {
                Text(state.describe(h))
                    .foregroundStyle(.primary)
            } else {
                Text("Hover a note to inspect it · click to hear it")
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            ColorLegend()
        }
        .font(.system(size: 11.5))
        .monospacedDigit()
        .padding(.horizontal, 24)
        .frame(height: 30)
    }
}

struct ColorLegend: View {
    @EnvironmentObject var state: AppState

    struct Entry: Identifiable {
        let name: String
        let rgb: SIMD3<Float>
        var id: String { name }
    }

    private var entries: [Entry] {
        switch state.colorMode {
        case .function:
            return [Entry(name: "Root", rgb: Palette.root),
                    Entry(name: "3rd", rgb: Palette.function[3] ?? Palette.neutral),
                    Entry(name: "5th", rgb: Palette.function[5] ?? Palette.neutral),
                    Entry(name: "7th", rgb: Palette.function[7] ?? Palette.neutral),
                    Entry(name: "Other", rgb: Palette.neutral)]
        case .spectrum:
            return (1...7).map { Entry(name: "\($0)", rgb: Palette.spectrum[$0]) }
        case .rootOnly:
            return [Entry(name: "Root", rgb: Palette.root), Entry(name: "Other", rgb: Palette.neutral)]
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(entries) { e in
                HStack(spacing: 5) {
                    Circle().fill(Palette.color(e.rgb)).frame(width: 8, height: 8)
                    Text(e.name).foregroundStyle(.secondary)
                }
            }
            if showsRingHint {
                HStack(spacing: 5) {
                    Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.3).frame(width: 10, height: 10)
                    Text(ringHint).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var showsRingHint: Bool {
        state.mode != .scale || state.selectedScaleShape != nil
    }

    private var ringHint: String {
        state.mode == .scale ? "Shape tone" : "Bass"
    }
}

// MARK: - Shared bits

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(.secondary)
    }
}

struct PillButton: View {
    let title: String
    let selected: Bool
    var minWidth: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: minWidth, minHeight: 24)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : surface))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.clear : hairline))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Dark tile with a small caption on top and a value below; used for chords and notes.
struct Tile: View {
    let top: String
    let bottom: String
    var accent: Color? = nil
    var selected = false
    var dimmed = false
    var minWidth: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if let accent {
                        Circle().fill(accent).frame(width: 7, height: 7)
                    }
                    Text(top)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                }
                Text(bottom)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .frame(minWidth: minWidth, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor : surface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Color.clear : hairline))
            .opacity(dimmed ? 0.35 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Stepper3: View {
    let title: String
    let subtitle: String
    let back: () -> Void
    let forward: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) { Image(systemName: "chevron.left").frame(width: 12, height: 14) }
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 110)
            Button(action: forward) { Image(systemName: "chevron.right").frame(width: 12, height: 14) }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

// MARK: - Info panel

struct InfoPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(state.mode == .scale ? "SCALE TONES" : "CHORD TONES")
                    NotesRow()
                }
                Spacer(minLength: 0)
                switch state.mode {
                case .chord: VoicingNavigator()
                case .scale: PositionSelector()
                case .progression: ProgressionVoicingInfo()
                }
            }
            if state.mode == .scale && !state.harmonized.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        SectionLabel("DIATONIC CHORDS  ·  CLICK OR PRESS 1–7 TO PLAY")
                        Toggle("Sevenths", isOn: $state.harmonySevenths)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                    HarmonyRow()
                }
            }
            if state.mode == .progression {
                ProgressionPanel()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NotesRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let ivs = state.currentIntervals
        let names = state.spelledNotes
        HStack(spacing: 6) {
            ForEach(Array(ivs.enumerated()), id: \.offset) { i, iv in
                Tile(top: iv.label,
                     bottom: names[i].text,
                     accent: Palette.color(degree: iv.simpleDegree, isRoot: iv.pitchClass == 0, mode: state.colorMode),
                     dimmed: state.hiddenPCs.contains(iv.pitchClass),
                     minWidth: 34) {
                    state.toggleHidden(iv.pitchClass)
                }
                .help("Click to hide or show \(names[i].text) on the fretboard")
            }
        }
    }
}

struct VoicingNavigator: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            switch state.chordDisplay {
            case .voicings:
                SectionLabel("VOICING")
                let all = state.voicings
                if let v = state.currentVoicing {
                    Stepper3(title: "\(min(state.voicingIndex, all.count - 1) + 1) of \(all.count)",
                             subtitle: v.shorthand,
                             back: { state.step(-1) }, forward: { state.step(1) })
                        .help("Previous / next voicing (⌥← ⌥→)")
                    Text(v.minFret == 0 ? "Open position" : "Frets \(v.minFret)–\(v.maxFret)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No playable voicing for this\ninversion and string count")
                        .font(.callout)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

            case .allTones:
                SectionLabel("ALL CHORD TONES")
                Text(state.inversion == 0
                     ? "Root position"
                     : "Bass note \(state.rootName.adding(state.bassInterval).text) is ringed")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .caged:
                SectionLabel("CAGED SHAPE")
                let shapes = state.chordCAGEDShapes
                if shapes.isEmpty {
                    Text("CAGED needs a 6-string tuning\nin standard intervals")
                        .font(.callout)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(shapes.enumerated()), id: \.offset) { i, s in
                            PillButton(title: s.shape.rawValue,
                                       selected: min(state.cagedIndex, shapes.count - 1) == i,
                                       minWidth: 32) { state.cagedIndex = i }
                        }
                    }
                    .help("Shapes in neck order (⌥← ⌥→)")
                    if let s = state.currentChordShape {
                        Text(state.chordHasExactCAGED
                             ? "\(s.voicing.shorthand)   ·   frets \(s.minFret)–\(s.maxFret)"
                             : "Chord tones in the \(s.shape.rawValue)-shape region, frets \(s.minFret)–\(s.maxFret)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct PositionSelector: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 10) {
                SectionLabel("POSITION")
                Picker("System", selection: $state.positionSystem) {
                    ForEach(PositionSystem.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 190)
            }
            HStack(spacing: 4) {
                PillButton(title: "All", selected: state.scalePosition == 0) { state.scalePosition = 0 }
                if state.positionSystem == .boxes {
                    let count = state.scalePositions.count
                    ForEach(Array(1...max(count, 1)), id: \.self) { i in
                        PillButton(title: "\(i)", selected: state.scalePosition == i) { state.scalePosition = i }
                    }
                } else if state.positionSystem == .nps {
                    ForEach(Array(state.npsPatterns.enumerated()), id: \.offset) { i, _ in
                        PillButton(title: "\(i + 1)", selected: state.scalePosition == i + 1) { state.scalePosition = i + 1 }
                    }
                } else {
                    ForEach(Array(state.scaleCAGEDShapes.enumerated()), id: \.offset) { i, s in
                        PillButton(title: s.shape.rawValue, selected: state.scalePosition == i + 1, minWidth: 32) {
                            state.scalePosition = i + 1
                        }
                    }
                }
            }
            .help("Previous / next position (⌥← ⌥→)")
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var caption: String {
        switch state.positionSystem {
        case .boxes:
            let p = state.scalePositions
            if state.scalePosition > 0 && state.scalePosition <= p.count {
                let r = p[state.scalePosition - 1]
                return "Frets \(r.lowerBound)–\(r.upperBound)"
            }
            return "Whole neck"
        case .caged:
            if state.scaleCAGEDShapes.isEmpty { return "CAGED needs a 6-string tuning in standard intervals" }
            if let s = state.selectedScaleShape {
                let frets = state.cagedScalePattern(s).map(\.fret)
                let lo = frets.min() ?? s.minFret, hi = frets.max() ?? s.maxFret
                return "\(s.shape.rawValue) shape · frets \(lo)–\(hi) · ringed = \(s.shape.rawValue) chord"
            }
            return "Whole neck"
        case .nps:
            let n = state.notesPerString
            if let p = state.selectedNPSPattern {
                let name = state.rootName.adding(state.scale.intervals[max(0, min(p.startDegree - 1, state.scale.intervals.count - 1))]).text
                return "\(n) notes per string · starts on \(name) (degree \(p.startDegree)) · frets \(p.minFret)–\(p.maxFret)"
            }
            return "Whole neck · \(n) notes per string"
        }
    }
}

struct HarmonyRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(state.harmonized) { h in
                Tile(top: h.numeral, bottom: h.name, minWidth: 54) {
                    if NSEvent.modifierFlags.contains(.command) { state.select(h) } else { state.playHarmony(h) }
                }
                .disabled(h.chord == nil)
                .help("Click to hear \(h.name) · ⌘-click to open it in Chord mode")
                .contextMenu {
                    Button("Play \(h.name)") { state.playHarmony(h) }
                    Button("Open in Chord Mode") { state.select(h) }
                }
            }
        }
    }
}

// MARK: - Progression

struct ProgressionVoicingInfo: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            SectionLabel("CHORD")
            if let step = state.currentStep {
                Stepper3(title: "\(step.id + 1) of \(state.progression.count)",
                         subtitle: state.displayedVoicing?.shorthand ?? step.chord.name,
                         back: { state.step(-1) }, forward: { state.step(1) })
                    .help("Previous / next chord (⌥← ⌥→)")
            } else {
                Text("No chords yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProgressionPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let steps = state.progression
        let current = state.currentStep?.id ?? -1
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("PROGRESSION IN \(state.rootName.text.uppercased())")
                    Spacer()
                    Button("Remove Last") { state.removeLastFromProgression() }
                        .disabled(steps.isEmpty)
                    Button("Clear") { state.progressionText = "" }
                        .disabled(steps.isEmpty)
                }
                .controlSize(.small)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(steps) { step in
                            Tile(top: state.displayToken(step.token), bottom: step.name,
                                 selected: step.id == current, minWidth: 54) {
                                state.playStep(step.id)
                            }
                            .help("Click to hear \(step.name)")
                        }
                    }
                }
                if steps.isEmpty {
                    Text("Load a preset or type Roman numerals in the sidebar, or add chords below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            let diatonic = state.harmonize(sevenths: state.harmonySevenths)
            if !diatonic.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        SectionLabel("ADD FROM \(state.rootName.text.uppercased()) \(state.scale.name.uppercased())  ·  ⇧1–7")
                        Toggle("Sevenths", isOn: $state.harmonySevenths)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                    HStack(spacing: 6) {
                        ForEach(diatonic) { h in
                            Tile(top: h.numeral, bottom: h.name, minWidth: 54) {
                                if let t = h.token { state.appendToProgression(t) }
                                state.playHarmony(h)
                            }
                            .disabled(h.token == nil)
                            .help("Append \(h.name) to the progression (⇧\(h.id + 1))")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Key") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 6), spacing: 5) {
                    ForEach(0..<12, id: \.self) { pc in
                        KeyButton(pc: pc)
                    }
                }
                .padding(.vertical, 2)
                Picker("Spelling", selection: $state.spelling) {
                    ForEach(Spelling.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            switch state.mode {
            case .scale: scaleSection
            case .chord: chordSection
            case .progression: progressionSections
            }

            Section("Display") {
                Picker("Labels", selection: $state.labelMode) {
                    ForEach(LabelMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Colors", selection: $state.colorMode) {
                    ForEach(ColorMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Dim notes outside selection", isOn: $state.showGhostNotes)
                Toggle("Show all chromatic notes", isOn: $state.showChromatic)
                Toggle("Left-handed", isOn: $state.leftHanded)
            }

            Section("Instrument") {
                Picker("Tuning", selection: $state.tuningID) {
                    ForEach(TuningLibrary.all) { Text($0.name).tag($0.id) }
                }
                Picker("Frets", selection: $state.fretCount) {
                    ForEach([12, 15, 17, 19, 20, 21, 22, 24], id: \.self) { Text("\($0)").tag($0) }
                }
                Picker("Fretboard", selection: $state.wood) {
                    ForEach(WoodStyle.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section("Sound") {
                Picker("Instrument", selection: $state.tone) {
                    ForEach(GuitarTone.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Chord style", selection: $state.playStyle) {
                    ForEach(PlayStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                if state.tone != .synth && state.tuning.id.hasPrefix("Bass") {
                    Text("Bass tunings use the fingered bass sample.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if state.tone != .synth && !state.samplesAvailable {
                    Text("macOS guitar samples not found; using the synth.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var scalePicker: some View {
        Picker("Scale", selection: $state.scaleID) {
            ForEach(ScaleLibrary.categories, id: \.self) { cat in
                Section(header: Text(cat)) {
                    ForEach(ScaleLibrary.all.filter { $0.category == cat }) { s in
                        Text(s.name).tag(s.id)
                    }
                }
            }
        }
    }

    private var stringsPicker: some View {
        Picker("Strings", selection: $state.voicingStrings) {
            Text("Any (4+)").tag(0)
            ForEach(Array(2...max(state.tuning.notes.count, 2)), id: \.self) { n in
                Text("\(n)").tag(n)
            }
        }
    }

    @ViewBuilder private var scaleSection: some View {
        Section("Scale") {
            scalePicker
        }
    }

    @ViewBuilder private var chordSection: some View {
        Section("Chord") {
            Picker("Chord", selection: $state.chordID) {
                ForEach(ChordLibrary.categories, id: \.self) { cat in
                    Section(header: Text(cat)) {
                        ForEach(ChordLibrary.all.filter { $0.category == cat }) { c in
                            Text("\(state.rootName.text)\(c.symbol)  —  \(c.name)").tag(c.id)
                        }
                    }
                }
            }
            Picker("View", selection: $state.chordDisplay) {
                ForEach(ChordDisplay.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Inversion", selection: $state.inversion) {
                ForEach(0..<state.chord.intervals.count, id: \.self) { i in
                    let bass = state.rootName.adding(state.chord.intervals[i]).text
                    Text("\(state.inversionName(i)) (\(bass))").tag(i)
                }
            }
            .disabled(state.chordDisplay == .caged)
            if state.chordDisplay == .voicings {
                stringsPicker
            }
        }
    }

    @ViewBuilder private var progressionSections: some View {
        Section("Progression") {
            Menu("Load Preset") {
                ForEach(ProgressionLibrary.presets) { p in
                    Button(p.name) { state.progressionText = p.text }
                }
            }
            TextField("Roman numerals", text: $state.progressionText, axis: .vertical)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(2...5)
            let invalid = state.parsedProgression.invalid
            if !invalid.isEmpty {
                Text("Not recognised: \(invalid.joined(separator: "  "))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("I ii iii IV V vi vii°, with 7, maj7, ø7, °7, 9, sus4, 7b9 … Prefix b or # for borrowed chords (bVII, #iv°).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            scalePicker
        }
        Section("Voicings") {
            Picker("View", selection: $state.progressionDisplay) {
                ForEach(ProgressionDisplay.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if state.progressionDisplay == .voicings {
                stringsPicker
                Stepper("Around fret \(state.progressionFret)", value: $state.progressionFret,
                        in: 0...max(0, state.fretCount - 4))
                Toggle("Use inversions", isOn: $state.allowInversions)
            }
        }
        Section("Playback") {
            LabeledContent("Tempo") {
                HStack {
                    Slider(value: $state.tempo, in: 40...220, step: 1)
                    Text("\(Int(state.tempo)) bpm")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
            }
            Picker("Beats per chord", selection: $state.beatsPerChord) {
                ForEach([1, 2, 4, 8], id: \.self) { Text("\($0)").tag($0) }
            }
            Toggle("Loop", isOn: $state.loopProgression)
        }
    }
}

struct KeyButton: View {
    @EnvironmentObject var state: AppState
    let pc: Int

    var body: some View {
        let selected = state.rootPC == pc
        Button {
            state.rootPC = pc
        } label: {
            Text(state.keyName(pc).text)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor : surface))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.clear : hairline))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
