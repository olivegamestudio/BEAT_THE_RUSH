import SwiftUI

// MARK: - RailKit · piece 3 — the movement engine
//
// The shared kinematics every level was re-implementing: each tick, work out how far a train may
// advance — the min of the end of its road, the tail of the train ahead on its lane, and whatever the
// level says is holding it — then ease its speed toward that (brake smoothly to a stand, accelerate
// away when it clears) and move it. The sim never knows what a "platform" or a "bridge" is; the
// level's own rules plug in through a handful of hooks.

/// A train the sim moves along its path. Levels subclass this to hang their own state (which
/// platform, whether it's boarded, …) while the sim drives `dist`, `v` and `railAspect`.
class RailVehicle: Identifiable {
    let id = UUID()
    var spec: Train
    var path: RoutePath
    var lane: Int              // trains on the same lane queue behind each other (built-in following)
    var dist: CGFloat = 0      // head arc-length along the path
    var v: CGFloat = 0         // current speed, eased tick to tick
    var railAspect = 0         // 0 green · 1 amber · 2 red — lights the road just ahead
    var blocked = false        // held short of something this tick
    var stopped = 0.0          // seconds sat still at a stand (drives the "waiting" bubble)
    var finished = false       // reached the end of its run; removed after the tick

    init(spec: Train, path: RoutePath, lane: Int = 0) {
        self.spec = spec; self.path = path; self.lane = lane
    }

    var carLen: CGFloat { spec.carLength }

    /// The x-extent this train covers on its line right now (head and tail) — for block occupancy.
    var xExtent: ClosedRange<CGFloat> {
        let fx = path.sample(dist).p.x
        let rx = path.sample(max(0, dist - carLen)).p.x
        return min(fx, rx)...max(fx, rx)
    }
}

/// The feel of the running: a top speed, and how hard trains pull away and brake.
struct RailKinematics {
    var speedCap: CGFloat
    var accel: CGFloat
    var decel: CGFloat
    var followGap: CGFloat
    init(speedCap: CGFloat, accel: CGFloat = 200, decel: CGFloat = 300,
         followGap: CGFloat = Track.carUnit * 1.15) {
        self.speedCap = speedCap; self.accel = accel; self.decel = decel; self.followGap = followGap
    }
}

/// How a vehicle keeps clear of the ones ahead. `.lane` — queue behind the nearest train on the same
/// lane (simple parallel running: Saltash's approaches, Newark's two lines, …). `.bodyAhead` — hold clear
/// of any train whose *body* lies across the road just ahead, wherever the throat roads weave across each
/// other (crossing moves through a full ladder: Birmingham, Crewe); `reach` is how far to look ahead,
/// `clear` the clearance kept from another train's body.
enum FollowMode {
    case lane
    case bodyAhead(reach: CGFloat, clear: CGFloat)
}

/// The engine. Owns the trains, advances them each tick, and calls the level's hooks. Generic over
/// the vehicle type so a level gets its own train class back from `vehicles`, fully typed.
final class RailSim<V: RailVehicle> {
    var vehicles: [V] = []
    var kin: RailKinematics
    /// How following is resolved — lane-queue (default) or position-based body-ahead for weaving throats.
    var followMode: FollowMode = .lane

    /// Extra movement authority from the level: the furthest arc-length `t` may reach given the
    /// current roster — held signals, a bridge/crossing resource, a platform berth, and so on. The
    /// sim mins this with its own limits; return `.infinity` for "nothing extra holding it".
    var ceiling: ((V, [V]) -> CGFloat)?
    /// A per-tick speed cap — easing to caution at an amber, say. Return the cap, or `.infinity`.
    var speedLimit: ((V) -> CGFloat)?
    /// Per-vehicle kinematics override — when a level mixes stock with different feel (a fast express
    /// vs a gentle local), return that vehicle's speed/accel/decel/gap. Defaults to the sim's `kin`.
    var kinematics: ((V) -> RailKinematics)?
    /// Extra arc-length a vehicle may run past the end of its path before finishing, so a long train's
    /// tail clears the visible end rather than the whole set vanishing at once. Defaults to 0.
    var overrun: ((V) -> CGFloat)?
    /// Run after a vehicle has advanced this tick: boarding, grabbing or freeing a resource, …
    var onAdvance: ((V, Double) -> Void)?
    /// Has this vehicle finished its run? Defaults to "its head reached the end of its path".
    var isFinished: ((V) -> Bool)?
    /// Called when a vehicle finishes, just before it's removed from the roster.
    var onFinish: ((V) -> Void)?

