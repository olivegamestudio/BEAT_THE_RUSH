import SwiftUI

/// Dawlish Warren on the sandy Exe spit. Two through tracks run across; at each end a pair of
/// points can turn a stopping train off into a platform loop and back onto the main. Expresses
/// keep to the main and race straight through.
final class DawTrain: Identifiable {
    let id = UUID()
    var spec: Train
    let dir: DawlishStation.Dir
    let express: Bool
    var steam = false            // a heritage steam special — runs straight through, never diverts
    var path: RoutePath          // main by default; switched to the loop if the points divert it
    var berthDist: CGFloat
    var onLoop = false
    var committed = false        // past the entry point — the route is locked
    let speed: CGFloat
    var dist: CGFloat = 0
    var boarded = false
    var started = false
    var dwell = 0.0
    var load = 0.0               // people already aboard — keeps topping up until the train pulls away
    var released = false          // the player has cleared the starter — free to pull out onto the main
    var departed = false          // has sounded its departure as it left the platform end
    var v: CGFloat = 0            // current speed, eased toward the target so trains glide up to and away from stops
    var stopped = 0.0            // seconds sat still at a red — drives the "waiting" bubble
    var finished = false
    var carLen: CGFloat { spec.carLength }
    init(_ spec: Train, _ dir: DawlishStation.Dir, express: Bool, _ path: RoutePath, berth: CGFloat, speed: CGFloat) {
        self.spec = spec; self.dir = dir; self.express = express
        self.path = path; berthDist = berth; self.speed = speed
    }
}

@MainActor
final class DawlishStation: ObservableObject {
    enum Dir { case east, west }
    let def: StationDef
    var name: String { def.name }

    // Geometry (design space W = 1200, H = 452)
    let upMainY: CGFloat = 262     // eastbound main (through)
    let downMainY: CGFloat = 304   // westbound main (through)
    let upLoopY: CGFloat = 218     // eastbound platform loop (above)
    let downLoopY: CGFloat = 348   // westbound platform loop (below)
    let xW: CGFloat = 322          // west points
    let xE: CGFloat = 878          // east points
    let platL: CGFloat = 424
    let platR: CGFloat = 776
    let spawnL: CGFloat = -260
    let spawnR: CGFloat = 1460

    @Published var trains: [DawTrain] = []
    @Published var carried = 0.0
    @Published var pUp = 1.0
    @Published var pDown = 1.0
    @Published var expressNearUp = false    // an express is approaching on the eastbound main — warn the player
    @Published var expressNearDown = false
    @Published var upHold = true      // platform starter: red holds a boarded train, green clears it to depart
    @Published var downHold = true
    @Published var outcome: GameOutcome = .playing
    @Published var stars = 0
    @Published var sparkles: [Sparkle] = []

    var animT = 0.0
    private var upWait = 0.0, downWait = 0.0
    let agitateAfter = 20.0
    var upAgitated: Bool { pUp >= 1 && upWait > agitateAfter }
    var downAgitated: Bool { pDown >= 1 && downWait > agitateAfter }
    private func moodFor(_ w: Double, _ p: Double) -> Mood {
        if p < 1 { return .happy }
        if w > agitateAfter { return .cross }
        if w > agitateAfter * 0.55 { return .waiting }
        return .happy
    }
    var upMood: Mood { moodFor(upWait, pUp) }
    var downMood: Mood { moodFor(downWait, pDown) }

    let baseSpeed: CGFloat = 74
    let dwellTime = 2.4
    let perCar = 3.0
    let boardOffRate = 6.0
    let platformCap = 16.0
    let overflowGrace = 18.0

    // Prebuilt routes and their berth distances.
    private let eMain, eStop, wMain, wStop: RoutePath
    private let eBerth, wBerth: CGFloat
    private var spawnClock = 0.0, nextSpawn = 1.0
    private var paxClock = 0.0, nextPax = 1.2
    private var overUp = 0.0, overDown = 0.0
    private var peakFill = 0.0

