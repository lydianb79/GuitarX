import SwiftUI

let appBackground = Color(red: 0.055, green: 0.055, blue: 0.065)

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 290, ideal: 310, max: 380)
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
                    .transition(.opacity)
            }
            Button {
                state.playSelection()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Play the scale / chord (Space)")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

// MARK: - Info panel

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
                if state.mode == .chord {
                    VoicingNavigator()
                } else {
                    PositionSelector()
                }
            }
            if state.mode == .scale && !state.harmonized.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("DIATONIC 7TH CHORDS  ·  CLICK TO EXPLORE")
                    HarmonyRow()
                }
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
            if state.chordDisplay == .voicings {
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
            } else {
                SectionLabel("ALL CHORD TONES")
                Text(state.inversion == 0
                     ? "Root position"
                     : "Bass (ringed): \(state.rootName.adding(state.bassInterval).text)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PositionSelector: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let positions = state.scalePositions
        VStack(alignment: .trailing, spacing: 8) {
            SectionLabel("POSITION  ·  ⌥← ⌥→")
            HStack(spacing: 4) {
                PositionButton(title: "All", index: 0)
                ForEach(Array(1...max(positions.count, 1)), id: \.self) { i in
                    PositionButton(title: "\(i)", index: i)
                }
            }
            if state.scalePosition > 0 && state.scalePosition <= positions.count {
                let r = positions[state.scalePosition - 1]
                Text("Frets \(r.lowerBound)–\(r.upperBound)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Whole neck")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PositionButton: View {
    @EnvironmentObject var state: AppState
    let title: String
    let index: Int

    var body: some View {
        let selected = state.scalePosition == index
        Button {
            state.scalePosition = index
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: 28, minHeight: 26)
                .padding(.horizontal, 3)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.white.opacity(0.07)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct HarmonyRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 7) {
            ForEach(state.harmonized) { h in
                Button {
                    state.select(h)
                } label: {
                    VStack(spacing: 2) {
                        Text(h.numeral)
                            .font(.system(size: 11, weight: .bold, design: .serif))
                            .foregroundStyle(.secondary)
                        Text(h.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .frame(minWidth: 66, minHeight: 46)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .disabled(h.chord == nil)
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

            if state.mode == .scale {
                Section("Scale / Mode") {
                    Picker("Scale", selection: $state.scaleID) {
                        ForEach(ScaleLibrary.categories, id: \.self) { cat in
                            Section(header: Text(cat)) {
                                ForEach(ScaleLibrary.all.filter { $0.category == cat }) { s in
                                    Text(s.name).tag(s.id)
                                }
                            }
                        }
                    }
                    LabeledContent("Formula") {
                        Text(state.scale.formula)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
            } else {
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
                    Picker("Inversion", selection: $state.inversion) {
                        ForEach(0..<state.chord.intervals.count, id: \.self) { i in
                            let bass = state.rootName.adding(state.chord.intervals[i]).text
                            Text("\(state.inversionName(i))  (bass \(bass))").tag(i)
                        }
                    }
                    Picker("Show", selection: $state.chordDisplay) {
                        ForEach(ChordDisplay.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if state.chordDisplay == .voicings {
                        Picker("Strings", selection: $state.voicingStrings) {
                            Text("Any (4+)").tag(0)
                            ForEach(Array(2...max(state.tuning.notes.count, 2)), id: \.self) { n in
                                Text("\(n) strings").tag(n)
                            }
                        }
                    }
                    LabeledContent("Formula") {
                        Text(state.chord.formula)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                }
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
