import SwiftUI

let appBackground = Color(red: 0.055, green: 0.055, blue: 0.065)

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 320, max: 400)
        } detail: {
            VStack(spacing: 0) {
                HeaderView()
                FretboardView(state: state)
                    .frame(minHeight: 280)
                InfoPanel()
            }
            .background(appBackground)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Header

struct HeaderView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(state.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(state.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if let h = state.hover {
                Text(state.describe(h))
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
            }
            Menu {
                Button("This View…") { PDFExporter.exportCurrentView(state: state) }
                Button("\(state.exportAllLabel)…") { PDFExporter.exportAll(state: state) }
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .controlSize(.large)
            .fixedSize()
            .help("Export as PDF (⌘E / ⇧⌘E)")
            Button {
                state.playSelection()
            } label: {
                Label(state.isPlaying ? "Stop" : "Play",
                      systemImage: state.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Play / stop (Space)")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

// MARK: - Shared bits

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.2)
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
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: minWidth, minHeight: 26)
                .padding(.horizontal, 3)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.white.opacity(0.07)))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ChordChip: View {
    let top: String
    let bottom: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(top)
                    .font(.system(size: 11, weight: .bold, design: .serif))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                Text(bottom)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .frame(minWidth: 62, minHeight: 46)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0 : 0.09)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info panel

struct InfoPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("NOTES  ·  CLICK TO HIDE / SHOW")
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
                    SectionLabel("DIATONIC 7TH CHORDS  ·  CLICK TO EXPLORE")
                    HarmonyRow()
                }
            }
            if state.mode == .progression {
                ProgressionPanel()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 20)
    }
}

struct NotesRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let ivs = state.currentIntervals
        let names = state.spelledNotes
        HStack(spacing: 7) {
            ForEach(Array(ivs.enumerated()), id: \.offset) { i, iv in
                let hidden = state.hiddenPCs.contains(iv.pitchClass)
                let color = Palette.color(degree: iv.simpleDegree, isRoot: iv.pitchClass == 0,
                                          colorful: state.colorByInterval)
                Button {
                    state.toggleHidden(iv.pitchClass)
                } label: {
                    VStack(spacing: 1) {
                        Text(names[i].text)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Text(iv.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .opacity(0.7)
                    }
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(minWidth: 44, minHeight: 50)
                    .padding(.horizontal, 3)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color))
                    .opacity(hidden ? 0.22 : 1)
                }
                .buttonStyle(.plain)
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
                SectionLabel("VOICING  ·  ⌥← ⌥→")
                let all = state.voicings
                if let v = state.currentVoicing {
                    HStack(spacing: 10) {
                        Button { state.step(-1) } label: { Image(systemName: "chevron.left").frame(width: 14) }
                        VStack(spacing: 2) {
                            Text("\(min(state.voicingIndex, all.count - 1) + 1) / \(all.count)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(v.shorthand)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 120)
                        Button { state.step(1) } label: { Image(systemName: "chevron.right").frame(width: 14) }
                    }
                    .buttonStyle(.bordered)
                    Text(v.minFret == 0 ? "Open position" : "Frets \(v.minFret)–\(v.maxFret)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No playable voicing for this\ninversion / string count")
                        .font(.callout)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

            case .allTones:
                SectionLabel("ALL CHORD TONES")
                Text(state.inversion == 0
                     ? "Root position"
                     : "Bass (ringed): \(state.rootName.adding(state.bassInterval).text)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .caged:
                SectionLabel("CAGED SHAPE  ·  ⌥← ⌥→")
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
                                       minWidth: 34) { state.cagedIndex = i }
                        }
                    }
                    if let s = state.currentChordShape {
                        Text(state.chordHasExactCAGED
                             ? "\(s.voicing.shorthand)  ·  frets \(s.minFret)–\(s.maxFret)"
                             : "Chord tones in the \(s.shape.rawValue)-shape region, frets \(s.minFret)–\(s.maxFret)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
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
                SectionLabel("POSITION  ·  ⌥← ⌥→")
                Picker("System", selection: $state.positionSystem) {
                    ForEach(PositionSystem.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            HStack(spacing: 4) {
                PillButton(title: "All", selected: state.scalePosition == 0) { state.scalePosition = 0 }
                if state.positionSystem == .boxes {
                    let count = state.scalePositions.count
                    ForEach(Array(1...max(count, 1)), id: \.self) { i in
                        PillButton(title: "\(i)", selected: state.scalePosition == i) { state.scalePosition = i }
                    }
                } else {
                    ForEach(Array(state.scaleCAGEDShapes.enumerated()), id: \.offset) { i, s in
                        PillButton(title: s.shape.rawValue, selected: state.scalePosition == i + 1, minWidth: 34) {
                            state.scalePosition = i + 1
                        }
                    }
                }
            }
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
                return "\(s.shape.rawValue) shape · frets \(max(0, s.minFret - 1))–\(s.maxFret + 1) · ringed notes = chord shape"
            }
            return "Whole neck"
        }
    }
}

struct HarmonyRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 7) {
            ForEach(state.harmonized) { h in
                ChordChip(top: h.numeral, bottom: h.name, selected: false) { state.select(h) }
                    .disabled(h.chord == nil)
            }
        }
    }
}

