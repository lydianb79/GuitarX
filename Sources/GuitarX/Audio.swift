import AVFoundation
import AudioToolbox

struct SynthNote {
    let midi: Int
    let time: Double
    var length: Double = 4.5
}

/// Playback sound. Sampled tones use the General MIDI guitar samples that ship with macOS.
enum GuitarTone: String, CaseIterable, Identifiable {
    case steel = "Steel-String Acoustic"
    case nylon = "Nylon-String Classical"
    case jazz = "Jazz Electric"
    case clean = "Clean Electric"
    case muted = "Muted Electric"
    case overdrive = "Overdriven Electric"
    case synth = "Plucked Synth"

    var id: String { rawValue }

    /// General MIDI program number (0-based), nil for the built-in synth.
    var program: UInt8? {
        switch self {
        case .nylon: return 24
        case .steel: return 25
        case .jazz: return 26
        case .clean: return 27
        case .muted: return 28
        case .overdrive: return 29
        case .synth: return nil
        }
    }

    static let fingeredBass: UInt8 = 33
}

/// Plays notes either through Apple's sampler (real recorded guitars) or a Karplus–Strong fallback synth.
final class GuitarSynth {
    static let soundBankURL = URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampler = AVAudioUnitSampler()
    private let submix = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private lazy var sequencer = AVAudioSequencer(audioEngine: engine)
    private let sampleRate: Double = 44_100
    private let format: AVAudioFormat
    private let queue = DispatchQueue(label: "GuitarX.synth", qos: .userInitiated)

