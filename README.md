# GuitarX — Fretboard Navigator

A native macOS app (SwiftUI + Metal) that renders a guitar fretboard and shows any scale, mode or chord/inversion on it.

## Download

Get the latest version from [Releases](https://github.com/lydianb79/GuitarX/releases/latest):

| Your Mac | Download |
|---|---|
| Apple Silicon (M1, M2, M3, M4 …) | [GuitarX-arm64.zip](https://github.com/lydianb79/GuitarX/releases/latest/download/GuitarX-arm64.zip) |
| Intel | [GuitarX-x86_64.zip](https://github.com/lydianb79/GuitarX/releases/latest/download/GuitarX-x86_64.zip) |

Not sure which one you need? Open the Apple menu → **About This Mac**. "Chip: Apple M…" means Apple Silicon; "Processor: Intel…" means Intel.

Requires **macOS 14 (Sonoma)** or later.

**First launch:** the app isn't signed with an Apple Developer ID, so macOS warns you the first time. Unzip it, move **GuitarX** to Applications, then **right-click the app → Open** and confirm. After that it opens normally.

## Build from source

Requires macOS 14+ and Xcode 15+ (or the Xcode Command Line Tools).

```bash
git clone https://github.com/lydianb79/GuitarX.git
cd GuitarX
./build-app.sh            # builds build/GuitarX.app for this Mac's architecture
open build/GuitarX.app
```

Or open `Package.swift` in Xcode and press ⌘R.

To build for a specific architecture, for example an Intel build on an Apple Silicon Mac, pass `--arch` to SwiftPM:

```bash
swift build -c release --arch x86_64 --scratch-path .build/x86_64   # or: --arch arm64
swift build -c release --arch x86_64 --scratch-path .build/x86_64 --show-bin-path   # where the binary is
```

`build-app.sh` shows how to wrap the binary into an `.app` bundle with an icon and `Info.plist`.

## Features

- **Metal renderer.** Every element is an instanced quad drawn with a signed-distance-field shader: procedural ebony (the default), rosewood or maple grain, with binding, pearl inlays, metal frets, and wound and plain strings. Note markers are flat discs with a fine rim. Labels come from a CoreText glyph atlas. Fret spacing follows real equal temperament, blended so the high frets stay usable. Markers animate in when the selection changes and glow while their note plays.
- **Scales & modes (~60), in all 12 keys:** the modes of major, melodic minor, harmonic minor, harmonic major and double harmonic; pentatonics and blues; bebop; symmetric scales; and exotic scales. Note names are spelled correctly for the key (e.g. G♯ harmonic minor gives F𝄪, shown as F♯♯).
- **Chords (~50) with every inversion:** triads, 6ths, 7ths, added-tone chords, 9ths, 11ths, 13ths and altered dominants.
  - *Voicings* finds playable grips for the chosen inversion (the lowest note is the inversion's bass) across the whole neck, and lets you filter by number of strings. For example, choose 3 strings to study triad inversions on each string set.
  - *All Tones* shows every chord tone on the neck, with the bass note ringed.
  - *CAGED* shows the exact C·A·G·E·D grips for major, minor, 7, maj7 and m7 chords. For other chord types it shows the chord tones inside each shape's area of the neck.
- **Scale positions**, three systems:
  - *Boxes:* 5-fret windows, one starting on each scale degree.
  - *CAGED:* the five CAGED fingerings in neck order. Each pitch appears once within one hand position, and the shape's chord tones are ringed in gold. Gives the standard five pentatonic boxes and 2–3 notes per string for 7-note scales. Minor scales use the minor shapes. Needs a 6-string tuning in standard intervals (E, E♭ and D standard, and the top 6 strings of a 7- or 8-string).
  - *3NPS:* one fingering starting on each scale degree with exactly three notes per string (two for pentatonics and other scales with fewer than 7 notes). Works in any tuning.
- **Diatonic chords:** for any 7-note scale, the seven seventh chords of the key. Click one to open it in Chord mode.
- **Progression mode:**
  - Type Roman numerals (`I V vi IV`, `ii7 V7 Imaj7`, `i bVII bVI V`, `V7b9`, `vii°7` …), load one of 18 presets (pop, jazz ii–V–I, 12-bar blues, Andalusian, Canon …), or click diatonic triads or sevenths from any 7-note scale to add them.
  - Each chord gets a voicing chosen for smooth voice leading near a fret you set, optionally using inversions. Slash chords are labelled.
  - Playback has tempo, beats per chord and loop settings, and the fretboard follows along as it plays.
- **Display:**
  - Labels: note names, intervals, scale degrees, or none.
  - Colours: *Chord Tones* (root, 3rd, 5th and 7th coloured, other notes neutral; the default), *Spectrum* (one colour per degree), or *Root Only*. A legend under the fretboard explains them.
  - Click a note tile to hide or show that note on the neck. Hover a fret to see its note, interval, string and fret in the status line.
  - Notes outside the current position or voicing can be dimmed or hidden, and all chromatic notes can be shown.
- **Instrument:** 16 tunings (standard, drop tunings, open tunings, DADGAD, all fourths, 7- and 8-string, bass, ukulele), 12–24 frets, left-handed mode.
- **Sound:** real sampled guitars from the General MIDI sound bank built into macOS: steel-string (default), nylon, jazz, clean, muted and overdriven electric, chosen under *Sound → Instrument*. Bass tunings switch to fingered bass. Click any fret to hear the note, or press Space to play the scale run, strum the voicing or play the progression. Notes are timed by an `AVAudioSequencer`. A plucked-string synth is also available, and is used automatically if the samples can't be loaded.
- **PDF export:**
  - *This View* (⌘E) saves one page with the title, the notes and their intervals, the grip, and a high-resolution Metal render of the fretboard.
  - *All…* (⇧⌘E) saves a multi-page sheet with two diagrams per page: every scale position (Boxes, CAGED or 3NPS), every CAGED chord shape, the first 30 voicings, every inversion, or every chord of the progression.
  - Both are in the File menu and the toolbar's Export button.
  - *Print-Friendly* (on by default) renders the diagrams on white, with a light fretboard and dark strings and labels, to save ink. Turn it off to export the dark on-screen look.
- **Mac-native layout:** the Scale / Chord / Progression switch, Export and Play are in the window toolbar; all settings are in the sidebar.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| Space (or ⌘↩) | Play / stop |
| ⌘1 / ⌘2 / ⌘3 | Scale / Chord / Progression mode |
| ⌘← / ⌘→ | Key down / up a semitone |
| ⌘↑ / ⌘↓ | Key up / down a fifth |
| ⌥← / ⌥→ | Previous / next position, voicing, CAGED shape or progression chord |
| ⇧⌘C | Switch to CAGED view |
| ⌘E / ⇧⌘E | Export view / export all as PDF |
| ⇧⌘I | Next inversion |
| ⇧⌘N / ⇧⌘T | Show note names / intervals |

## Source layout

| File | Purpose |
|---|---|
| `Theory.swift` | Notes, intervals, enharmonic spelling |
| `Library.swift` | Scales, modes, chords, tunings |
| `Voicings.swift` | Playable chord-voicing search |
| `CAGED.swift` | CAGED shape templates and placement |
| `Progression.swift` | Roman-numeral parser and progression presets |
| `AppState.swift` | Selection state, fretboard model, playback |
| `Renderer.swift`, `Shaders.swift` | Metal renderer and MSL shaders |
| `LabelAtlas.swift` | CoreText → Metal glyph atlas |
| `FretboardLayout.swift` | Geometry, hit-testing, colour palette |
| `Views.swift` | SwiftUI sidebar, header and info panel |
| `PDFExport.swift` | Off-screen render → PDF sheets |
| `Audio.swift` | Sampler + MIDI sequencer playback, Karplus–Strong fallback |