// MARK: - Progression

struct ProgressionVoicingInfo: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            SectionLabel("CHORD  ·  ⌥← ⌥→")
            if let step = state.currentStep {
                HStack(spacing: 10) {
                    Button { state.step(-1) } label: { Image(systemName: "chevron.left").frame(width: 14) }
                    VStack(spacing: 2) {
                        Text("\(step.id + 1) / \(state.progression.count)")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        if let v = state.displayedVoicing {
                            Text(v.shorthand)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(step.chord.name)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 120)
                    Button { state.step(1) } label: { Image(systemName: "chevron.right").frame(width: 14) }
                }
                .buttonStyle(.bordered)
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("PROGRESSION IN \(state.rootName.text.uppercased())  ·  CLICK A CHORD  ·  SPACE PLAYS")
                    Spacer()
                    Button("Remove Last") { state.removeLastFromProgression() }
                        .disabled(steps.isEmpty)
                    Button("Clear") { state.progressionText = "" }
                        .disabled(steps.isEmpty)
                }
                .controlSize(.small)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(steps) { step in
                            ChordChip(top: state.displayToken(step.token), bottom: step.name,
                                      selected: step.id == current) {
                                state.progressionStep = step.id
                            }
                        }
                    }
                }
                if steps.isEmpty {
                    Text("Empty. Load a preset, type numerals in the sidebar, or add chords below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            let diatonic = state.harmonize(sevenths: state.harmonySevenths)
            if !diatonic.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        SectionLabel("ADD CHORD FROM \(state.rootName.text.uppercased()) \(state.scale.name.uppercased())")
                        Toggle("7ths", isOn: $state.harmonySevenths)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                    HStack(spacing: 7) {
                        ForEach(diatonic) { h in
                            ChordChip(top: h.numeral, bottom: h.name, selected: false) {
                                if let t = h.token { state.appendToProgression(t) }
                            }
                            .disabled(h.token == nil)
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
            Section {
                Picker("Mode", selection: $state.mode) {
                    ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Key") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
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
                Toggle("Color by interval", isOn: $state.colorByInterval)
                Toggle("Dim notes outside position / voicing", isOn: $state.showGhostNotes)
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
                Text("\(n) strings").tag(n)
            }
        }
    }

    @ViewBuilder private var scaleSection: some View {
        Section("Scale / Mode") {
            scalePicker
            LabeledContent("Formula") {
                Text(state.scale.formula)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
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
            Picker("Show", selection: $state.chordDisplay) {
                ForEach(ChordDisplay.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Inversion", selection: $state.inversion) {
                ForEach(0..<state.chord.intervals.count, id: \.self) { i in
                    let bass = state.rootName.adding(state.chord.intervals[i]).text
                    Text("\(state.inversionName(i))  (bass \(bass))").tag(i)
                }
            }
            .disabled(state.chordDisplay == .caged)
            if state.chordDisplay == .voicings {
                stringsPicker
            }
            LabeledContent("Formula") {
                Text(state.chord.formula)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
    }

    @ViewBuilder private var progressionSections: some View {
        Section("Progression") {
            Menu("Load Preset…") {
                ForEach(ProgressionLibrary.presets) { p in
                    Button(p.name) { state.progressionText = p.text }
                }
            }
            TextField("Roman numerals", text: $state.progressionText, axis: .vertical)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .lineLimit(2...5)
            let invalid = state.parsedProgression.invalid
            if !invalid.isEmpty {
                Text("Not understood: \(invalid.joined(separator: "  "))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Text("I ii iii IV V vi vii°, then 7 · maj7 · ø7 · °7 · 9 · sus4 · 7b9 …  Prefix b or # for borrowed chords (bVII, #iv°).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            scalePicker
        }
        Section("Fretboard") {
            Picker("Show", selection: $state.progressionDisplay) {
                ForEach(ProgressionDisplay.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if state.progressionDisplay == .voicings {
                stringsPicker
                Stepper("Around fret \(state.progressionFret)", value: $state.progressionFret,
                        in: 0...max(0, state.fretCount - 4))
                Toggle("Use inversions for voice leading", isOn: $state.allowInversions)
            }
        }
        Section("Playback") {
            LabeledContent("Tempo") {
                HStack {
                    Slider(value: $state.tempo, in: 40...220, step: 1)
                    Text("\(Int(state.tempo))")
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
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
        let isBlack = [1, 3, 6, 8, 10].contains(pc)
        Button {
            state.rootPC = pc
        } label: {
            Text(state.keyName(pc).text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.accentColor
                                   : (isBlack ? Color.black.opacity(0.35) : Color.white.opacity(0.08))))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