    private var loadedProgram: UInt8? = nil
    private var noteTokens: [UInt8: Int] = [:]
    private var tokenCounter = 0
    private(set) var samplesAvailable = FileManager.default.fileExists(atPath: GuitarSynth.soundBankURL.path)

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(player)
        engine.attach(sampler)
        engine.attach(submix)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 14
        engine.connect(player, to: submix, fromBus: 0, toBus: 0, format: format)
        engine.connect(sampler, to: submix, fromBus: 0, toBus: 1, format: nil)
        engine.connect(submix, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    // MARK: Public

    /// Loads a sampled instrument ahead of time so the first note isn't delayed.
    func preload(program: UInt8?) {
        guard let program else { return }
        _ = loadProgram(program)
    }

    /// Plays notes with the given GM program (nil = plucked synth).
    func play(_ notes: [SynthNote], program: UInt8?) {
        guard !notes.isEmpty else { return }
        if let program, loadProgram(program), ensureRunning() {
            playSampled(notes)
        } else {
            queue.async { [weak self] in self?.render(notes) }
        }
    }

    func stop() {
        stopSequence()
        allNotesOff()
        queue.async {
            DispatchQueue.main.async { [self] in player.stop() }
        }
    }

    // MARK: Sampler

    private func ensureRunning() -> Bool {
        if engine.isRunning { return true }
        do {
            try engine.start()
            return true
        } catch {
            NSLog("GuitarX audio error: \(error)")
            return false
        }
    }

    private func loadProgram(_ program: UInt8) -> Bool {
        guard samplesAvailable else { return false }
        if loadedProgram == program { return true }
        do {
            try sampler.loadSoundBankInstrument(at: GuitarSynth.soundBankURL, program: program,
                                                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                                                bankLSB: UInt8(kAUSampler_DefaultBankLSB))
            loadedProgram = program
            return true
        } catch {
            NSLog("GuitarX: could not load guitar samples (\(error)); using the synth instead")
            samplesAvailable = false
            return false
        }
    }

    private func playSampled(_ notes: [SynthNote]) {
        stopSequence()

        // A single click: play it immediately and let other strings keep ringing.
        if notes.count == 1, notes[0].time == 0 {
            let n = notes[0]
            let key = UInt8(clamping: n.midi)
            sampler.stopNote(key, onChannel: 0)
            sampler.startNote(key, withVelocity: 100, onChannel: 0)
            tokenCounter += 1
            let token = tokenCounter
            noteTokens[key] = token
            DispatchQueue.main.asyncAfter(deadline: .now() + min(n.length, 3.5)) { [weak self] in
                guard let self, self.noteTokens[key] == token else { return }
                self.sampler.stopNote(key, onChannel: 0)
            }
            return
        }

        allNotesOff()
        guard let data = GuitarSynth.midiData(for: notes) else { return }
        do {
            try sequencer.load(from: data, options: [])
            for track in sequencer.tracks { track.destinationAudioUnit = sampler }
            sequencer.currentPositionInSeconds = 0
            sequencer.prepareToPlay()
            try sequencer.start()
        } catch {
            NSLog("GuitarX sequencer error: \(error)")
        }
    }

    private func stopSequence() {
        if sequencer.isPlaying { sequencer.stop() }
    }

    private func allNotesOff() {
        noteTokens.removeAll()
        for key in UInt8(0)...UInt8(127) { sampler.stopNote(key, onChannel: 0) }
    }

    /// Builds a one-track Standard MIDI File at 60 BPM, so beats equal seconds.
    private static func midiData(for notes: [SynthNote]) -> Data? {
        var seqRef: MusicSequence?
        guard NewMusicSequence(&seqRef) == noErr, let seq = seqRef else { return nil }
        defer { _ = DisposeMusicSequence(seq) }

        var tempoRef: MusicTrack?
        if MusicSequenceGetTempoTrack(seq, &tempoRef) == noErr, let tempo = tempoRef {
            _ = MusicTrackNewExtendedTempoEvent(tempo, 0, 60)
        }
        var trackRef: MusicTrack?
        guard MusicSequenceNewTrack(seq, &trackRef) == noErr, let track = trackRef else { return nil }

        for n in notes {
            var msg = MIDINoteMessage(channel: 0,
                                      note: UInt8(clamping: n.midi),
                                      velocity: UInt8.random(in: 86...106),
                                      releaseVelocity: 0,
                                      duration: Float32(max(0.05, min(n.length, 4.0))))
            _ = MusicTrackNewMIDINoteEvent(track, MusicTimeStamp(max(0, n.time)), &msg)
        }

        var out: Unmanaged<CFData>?
        guard MusicSequenceFileCreateData(seq, .midiType, .eraseFile, 480, &out) == noErr,
              let cf = out?.takeRetainedValue() else { return nil }
        return cf as Data
    }

    // MARK: Karplus–Strong fallback

    private func render(_ notes: [SynthNote]) {
        let total = notes.map { $0.time + min($0.length, 2.4) }.max() ?? 2.4
        let frames = Int(total * sampleRate)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(frames)

        var mix = [Float](repeating: 0, count: frames)
        for n in notes {
            pluck(&mix, start: Int(n.time * sampleRate), midi: n.midi, length: n.length)
        }
        var peak: Float = 0.0001
        for v in mix { peak = max(peak, abs(v)) }
        let gain = min(1.0, 0.8 / peak)
        let left = channels[0]
        let right = channels[1]
        for i in 0..<frames {
            let v = tanh(mix[i] * gain * 1.1)
            left[i] = v
            right[i] = v
        }

        DispatchQueue.main.async { [self] in
            if !engine.isRunning {
                do { try engine.start() } catch {
                    NSLog("GuitarX audio error: \(error)")
                    return
                }
            }
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    private func pluck(_ out: inout [Float], start: Int, midi: Int, length noteLength: Double) {
        guard start >= 0, start < out.count else { return }
        let freq = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        let period = sampleRate / freq - 0.5          // the averaging filter adds half a sample
        var n = Int(period.rounded(.down))
        var frac = period - Double(n)
        if frac < 0.1 { n -= 1; frac += 1 }
        n = max(n, 2)
        let c = Float((1 - frac) / (1 + frac))        // all-pass for fractional delay (tuning accuracy)

        var line = [Float](repeating: 0, count: n)
        var lp: Float = 0
        for i in 0..<n {
            lp += (Float.random(in: -1...1) - lp) * 0.55
            line[i] = lp
        }
        let mean = line.reduce(0, +) / Float(n)
        for i in 0..<n { line[i] -= mean }

        let t60 = max(1.2, 3.6 - 2.2 * min(1.0, max(0, freq - 80) / 900))
        let loss = Float(pow(0.001, 1.0 / (t60 * freq)))
        let length = min(out.count - start, Int(sampleRate * min(noteLength, 4.5)))
        let fade = min(length, Int(sampleRate * 0.08))
        var idx = 0
        var apX: Float = 0
        var apY: Float = 0
        for i in 0..<length {
            let a = line[idx]
            let b = line[idx + 1 < n ? idx + 1 : 0]
            let avg = loss * 0.5 * (a + b)
            let y = c * avg + apX - c * apY
            apX = avg
            apY = y
            line[idx] = y
            idx += 1
            if idx == n { idx = 0 }
            var gain: Float = 0.32
            if i > length - fade { gain *= Float(length - i) / Float(max(fade, 1)) }
            out[start + i] += a * gain
        }
    }
}
