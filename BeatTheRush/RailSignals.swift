import SwiftUI

// MARK: - RailKit · piece 2 — signals as types
//
// One tested implementation of each signal kind, instead of a bespoke copy per level. Each signal
// owns the stretch it protects and computes its own aspect from occupancy; the level only has to
// place it and, each tick, hand it a test of what's occupied.

/// An automatic three-aspect block signal (0 green · 1 amber · 2 red). It protects the block of
/// track just beyond it: **red** while that block is occupied, **amber** while the *next* signal's
/// block is occupied (a caution to the queue building ahead), **green** otherwise — so the queue
/// itself, trains stacking up behind one another, is what turns the approach red.
///
/// It deliberately knows nothing about trains: the level hands `update` an occupancy test over a
/// 1-D stretch of the line, so the same signal serves any axis-aligned running line (Saltash's two
/// approaches, Lostwithiel's lanes, …). A block is described by where the signal sits (`axis`), which
/// way it faces (`forward`), and how long the block is (`blockLen`).
final class BlockSignal {
    let id: String
    let at: CGPoint             // foot on the track, where it's drawn
    let axis: CGFloat           // the signal's position along the line (x, for a horizontal line)
    let forward: CGFloat        // +1 protects the stretch to the right of `axis`, -1 to the left
    let blockLen: CGFloat
    weak var next: BlockSignal? // the next signal down the line — its block is the amber look-ahead
    private(set) var aspect = 0

    init(_ id: String, at: CGPoint, axis: CGFloat, forward: CGFloat, blockLen: CGFloat) {
        self.id = id; self.at = at; self.axis = axis; self.forward = forward; self.blockLen = blockLen
    }

    /// The stretch of line this signal's block covers.
    var block: ClosedRange<CGFloat> {
        forward >= 0 ? axis...(axis + blockLen) : (axis - blockLen)...axis
    }

    /// Recompute the aspect from a test that says whether a given stretch of the line is occupied.
    func update(_ occupied: (ClosedRange<CGFloat>) -> Bool) {
        if occupied(block) { aspect = 2 }
        else if let n = next, occupied(n.block) { aspect = 1 }
        else { aspect = 0 }
    }
}

/// A player-tappable hold signal — the lever the player pulls to clear a route or a direction
/// (Saltash's bridge portals, Lostwithiel's single-line pass). It latches the player's *intent*
/// (`cleared`); whether a train may actually move is the level's call — usually `cleared` **and** the
/// section it protects is free — which keeps the resource logic in one obvious place rather than
/// buried in the signal.
final class HoldSignal {
    let id: String
    let at: CGPoint
    var cleared: Bool

    init(_ id: String, at: CGPoint, cleared: Bool = false) {
        self.id = id; self.at = at; self.cleared = cleared
    }

    func toggle() { cleared.toggle() }
}

/// A set of hold signals where clearing one holds the rest — a radio group. Saltash's single-line
/// bridge is exactly this: only one direction is ever cleared onto it, so the two take turns.
final class HoldGroup {
    private(set) var signals: [HoldSignal]
    /// The id of the currently-cleared signal, or `nil` when everything is held.
    private(set) var granted: String?

    init(_ signals: [HoldSignal]) { self.signals = signals }

    /// Tap `id`: clear it (holding the others), or hold everything if it was already the cleared one.
    func toggle(_ id: String) { grant(granted == id ? nil : id) }

    /// Force the granted signal (used to set an initial state or reset).
    func grant(_ id: String?) {
        granted = id
        for s in signals { s.cleared = (s.id == id) }
    }

    func isCleared(_ id: String) -> Bool { granted == id }
}