    init(kin: RailKinematics) { self.kin = kin }

    /// The built-in following limit: the tail of the nearest train ahead on the same lane, less the
    /// follow gap — so a train never runs into the back of the one in front on its own road.
    private func followCeiling(_ t: V, _ roster: [V], _ k: RailKinematics) -> CGFloat {
        switch followMode {
        case .lane:
            var aheadTail = CGFloat.infinity
            for o in roster where o !== t && !o.finished && o.lane == t.lane && o.dist > t.dist {
                aheadTail = min(aheadTail, o.dist - o.carLen)
            }
            return aheadTail.isFinite ? aheadTail - k.followGap : .infinity
        case .bodyAhead(let reach, let clear):
            let d = bodyAheadCeiling(t, roster, reach: reach, clear: clear)
            return d.isFinite ? d - k.followGap : .infinity
        }
    }

    /// Walk forward along `t`'s own road; return the arc-length at which its nose first closes within
    /// `clear` of any train physically ahead of it (by progress, ties broken by id) — whatever road or
    /// platform that train is heading for. Comparing real positions is what stops trains overlapping where
    /// the throat roads weave across each other. `.infinity` if the road is clear for `reach`.
    private func bodyAheadCeiling(_ t: V, _ roster: [V], reach: CGFloat, clear: CGFloat) -> CGFloat {
        var d = t.dist + 7
        let end = t.dist + reach
        while d <= end {
            let p = t.path.sample(d).p
            for o in roster where o !== t && !o.finished {
                let oAhead = o.dist > t.dist || (o.dist == t.dist && o.id.hashValue > t.id.hashValue)
                if oAhead && bodyNear(o, p, within: clear) { return d - 7 }
            }
            d += 7
        }
        return .infinity
    }
    /// True if any point along `o`'s body (nose back to tail) lies within `r` of `p`.
    private func bodyNear(_ o: V, _ p: CGPoint, within r: CGFloat) -> Bool {
        var d = o.dist
        let tail = o.dist - o.carLen
        while d >= tail {
            let q = o.path.sample(d).p
            if hypot(q.x - p.x, q.y - p.y) < r { return true }
            d -= 18
        }
        return false
    }

    func step(_ dt: Double) {
        let roster = vehicles
        for t in roster where !t.finished {
            let k = kinematics?(t) ?? kin                       // this vehicle's feel (may differ per stock)
            let end = t.path.total + (overrun?(t) ?? 0)         // it may run a little past the path end
            // How far the train is allowed to reach: the end of its road, the train ahead, the level.
            var cap = min(end, followCeiling(t, roster, k))
            if let extra = ceiling?(t, roster) { cap = min(cap, extra) }
            if cap < 0 { cap = 0 }

            // Ease v: brake so as to come to a stand exactly at the ceiling (v² = 2·decel·headroom),
            // but never above the top speed or the tick's caution cap. Accelerate up to the target,
            // decelerate down to it — so a train screeches to a stand at a red and pulls away after.
            let headroom = max(0, cap - t.dist)
            let brakeV = (2 * k.decel * headroom).squareRoot()
            let caution = min(speedLimit?(t) ?? .infinity, k.speedCap)
            let target = min(brakeV, caution)
            if t.v < target { t.v = min(target, t.v + k.accel * CGFloat(dt)) }
            else { t.v = max(target, t.v - k.decel * CGFloat(dt)) }
            if t.v < 0 { t.v = 0 }

            let next = min(t.dist + t.v * CGFloat(dt), cap)
            t.blocked = next <= t.dist + 0.01 && cap < end - 1
            t.stopped = t.blocked ? t.stopped + dt : 0
            t.dist = max(t.dist, next)

            // Light the road ahead: green if it can run clear to the end, red as it stops, amber when
            // it's closing on something or under caution.
            t.railAspect = railAspect(headroom: cap - t.dist,
                                      clearToEnd: cap >= t.path.total - 1,
                                      amber: caution < k.speedCap)
            onAdvance?(t, dt)

            if isFinished?(t) ?? (t.dist >= end) {
                t.finished = true
                onFinish?(t)
            }
        }
        vehicles.removeAll { $0.finished }
    }
}
