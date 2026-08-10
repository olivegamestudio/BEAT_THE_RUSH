import AVFoundation

/// A tiny synthesised sound layer. Every effect is generated in code at launch — no audio files —
/// and played through a small pool of nodes so effects can overlap. Respects a persisted mute.
final class Sound {
    static let shared = Sound()
    enum FX { case tap, ui, board, depart, ding, star, win, lose }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [FX: AVAudioPCMBuffer] = [:]
    private let sr = 44100.0
    private(set) var muted = UserDefaults.standard.bool(forKey: "btr.muted")

    private init() {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        for _ in 0..<8 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: fmt)
            players.append(p)
        }

        buffers[.tap] = render(0.06) { t in env(t, 0.06, a: 0.002, r: 0.055) * 0.5 * sin(2 * .pi * 760 * t) }
        buffers[.ui]  = render(0.05) { t in env(t, 0.05, a: 0.002, r: 0.045) * 0.4 * sin(2 * .pi * 600 * t) }
        buffers[.board] = render(0.20) { t in
            env(t, 0.20, a: 0.006, r: 0.18) * 0.32 * (sin(2 * .pi * 700 * t) + 0.5 * sin(2 * .pi * 1050 * t))
        }
        buffers[.star] = render(0.16) { t in
            env(t, 0.16, a: 0.002, r: 0.14) * 0.28 * (sin(2 * .pi * 1500 * t) + 0.4 * sin(2 * .pi * 2300 * t))
        }
        // the level-crossing bell: one short, bright ding
        buffers[.ding] = render(0.26) { t in
            let e = exp(-t * 12)
            return e * 0.26 * (sin(2 * .pi * 700 * t) + 0.4 * sin(2 * .pi * 1400 * t))
        }
        // a soft descending toot as a train leaves — no harsh noise
        buffers[.depart] = render(0.22) { t in
            let f = 300 - 90 * (t / 0.22)
            return env(t, 0.22, a: 0.01, r: 0.2) * 0.2 * (sin(2 * .pi * f * t) + 0.3 * sin(2 * .pi * f * 2 * t))
        }
        buffers[.win]  = arpeggio([523.25, 659.25, 783.99, 1046.5], step: 0.13)
        buffers[.lose] = arpeggio([392.0, 330.0, 262.0], step: 0.18)

        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, options: [.mixWithOthers])   // respects the phone's silent switch
        try? s.setActive(true)
        try? engine.start()
        players.forEach { $0.play() }
    }

    func play(_ fx: FX) {
        guard !muted, let buf = buffers[fx] else { return }
        if !engine.isRunning { try? engine.start() }
        let p = players[next]; next = (next + 1) % players.count
        p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
    }

    func toggleMute() { muted.toggle(); UserDefaults.standard.set(muted, forKey: "btr.muted") }

    // MARK: synthesis helpers

    private func arpeggio(_ notes: [Double], step: Double) -> AVAudioPCMBuffer {
        render(Double(notes.count) * step) { t in
            let idx = min(Int(t / step), notes.count - 1)
            let local = t - Double(idx) * step
            return env(local, step, a: 0.005, r: step * 0.9) * 0.3 * sin(2 * .pi * notes[idx] * t)
        }
    }

    private func render(_ dur: Double, _ f: (Double) -> Double) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let n = AVAudioFrameCount(dur * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n)!
        buf.frameLength = n
        let p = buf.floatChannelData![0]
        for i in 0..<Int(n) { p[i] = Float(f(Double(i) / sr)) }
        return buf
    }
}

/// Attack/release envelope in [0,1] over a sound of length `dur`.
private func env(_ t: Double, _ dur: Double, a: Double, r: Double) -> Double {
    if t < 0 || t > dur { return 0 }
    let atk = a > 0 ? min(t / a, 1) : 1
    let rel = r > 0 ? min((dur - t) / r, 1) : 1
    return max(0, min(atk, rel))
}