    init(_ def: StationDef) {
        self.def = def
        let d: CGFloat = 60      // how far past the points the loop has fully diverged
        eMain = RoutePath([CGPoint(x: spawnL, y: upMainY), CGPoint(x: spawnR, y: upMainY)])
        eStop = RoutePath([CGPoint(x: spawnL, y: upMainY), CGPoint(x: xW, y: upMainY),
                           CGPoint(x: xW + d, y: upLoopY), CGPoint(x: platR, y: upLoopY),
                           CGPoint(x: xE - d, y: upLoopY), CGPoint(x: xE, y: upMainY),
                           CGPoint(x: spawnR, y: upMainY)])
        eBerth = eStop.distanceTo(vertex: 3)
        wMain = RoutePath([CGPoint(x: spawnR, y: downMainY), CGPoint(x: spawnL, y: downMainY)])
        wStop = RoutePath([CGPoint(x: spawnR, y: downMainY), CGPoint(x: xE, y: downMainY),
                           CGPoint(x: xE - d, y: downLoopY), CGPoint(x: platL, y: downLoopY),
                           CGPoint(x: xW + d, y: downLoopY), CGPoint(x: xW, y: downMainY),
                           CGPoint(x: spawnL, y: downMainY)])
        wBerth = wStop.distanceTo(vertex: 3)
        spawn()
    }

    /// Flip a platform starter between hold (red) and clear (green).
    func toggleStarter(_ dir: Dir) {
        if dir == .east { upHold.toggle() } else { downHold.toggle() }
        objectWillChange.send()
    }
    /// Distance from spawn to the entry point, the same on the main and the loop (they share it).
    private func pointDist(_ dir: Dir) -> CGFloat { dir == .east ? (xW - spawnL) : (spawnR - xE) }
    /// Distance along a diverted train's loop path to where it rejoins the main (vertex 5).
    private var eExit: CGFloat { eStop.distanceTo(vertex: 5) }
    private var wExit: CGFloat { wStop.distanceTo(vertex: 5) }
    private func exitDist(_ dir: Dir) -> CGFloat { dir == .east ? eExit : wExit }
    private func exitX(_ dir: Dir) -> CGFloat { dir == .east ? xE : xW }
    /// The main signal stands at the entry point — the far end of the platform from the starter — so a red
    /// there keeps a fresh through train out of the whole single-line section while the platform pulls out.
    private func mainSignalDist(_ dir: Dir) -> CGFloat { pointDist(dir) }
    /// The interlock is driven straight off the player's starter: a platform cleared to green throws its own
    /// main signal to red, and setting the starter back to red returns the main to green at once.
    /// A released local is still crossing the junction — the main must stay shut until its whole length is
    /// clear, or flipping the starter back would loose a through train into the tail of the pulling-out local.
    private func platformCrossing(_ dir: Dir) -> Bool {
        // A released local counts as crossing until its whole length is off the loop (then it transfers to the
        // main and onLoop drops) — so the main stays shut for the entire pull-out.
        trains.contains { !$0.finished && $0.dir == dir && $0.onLoop && $0.released }
    }
    private func mainBlocked(_ dir: Dir) -> Bool {
        (dir == .east ? !upHold : !downHold) || platformCrossing(dir)
    }
    var upMainBlocked: Bool { mainBlocked(.east) }
    var downMainBlocked: Bool { mainBlocked(.west) }

