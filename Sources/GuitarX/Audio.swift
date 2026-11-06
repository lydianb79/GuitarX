import AVFoundation

struct SynthNote {
    let midi: Int
    let time: Double
    var length: Double = 4.5
}

/// Tiny Karplus–Strong plucked-string synth so you can hear what you see.
final class GuitarSynth {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let reverb = AVAudioUnitReverb()
    private let sampleRate: Double = 44_100
    private let format: AVAudioFormat
    private let queue = DispatchQueue(label: "GuitarX.synth", qos: .userInitiated)

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(player)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 16
        engine.connect(player, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
    }

    func play(_ notes: [SynthNote]) {
        guard !notes.isEmpty else { return }
        queue.async { [weak self] in self?.render(notes) }
    }

    func stop() {
        queue.async {
            DispatchQueue.main.async { [self] in player.stop() }
        }
    }

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
