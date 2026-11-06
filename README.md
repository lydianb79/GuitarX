# GuitarX — Fretboard Navigator

A native macOS app (SwiftUI + Metal) that renders a guitar fretboard and shows any scale, mode or chord/inversion on it.

## Build & run

Requires macOS 14+ and Xcode 15+ (or the Xcode Command Line Tools).

```bash
cd ~/Desktop/GuitarX
chmod +x build-app.sh
./build-app.sh
open build/GuitarX.app
```

Or open `Package.swift` in Xcode and press ⌘R.

## Features

- **Metal renderer.** Every element is an instanced quad drawn with a signed-distance-field shader: procedural rosewood/ebony/maple grain, pearl inlays, metallic frets, wound and plain strings, glossy note markers with glow, and text drawn from a CoreText glyph atlas. Fret spacing follows real equal temperament, blended so the high frets stay usable. Markers animate in when the selection changes.
- **Scales & modes (~60), in all 12 keys:** the modes of major, melodic minor, harmonic minor, harmonic major and double harmonic; pentatonics and blues; bebop; symmetric scales; and exotic scales. Note names are spelled correctly for the key (e.g. G♯ harmonic minor gives F𝄪, shown as F♯♯).
- **Chords (~50) with every inversion:** triads, 6ths, 7ths, added-tone chords, 9ths, 11ths, 13ths and altered dominants.
  - *Voicings* mode finds playable grips for the chosen inversion (the lowest note is the inversion's bass) across the whole neck, and lets you filter by number of strings. For example, choose 3 strings to study triad inversions on each string set.
  - *All Tones* mode shows every chord tone on the neck, with the bass note ringed.
- **CAGED system:**
  - *Scale mode:* positions can be 5-fret boxes or the five CAGED shapes in neck order. The notes of the shape's chord get a gold ring. Minor scales use the minor CAGED shapes.
  - *Chord mode:* a third view next to *Voicings* and *All Tones* shows the exact C·A·G·E·D grips for major, minor, 7, maj7 and m7 chords. For other chord types it shows the chord tones inside each shape's area of the neck.
  - Works in any tuning whose 6 strings follow standard intervals (E, E♭ and D standard, and the top 6 strings of a 7- or 8-string).
- **3-notes-per-string (3NPS):** a third position system next to Boxes and CAGED. It gives one fingering starting on each scale degree, with exactly three notes per string (two for pentatonics and other scales with fewer than 7 notes). It works in any tuning.
- **Progression mode:**
  - Type Roman numerals (`I V vi IV`, `ii7 V7 Imaj7`, `i bVII bVI V`, `V7b9`, `vii°7` …), load one of 18 presets (pop, jazz ii–V–I, 12-bar blues, Andalusian, Canon …), or click diatonic triads or 7ths from any 7-note scale to add them.
  - Each chord gets a voicing chosen for smooth voice leading near a fret you set, optionally using inversions. Slash chords are labelled.
  - Playback has tempo, beats per chord and loop settings, and the fretboard follows along as it plays.
- **Navigation:** scale positions (whole neck or 5-fret boxes), diatonic 7th chords for any 7-note scale (click one to jump to it), and note chips you can click to hide or show each interval.
- **PDF export:**
  - *This View* (⌘E) saves one page with the title, the notes and their intervals, the grip, and a high-resolution Metal render of the fretboard.
  - *All…* (⇧⌘E) saves a multi-page sheet with two diagrams per page: every scale position or CAGED shape, every CAGED chord shape, the first 30 voicings, every inversion, or every chord of the progression.
  - Both options are in the File menu and the toolbar's Export button.
  - *Print-Friendly* (on by default) renders the diagrams on white, with a light fretboard and dark strings and labels, to save ink. Turn it off to export the dark on-screen look.
- **Labels:** note names, intervals, scale degrees, or none. Colours follow interval function (root, 3rd, 5th, 7th, …).
- **Instrument:** 16 tunings (standard, drop tunings, open tunings, DADGAD, 7- and 8-string, bass, ukulele), 12–24 frets, left-handed mode.
- **Sound:** real sampled guitars from the General MIDI sound bank built into macOS: steel-string, nylon, jazz, clean, muted and overdriven electric. Bass tunings switch to fingered bass. Click any fret to hear the note, or press Space to play the scale run, strum the voicing or play the progression. Notes are timed by an `AVAudioSequencer`. A plucked-string synth is still available, and is used automatically if the samples can't be loaded.

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
