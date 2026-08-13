import UIKit

/// Haptic feedback, fired from the same place as the sound effects. Deliberately sparse — only the
/// player's own taps and the win/lose punctuation buzz; the frequent game-driven cues (a train
/// boarding, departing, a crossing bell) stay silent so the phone isn't rattling non-stop.
/// Independent of the sound mute, with its own persisted on/off. A fresh, freshly-prepared generator
/// is used per hit — the most reliable way to make the Taptic Engine actually fire.
final class Haptics {
    static let shared = Haptics()
    private(set) var enabled = UserDefaults.standard.object(forKey: "btr.haptics") as? Bool ?? true

    private init() {}

    func toggle() {
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: "btr.haptics")
        if enabled { fire(for: .tap) }        // a confirming buzz the moment it's switched on
    }

    func fire(for fx: Sound.FX) {
        guard enabled else { return }
        let run = {
            switch fx {
            case .tap:                          // throwing a signal — the main control; a firm knock
                let g = UIImpactFeedbackGenerator(style: .rigid); g.prepare(); g.impactOccurred(intensity: 1.0)
            case .ui:                           // menu / tile presses
                let g = UIImpactFeedbackGenerator(style: .light); g.prepare(); g.impactOccurred(intensity: 0.8)
            case .win:
                let g = UINotificationFeedbackGenerator(); g.prepare(); g.notificationOccurred(.success)
            case .lose:
                let g = UINotificationFeedbackGenerator(); g.prepare(); g.notificationOccurred(.error)
            default: break                      // board/depart/ding/star: no buzz
            }
        }
        Thread.isMainThread ? run() : DispatchQueue.main.async(execute: run)
    }
}
