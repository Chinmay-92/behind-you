import AVFoundation

/// Every sound is synthesized at runtime — no audio files.
final class Sound {
    private let engine = AVAudioEngine()
    private let fx = AVAudioPlayerNode()
    private let heart = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private let enabled: Bool
    private var voice: Process?

    init(enabled: Bool) {
        self.enabled = enabled
        guard enabled else { return }
        for node in [fx, heart] {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        do { try engine.start() } catch { log("audio unavailable: \(error.localizedDescription)") }
    }

    private func render(_ seconds: Double, _ f: (Double) -> Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * format.sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let l = buf.floatChannelData![0], r = buf.floatChannelData![1]
        for i in 0..<Int(n) {
            let v = Float(f(Double(i) / format.sampleRate))
            l[i] = v
            r[i] = v
        }
        return buf
    }

    /// Starts (or speeds up) a heartbeat.
    func heartbeat(bpm: Double) {
        guard enabled, engine.isRunning else { return }
        let thump = { (t: Double) -> Double in
            guard t >= 0 else { return 0 }
            return sin(2 * .pi * 46 * t) * exp(-t * 16) + 0.35 * sin(2 * .pi * 92 * t) * exp(-t * 28)
        }
        let beat = render(60 / bpm) { t in 0.9 * (thump(t) + 0.7 * thump(t - 0.26)) }
        heart.scheduleBuffer(beat, at: nil, options: [.loops, .interrupts])
        heart.play()
    }

    func stopHeartbeat() { heart.stop() }

    /// A low, wrong-sounding swell when it notices you looked back.
    func sting() {
        guard enabled, engine.isRunning else { return }
        let buf = render(1.6) { t in
            let env = min(t / 0.05, 1) * exp(-t * 2.2)
            let f = 55 - 18 * t
            return 0.55 * env * (sin(2 * .pi * f * t) + 0.4 * sin(2 * .pi * f * 1.06 * t) + 0.15 * Double.random(in: -1...1))
        }
        fx.scheduleBuffer(buf, at: nil, options: [.interrupts])
        fx.play()
    }

    func scream() {
        guard enabled, engine.isRunning else { return }
        var phases = [0.0, 0.0, 0.0]
        let detune = [1.0, 1.013, 1.49]
        let dt = 1 / format.sampleRate
        let buf = render(2.0) { t in
            let env = min(t / 0.015, 1) * (t < 1.4 ? 1 - t * 0.2 : max(0, (2.0 - t) / 0.6) * 0.72)
            let base = 760 + 520 * t + 45 * sin(2 * .pi * 7.5 * t)
            var s = 0.0
            for i in 0..<3 {
                phases[i] += base * detune[i] * dt
                s += 2 * (phases[i] - floor(phases[i])) - 1
            }
            let boom = sin(2 * .pi * 38 * t) * exp(-t * 5) * 2
            let noise = Double.random(in: -1...1) * 0.6
            return 0.42 * env * tanh(1.8 * (s / 3 + noise + boom))
        }
        fx.scheduleBuffer(buf, at: nil, options: [.interrupts])
        fx.play()
    }

    /// Uses the system "Whisper" voice.
    func whisper(_ text: String, volume: Double = 0.6) {
        guard enabled else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", "Whisper", "-r", "120", "[[volm \(volume)]] \(text)"]
        try? p.run()
        voice = p
    }

    func stop() {
        voice?.terminate()
        heart.stop()
        fx.stop()
        engine.stop()
    }
}
