import CoreHaptics
import UIKit

/// Haptic feedback, fired from the same place as the sound effects. Uses **Core Haptics** — the robust
/// engine that isn't muffled by the app's active audio session the way a plain feedback generator can
/// be — with a `UIImpactFeedbackGenerator` fallback if the hardware or engine is unavailable.
///
/// Deliberately sparse: only the player's own taps and the win/lose punctuation buzz; the frequent
/// game cues (boarding, departing, a crossing bell) stay silent. Independent of the sound mute, with
/// its own persisted on/off.
final class Haptics {
    static let shared = Haptics()
    private let supports = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private(set) var enabled = UserDefaults.standard.object(forKey: "btr.haptics") as? Bool ?? true

    private init() {
        guard supports else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    func toggle() {
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: "btr.haptics")
        if enabled { fire(for: .tap) }        // a confirming buzz the moment it's switched on
    }

    func fire(for fx: Sound.FX) {
        guard enabled else { return }
        switch fx {
        case .tap:  transient(intensity: 1.0, sharpness: 0.9)   // throwing a signal — a firm knock
        case .ui:   transient(intensity: 0.6, sharpness: 0.4)   // menu / tile presses
        case .win:  transient(intensity: 0.9, sharpness: 0.6)
        case .lose: transient(intensity: 1.0, sharpness: 0.2)   // a duller thud
        default:    break                                       // board/depart/ding/star: no buzz
        }
    }

    private func transient(intensity: Float, sharpness: Float) {
        if supports, let engine {
            do {
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ], relativeTime: 0)
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                try engine.start()
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                return
            } catch {
                // fall through to the generator
            }
        }
        let run = {
            let g = UIImpactFeedbackGenerator(style: .rigid); g.prepare(); g.impactOccurred(intensity: CGFloat(intensity))
        }
        Thread.isMainThread ? run() : DispatchQueue.main.async(execute: run)
    }
}