    // Automatic block signals down each main. A signal is red while the block ahead of it holds any part of a
    // through train, and a following train must stop at it — front tests the signal, the leader's rear clears it.
    let blockXs: [CGFloat] = [-170, 90, 1060, 1320]
    private let blockLen: CGFloat = 250
    /// The x on the main of a through train's nose, given its distance.
    private func mainFrontX(_ o: DawTrain) -> CGFloat {
        o.dir == .east ? spawnL + o.dist : spawnR - o.dist
    }
    /// The next block signal a train meets after passing the one at `x`.
    private func nextBlockX(after x: CGFloat, _ dir: Dir) -> CGFloat? {
        dir == .east ? blockXs.filter { $0 > x + 1 }.min() : blockXs.filter { $0 < x - 1 }.max()
    }
    /// A signal's aspect: 2 = red (block ahead occupied), 1 = amber (next signal red — caution), 0 = green.
    func blockAspect(_ x: CGFloat, _ dir: Dir) -> Int {
        if blockOccupied(x, dir) { return 2 }
        if let nx = nextBlockX(after: x, dir), blockOccupied(nx, dir) { return 1 }
        return 0
    }
    /// Is the block just ahead of the signal at `x` occupied by a through train heading that way?
    func blockOccupied(_ x: CGFloat, _ dir: Dir) -> Bool {
        let east = dir == .east
        let lo = east ? x : x - blockLen
        let hi = east ? x + blockLen : x
        return trains.contains { o in
            guard !o.finished, !o.onLoop, o.dir == dir else { return false }
            let fx = mainFrontX(o)
            let rx = east ? fx - CGFloat(o.spec.length) * Track.carUnit
                          : fx + CGFloat(o.spec.length) * Track.carUnit
            return min(fx, rx) <= hi && max(fx, rx) >= lo
        }
    }
    /// Distance a through train runs to reach the loop's junction with the main.
    private func mainJunctionDist(_ dir: Dir) -> CGFloat { dir == .east ? (xE - spawnL) : (spawnR - xW) }
    /// Whether a platform train must stay put rather than pull out across the main. It waits for any express
    /// anywhere in the section (never sneak out in front of a fast train), but only for a plain local that's
    /// right at the junction — so gaps still come along reliably.
    private func throughNearJunction(_ dir: Dir) -> Bool {
        let j = mainJunctionDist(dir)
        return trains.contains { o in
            guard !o.finished, o.dir == dir, !o.onLoop, o.committed else { return false }
            let toJ = j - o.dist                          // >0 nose approaching the junction, <0 nose through it
            let tailPast = CGFloat(o.spec.length) * Track.carUnit   // nose must clear by the whole train length
            if toJ <= -tailPast { return false }              // the tail is clear of the junction
            if o.express { return true }                       // any part of an express still on the junction — hold
            return toJ < Track.carUnit * 4.5                   // a plain local only blocks right at the junction
        }
    }

    /// Is a train already in the platform loop for that direction, so the next one must wait on the main?
    private func loopBusy(_ dir: Dir, except t: DawTrain) -> Bool {
        let exit = exitDist(dir)
        return trains.contains { o in
            o !== t && !o.finished && o.dir == dir && o.onLoop && o.committed && o.dist < exit - Track.carUnit
        }
    }
    /// A main-line train passing through the exit point, which a departing platform train must give way to.
    private func mainNearExit(_ dir: Dir, except t: DawTrain) -> Bool {
        let x = exitX(dir)
        let guardW = Track.carUnit * 3.4
        return trains.contains { o in
            guard o !== t, !o.finished, o.dir == dir, !o.onLoop, o.committed else { return false }
            let ox = dir == .east ? (spawnL + o.dist) : (spawnR - o.dist)
            return abs(ox - x) < guardW
        }
    }

    func reset() {
        trains = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0; sparkles = []
        pUp = 1; pDown = 1; overUp = 0; overDown = 0; upWait = 0; downWait = 0
        expressNearUp = false; expressNearDown = false; upHold = true; downHold = true
        spawnClock = 0; nextSpawn = 1.0; paxClock = 0; nextPax = 1.2
        spawn()
        objectWillChange.send()
    }

    private func spawn() {
        let express = Double.random(in: 0...1) < def.expressChance
        // Now and then a heritage steam special sweeps through — a fast service that never stops here.
        let steam = !express && Double.random(in: 0...1) < 0.16
        // Expresses are long intercity sets — a red or a green operator; the steam special runs a short
        // rake of cream coaches behind its engine; the short locals run in plain white.
        let len = express ? Int.random(in: 6...8) : (steam ? 5 : (def.trainLengths.randomElement() ?? 3))
        let tint = express ? (Bool.random() ? Color(red: 0.85, green: 0.18, blue: 0.22)
                                            : Color(red: 0.13, green: 0.60, blue: 0.32))
                           : (steam ? Color(red: 0.38, green: 0.23, blue: 0.14)   // teak/chocolate heritage stock
                                    : Color(red: 0.90, green: 0.92, blue: 0.95))
        let spec = Train(length: len, tint: tint, name: "")
        let east = Bool.random()
        let path = east ? eMain : wMain                // everyone starts on the main; points divert stoppers
        let t = DawTrain(spec, east ? .east : .west, express: express, path,
                         berth: path.total + 1,
                         speed: express ? baseSpeed * 3.1 : (steam ? baseSpeed * 2.0 : baseSpeed))
        t.steam = steam
        if express || steam {   // through services already carry passengers; a few run near-empty (ECS)
            let cap = Double(len) * perCar
            t.load = Double.random(in: 0...1) < 0.78 ? Double.random(in: cap * 0.5 ... cap * 0.95)
                                                     : Double.random(in: 0 ... cap * 0.25)
        }
        trains.append(t)
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        let gap = Track.carUnit * 0.9

        animT += dt
        upWait = pUp >= 1 ? upWait + dt : 0
        downWait = pDown >= 1 ? downWait + dt : 0

        paxClock += dt
        if paxClock >= nextPax {
            paxClock = 0
            if Bool.random() { pUp = min(pUp + 1, platformCap) } else { pDown = min(pDown + 1, platformCap) }
            nextPax = Double.random(in: def.spawnRange)
        }
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            if trains.count < 4 { spawn() }
            nextSpawn = Double.random(in: def.spawnRange.lowerBound...(def.spawnRange.upperBound * 1.3))
        }

