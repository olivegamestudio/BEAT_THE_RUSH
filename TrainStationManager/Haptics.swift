import UIKit

/// Haptic feedback, fired from the same place as the sound effects. Deliberately sparse — only the
/// player's own taps and the win/lose punctuation buzz; the frequent game-driven cues (a train
/// boarding, departing, a crossing bell) stay silent so the phone isn't rattling non-stop.
/// Independent of the sound mute — a muted game can still be felt.
final class Haptics {
    static let shared = Haptics()
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notify = UINotificationFeedbackGenerator()

    private init() { light.prepare(); soft.prepare(); notify.prepare() }

    func fire(for fx: Sound.FX) {
        switch fx {
        case .tap:  light.impactOccurred(intensity: 0.75); light.prepare()   // tapping a signal — the main control
        case .ui:   soft.impactOccurred(intensity: 0.6); soft.prepare()      // menu / button taps
        case .win:  notify.notificationOccurred(.success); notify.prepare()
        case .lose: notify.notificationOccurred(.error); notify.prepare()
        default:    break                                                    // board/depart/ding/star: no buzz
        }
    }
}
