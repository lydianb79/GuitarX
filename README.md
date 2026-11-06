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
- **Navigation:** scale positions (whole neck or 5-fret boxes), diatonic 7th chords for any 7-note scale (click one to jump to it), and note chips you can click to hide or show each interval.
- **Labels:** note names, intervals, scale degrees, or none. Colours follow interval function (root, 3rd, 5th, 7th, …).
- **Instrument:** 16 tunings (standard, drop tunings, open tunings, DADGAD, 7- and 8-string, bass, ukulele), 12–24 frets, left-handed mode.
- **Sound:** click any fret to hear the note, or press **Space** to play the scale run or strum the voicing (a built-in plucked-string synth).

## Keyboard shortcuts

| Keys | Action |
|---|---|
| Space | Play scale / chord |
| ⌘1 / ⌘2 | Scale mode / Chord mode |
| ⌘← / ⌘→ | Key down / up a semitone |
| ⌘↑ / ⌘↓ | Key up / down a fifth |
| ⌥← / ⌥→ | Previous / next position or voicing |
| ⇧⌘I | Next inversion |
| ⇧⌘N / ⇧⌘T | Show note names / intervals |

## Source layout

| File | Purpose |
|---|---|
| `Theory.swift` | Notes, intervals, enharmonic spelling |
| `Library.swift` | Scales, modes, chords, tunings |
| `Voicings.swift` | Playable chord-voicing search |
| `AppState.swift` | Selection state, fretboard model, playback |
| `Renderer.swift`, `Shaders.swift` | Metal renderer and MSL shaders |
| `LabelAtlas.swift` | CoreText → Metal glyph atlas |
| `FretboardLayout.swift` | Geometry, hit-testing, colour palette |
| `Views.swift` | SwiftUI sidebar, header and info panel |
| `Audio.swift` | Karplus–Strong guitar synth |