        // Warn while an express is still short of the station, so the player can time their release around it.
        expressNearUp = false; expressNearDown = false
        for t in trains where (t.express || t.steam) && !t.finished {
            let togo = pointDist(t.dir) - t.dist
            if togo > -320 && togo < 620 {
                if t.dir == .east { expressNearUp = true } else { expressNearDown = true }
            }
        }

        let roster = trains
        for t in roster where !t.finished {
            // Every train runs the main to the point. A short local pulls into a free platform automatically;
            // an express is too long for the loop and a busy loop turns one away — either just carries on the main.
            if !t.committed && t.dist >= pointDist(t.dir) - Track.carUnit * 0.3 {
                t.committed = true
                if !t.express && !t.steam && !loopBusy(t.dir, except: t) {
                    t.onLoop = true
                    t.path = t.dir == .east ? eStop : wStop
                    t.berthDist = t.dir == .east ? eBerth : wBerth
                }
            }
            // Once its whole length is past the junction, a released local rejoins the main proper. Switch it
            // onto the main path with an equivalent distance, so it and the through trains measure each other on
            // the same scale (otherwise they mis-space and can wedge at the junction).
            if t.onLoop && t.dist - CGFloat(t.spec.length) * Track.carUnit >= exitDist(t.dir) {
                let overshoot = t.dist - exitDist(t.dir)
                t.path = t.dir == .east ? eMain : wMain
                t.dist = mainJunctionDist(t.dir) + overshoot
                t.onLoop = false
            }

            // Let the train run on past the end of the line until its whole length has cleared, so a long
            // express doesn't vanish while its tail is still on-screen.
            let overrun = CGFloat(t.spec.length) * Track.carUnit
            var ceiling = t.path.total + overrun
            // A local always pulls up to board; then it holds while its starter is red, and pulls away once
            // it's boarded and the starter is cleared to green.
            if !t.express && t.onLoop && !t.released {
                let hold = t.dir == .east ? upHold : downHold
                // Hold if the starter is red, boarding isn't done, or a through train still has to clear the
                // junction — the last guard is what stops you releasing a local into a running express's path.
                if hold || !t.boarded || throughNearJunction(t.dir) { ceiling = min(ceiling, t.berthDist) }
                else { t.released = true; Sound.shared.play(.depart) }
            }
            // Interlock: while a released platform train is claiming the junction, the conflicting main signal is
            // red — every through train (express or not) holds short of the junction until the platform is clear.
            if !t.onLoop && mainBlocked(t.dir) {
                let sig = mainSignalDist(t.dir)
                if t.dist < sig { ceiling = min(ceiling, sig - Track.carUnit * 0.6) }
            }
            // Junction protection: a through train already past the entry stops its nose short of the junction
            // while a local is crossing it — the local only frees the junction once its rear is through.
            if !t.onLoop && platformCrossing(t.dir) {
                let jd = mainJunctionDist(t.dir)
                if t.dist < jd { ceiling = min(ceiling, jd - Track.carUnit * 0.9) }
            }
            // A through train already onto the junction still bars a platform train from barging into it.
            if t.onLoop && t.committed && t.dist < exitDist(t.dir) && mainNearExit(t.dir, except: t) {
                ceiling = min(ceiling, exitDist(t.dir) - Track.carUnit * 0.7)
            }
            // Trains block each other on any shared physical track: the same line through the middle, or the
            // common approach before the point (so a fast train can never clip a local that hasn't diverted yet).
            let pd = pointDist(t.dir)
            var aheadTail = CGFloat.infinity
            for o in roster where o !== t && !o.finished && o.dir == t.dir && o.dist > t.dist {
                let sharedApproach = t.dist < pd && o.dist < pd + o.carLen
                if o.onLoop == t.onLoop || sharedApproach { aheadTail = min(aheadTail, o.dist - o.carLen) }
            }
            if aheadTail.isFinite { ceiling = min(ceiling, aheadTail - gap) }
            // Honour the automatic block signals: a through train stops at a red one, and eases off at an amber.
            var speedCap = t.speed
            if !t.onLoop {
                let east = t.dir == .east
                let fx = mainFrontX(t)
                for sx in blockXs where (east ? sx > fx : sx < fx) {
                    switch blockAspect(sx, t.dir) {
                    case 2:                                  // red — stop short of the signal
                        let sd = east ? (sx - spawnL) : (spawnR - sx)
                        if t.dist < sd { ceiling = min(ceiling, sd - Track.carUnit * 0.5) }
                    case 1:                                  // amber — run at caution speed
                        speedCap = min(speedCap, t.speed * 0.45)
                    default: break
                    }
                }
            }
            // Ease toward the target speed: build up and brake gently over a long run, and brake harder and
            // earlier for a hard stop, so the train glides right up to the ceiling (a red signal, a berth, a train).
            let headroom = max(0, ceiling - t.dist)
            // Expresses build up and shed speed more briskly so a clear run really flies; locals stay gentle.
            let accel: CGFloat = t.express ? 165 : 62, decel: CGFloat = t.express ? 200 : 96
            let target = min(speedCap, sqrt(2 * decel * headroom))
            if t.v < target { t.v = min(target, t.v + accel * CGFloat(dt)) }
            else { t.v = max(target, t.v - decel * CGFloat(dt)) }
            t.dist = max(t.dist, min(t.dist + t.v * CGFloat(dt), ceiling))
            t.stopped = t.v < 5 ? t.stopped + dt : 0   // held at a red — count how long it's been waiting

            // Board while the train is standing at its berth. It keeps topping up from newly-arrived passengers
            // (up to its capacity) for as long as it hasn't pulled away — once it moves off, no more can board.
            if !t.express && t.onLoop && t.dist >= t.berthDist - 0.5 && t.dist <= t.berthDist + Track.carUnit * 0.3 {
                if !t.started {
                    t.started = true
                    t.dwell = dwellTime
                    if t.dir == .east { upWait = 0 } else { downWait = 0 }
                    Sound.shared.play(.board)
                }
                t.dwell -= dt
                let cap = Double(t.spec.length) * perCar
                let plat = t.dir == .east ? pUp : pDown
                if t.load < cap && plat > 0 {
                    let take = min(boardOffRate * dt, min(cap - t.load, plat))
                    let before = plat
                    if t.dir == .east { pUp = max(0, pUp - take) } else { pDown = max(0, pDown - take) }
                    let after = t.dir == .east ? pUp : pDown
                    if Int(before) != Int(after) {
                        // Sparkle on the platform, right where the waiting people stand (not up by the train).
                        let k = Int(after)
                        sparkles.append(Sparkle(x: platL - 6 + CGFloat(k) * 15,
                                                y: t.dir == .east ? 184 : 372))
                    }
                    t.load += take; carried += take
                }
                if t.dwell <= 0 { t.boarded = true }
            }
            if t.dist >= t.path.total + overrun { t.finished = true }
            else if t.dist >= t.path.total && !t.express && t.onLoop && !t.departed {
                t.departed = true; Sound.shared.play(.depart)
            }
        }
        trains.removeAll { $0.finished }
        for i in sparkles.indices { sparkles[i].age += dt }
        sparkles.removeAll { $0.age > sparkleLife }

        overUp = pUp >= platformCap ? overUp + dt : 0
        overDown = pDown >= platformCap ? overDown + dt : 0
        peakFill = max(peakFill, max(pUp, pDown) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = levelStars(def, carried: Int(carried))
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
            Sound.shared.play(.win)
        } else if overUp > overflowGrace || overDown > overflowGrace {
            outcome = .lost
            stars = levelStars(def, carried: Int(carried))
            Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }
}
