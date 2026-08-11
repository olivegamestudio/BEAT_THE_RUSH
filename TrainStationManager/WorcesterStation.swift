import SwiftUI

/// Worcester Foregate Street. Two platforms, but east of them the line pinches to a single track out to
/// Shrub Hill that everything must share: Platform 2 (orange) departs east over it to Droitwich & Birmingham,
/// while Platform 1 (green) trains arrive over it from London & Bristol. Only one train fits the single line at
/// a time, so the player's job is to grant it — east or west — and keep both platforms flowing.
final class WorcTrain: Identifiable {
    enum Line { case blue, red }        // blue = Platform 2 (eastbound, orange), red = Platform 1 (westbound, green)
    let id = UUID()
    var spec: Train
    let line: Line
    let path: RoutePath
    let berthDist: CGFloat
    let singleEnter: CGFloat       // distance at which it reaches the single-line neck
    let singleExit: CGFloat        // distance at which its front clears the single line
    var dist: CGFloat = 0
    var boarded = false
    var started = false
    var dwell = 0.0
    var load = 0.0
    var hasSingle = false          // currently granted the single line
    var v: CGFloat = 0
    var stopped = 0.0
    var finished = false
    var railAspect = 0             // 0 green / 1 amber / 2 red — lights the track ahead to show its route
    var carLen: CGFloat { spec.carLength }
    init(_ spec: Train, _ line: Line, _ path: RoutePath, berth: CGFloat, enter: CGFloat, exit: CGFloat) {
        self.spec = spec; self.line = line; self.path = path
        berthDist = berth; singleEnter = enter; singleExit = exit
    }
}

@MainActor
final class WorcesterStation: ObservableObject {
    typealias Line = WorcTrain.Line
    let def: StationDef
    var name: String { def.name }

    // Geometry (design space W = 1200, H = 452), all on the ground clear of the sky.
    let yP2: CGFloat = 210     // Platform 2 — orange, eastbound to Droitwich & Birmingham
    let yP1: CGFloat = 344     // Platform 1 — green, westbound from London & Bristol
    let ySingle: CGFloat = 276 // the single Shrub Hill line, between the platforms
    let xEJ: CGFloat = 800     // east throat — platforms converge to the single line
    let xSH: CGFloat = 1200    // Shrub Hill — single line splits to the destinations
    let platL: CGFloat = 456
    let platR: CGFloat = 716
    let spawnL: CGFloat = -300
    let spawnR: CGFloat = 1740
    let branchStep: CGFloat = 96   // how far apart the four junctions are staggered along the single line, west→east
    let branchFan: CGFloat = 130   // gradual diverge from the single line onto each destination line
    // East of Shrub Hill the four lines peel off the single line one at a time, interleaved in/out/in/out.
    let yLondon: CGFloat = 152, yDroitwich: CGFloat = 216       // in, out
    let yBristol: CGFloat = 336, yBirmingham: CGFloat = 400     // in, out
    var branchYs: [CGFloat] { [yLondon, yDroitwich, yBristol, yBirmingham] }
    /// Where each destination's junction sits on the single line, staggered west→east. Ordered so lines never
    /// cross: on each side the furthest-out destination peels off first — London (far up), Droitwich (near up),
    /// Birmingham (far down), Bristol (near down).
    func branchX(_ yDest: CGFloat) -> CGFloat {
        switch yDest {
        case yLondon:     return xSH
        case yDroitwich:  return xSH + branchStep
        case yBirmingham: return xSH + 2 * branchStep
        default:          return xSH + 3 * branchStep   // Bristol, furthest east
        }
    }
    var eastmostBranchX: CGFloat { xSH + 3 * branchStep }
    /// Three-aspect for a junction light, reflecting its own road: green when the single line is set that way,
    /// amber when a train waits on it, red otherwise.
    func branchAspect(_ yDest: CGFloat) -> Int {
        let isOut = (yDest == yDroitwich || yDest == yBirmingham)
        let thisGrant: Grant = isOut ? .east : (yDest == yLondon ? .london : .bristol)
        if grant == thisGrant { return 0 }
        let waiting: Bool
        if isOut {
            waiting = trains.contains { !$0.finished && $0.line == .blue && $0.boarded && !$0.hasSingle }
        } else {
            waiting = trains.contains { !$0.finished && $0.line == .red && !$0.hasSingle && abs($0.path.sample(0).p.y - yDest) < 6 }
        }
        return waiting ? 1 : 2
    }

    @Published var trains: [WorcTrain] = []
    @Published var carried = 0.0
    @Published var pP2 = 1.0
    @Published var pP1 = 1.0
    enum Grant { case east, london, bristol }   // what the single line is currently set for
    @Published var grant: Grant? = nil
    @Published var outcome: GameOutcome = .playing
    @Published var stars = 0
    @Published var sparkles: [Sparkle] = []

    var animT = 0.0
    private var p2Wait = 0.0, p1Wait = 0.0
    let agitateAfter = 22.0
    private func moodFor(_ w: Double, _ p: Double) -> Mood {
        if p < 1 { return .happy }
        if w > agitateAfter { return .cross }
        if w > agitateAfter * 0.55 { return .waiting }
        return .happy
    }
    var p2Mood: Mood { moodFor(p2Wait, pP2) }
    var p1Mood: Mood { moodFor(p1Wait, pP1) }
    var p2Agitated: Bool { pP2 >= 1 && p2Wait > agitateAfter }
    var p1Agitated: Bool { pP1 >= 1 && p1Wait > agitateAfter }

    let baseSpeed: CGFloat = 72
    let dwellTime = 2.6
    let perCar = 3.0
    let boardOffRate = 6.0
    let platformCap = 16.0
    let overflowGrace = 18.0

    static let wmrOrange = Color(red: 0.92, green: 0.46, blue: 0.09)
    static let gwrGreen = Color(red: 0.62, green: 0.86, blue: 0.18)   // lime green

    private var spawnClock = 0.0, nextSpawn = 1.2
    private var paxClock = 0.0, nextPax = 1.2
    private var overP2 = 0.0, overP1 = 0.0
    private var peakFill = 0.0
    private weak var occupant: WorcTrain?

    init(_ def: StationDef) { self.def = def; spawn() }

    /// Set the single line for a movement (or take the grant away if it was already set that way).
    func setGrant(_ g: Grant) { grant = (grant == g) ? nil : g; objectWillChange.send() }
    /// May this train take the single line right now — is it granted for its movement, and the line clear?
    private func mayTakeSingle(_ t: WorcTrain) -> Bool {
        guard occupant == nil else { return false }
        if t.line == .blue { return grant == .east }
        return abs(t.path.sample(0).p.y - yLondon) < 4 ? grant == .london : grant == .bristol
    }

    private func present(_ l: Line) -> Bool {
        trains.contains { !$0.finished && $0.line == l && !$0.hasSingle
            && $0.dist >= $0.berthDist - Track.carUnit && $0.dist < $0.singleExit }
    }
    var p2Busy: Bool { present(.blue) }
    var p1Busy: Bool { present(.red) }

    /// Is the block just east of `x` on the Platform 2 western approach occupied — i.e. should a queue signal
    /// there show red? Used to line eastbound arrivals up behind each other on the inbound-left road.
    func p2BlockAhead(_ x: CGFloat) -> Bool {
        let blockLen: CGFloat = 210
        for t in trains where !t.finished && t.line == .blue {
            let head = t.path.sample(t.dist).p
            guard head.x <= xEJ + 4, abs(head.y - yP2) < 24 else { continue }   // still on the western approach
            let tail = head.x - t.carLen
            if head.x > x && tail < x + blockLen { return true }
        }
        return false
    }
    /// Signal positions down the inbound-left approach, nearest the platform first.
    var p2QueueXs: [CGFloat] { [platL - 40, platL - 250, platL - 460] }
    /// Three-aspect for a queue light: red if the block just ahead is taken, amber if the block beyond it is, else green.
    func p2QueueAspect(_ x: CGFloat) -> Int {
        if p2BlockAhead(x) { return 2 }
        if p2BlockAhead(x + 210) { return 1 }
        return 0
    }
    /// Three-aspect for a junction light on the single line: red while a train holds the line, amber while it's
    /// granted but not yet taken, green when clear.
    var singleAspect: Int { occupant != nil ? 2 : (grant != nil ? 1 : 0) }

    private func spawn() {
        let line: Line = Bool.random() ? .blue : .red
        let spec = Train(length: def.trainLengths.randomElement() ?? 3,
                         tint: line == .blue ? Self.wmrOrange : Self.gwrGreen, name: "")
        let d: CGFloat = 40
        let path: RoutePath, berthV: Int, enterV: Int, exitV: Int
        if line == .blue {          // eastbound: Malvern → Platform 2 → single line → its junction → Droitwich/Birmingham
            let yE = Bool.random() ? yDroitwich : yBirmingham
            let bx = branchX(yE)
            path = RoutePath([CGPoint(x: spawnL, y: yP2), CGPoint(x: platR, y: yP2), CGPoint(x: xEJ, y: yP2),
                              CGPoint(x: xEJ + d, y: ySingle), CGPoint(x: bx, y: ySingle),
                              CGPoint(x: bx + branchFan, y: yE), CGPoint(x: spawnR, y: yE)])
            berthV = 1; enterV = 3; exitV = 4   // holds the single line until it diverges at its junction
        } else {                    // westbound: London/Bristol → its junction → single line → Platform 1 → Malvern
            let yA = Bool.random() ? yLondon : yBristol
            let bx = branchX(yA)
            path = RoutePath([CGPoint(x: spawnR, y: yA), CGPoint(x: bx + branchFan, y: yA), CGPoint(x: bx, y: ySingle),
                              CGPoint(x: xEJ + d, y: ySingle), CGPoint(x: xEJ, y: yP1),
                              CGPoint(x: platL, y: yP1), CGPoint(x: spawnL, y: yP1)])
            berthV = 5; enterV = 2; exitV = 3   // holds the single line from its junction to the platform throat
        }
        trains.append(WorcTrain(spec, line, path, berth: path.distanceTo(vertex: berthV),
                                enter: path.distanceTo(vertex: enterV), exit: path.distanceTo(vertex: exitV)))
    }

    func reset() {
        trains = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0; sparkles = []
        pP2 = 1; pP1 = 1; overP2 = 0; overP1 = 0; p2Wait = 0; p1Wait = 0; grant = nil
        spawnClock = 0; nextSpawn = 1.2; paxClock = 0; nextPax = 1.2
        spawn()
        objectWillChange.send()
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        let gap = Track.carUnit * 0.85

        animT += dt
        p2Wait = pP2 >= 1 ? p2Wait + dt : 0
        p1Wait = pP1 >= 1 ? p1Wait + dt : 0

        paxClock += dt
        if paxClock >= nextPax {
            paxClock = 0
            if Bool.random() { pP2 = min(pP2 + 1, platformCap) } else { pP1 = min(pP1 + 1, platformCap) }
            nextPax = Double.random(in: def.spawnRange)
        }
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            if trains.count < 6 { spawn() }
            nextSpawn = Double.random(in: def.spawnRange.lowerBound...(def.spawnRange.upperBound * 1.3))
        }

        let roster = trains
        for t in roster where !t.finished {
            let overrun = CGFloat(t.spec.length) * Track.carUnit
            var ceiling = t.path.total + overrun
            // Eastbound trains board at the platform before the single line; westbound board after it.
            if t.line == .blue && !t.boarded { ceiling = min(ceiling, t.berthDist) }
            // Hold unless the single line is granted our way and clear. Eastbound trains wait AT the platform
            // (so the berth stays occupied and the next train queues behind); westbound wait at their junction.
            if !t.hasSingle && t.dist < t.singleExit {
                let readyForSingle = t.line == .red || t.boarded    // eastbound must load first
                if !(readyForSingle && mayTakeSingle(t)) {
                    ceiling = min(ceiling, t.line == .blue ? t.berthDist : t.singleEnter - gap)
                }
            }
            // Westbound trains board once they're through the single line, at the platform.
            if t.line == .red && !t.boarded { ceiling = min(ceiling, t.berthDist) }
            // Follow the train ahead on the same physical road. Departures share the one Platform 2 road; arrivals
            // queue per eastern lane (London and Bristol don't hold each other up until they reach the single line).
            var aheadTail = CGFloat.infinity
            for o in roster where o !== t && !o.finished && o.line == t.line && o.dist > t.dist {
                let sameRoad = t.line == .blue || abs(t.path.sample(0).p.y - o.path.sample(0).p.y) < 4
                if sameRoad { aheadTail = min(aheadTail, o.dist - o.carLen) }
            }
            if aheadTail.isFinite { ceiling = min(ceiling, aheadTail - gap) }

            // Eastbound arrivals honour the inbound-left queue signals — hold before a red one.
            if t.line == .blue && !t.boarded {
                let headX = t.path.sample(t.dist).p.x
                for x in p2QueueXs.sorted() where x > headX + 2 {
                    if p2QueueAspect(x) == 2 { ceiling = min(ceiling, (x - spawnL) - gap); break }
                }
            }

            let headroom = max(0, ceiling - t.dist)
            let accel: CGFloat = 88, decel: CGFloat = 150
            let target = min(baseSpeed, sqrt(2 * decel * headroom))
            if t.v < target { t.v = min(target, t.v + accel * CGFloat(dt)) }
            else { t.v = max(target, t.v - decel * CGFloat(dt)) }
            t.dist = max(t.dist, min(t.dist + t.v * CGFloat(dt), ceiling))
            t.stopped = t.v < 5 ? t.stopped + dt : 0
            // Light the road ahead green/amber/red so its route over the single line reads at a glance.
            t.railAspect = railAspect(headroom: ceiling - t.dist, clearToEnd: ceiling >= t.path.total - 1)

            // Take the single line when at the neck, granted, and it's clear.
            if !t.hasSingle && mayTakeSingle(t)
                && t.dist >= t.singleEnter - gap - 1 && (t.line == .red || t.boarded) {
                t.hasSingle = true; occupant = t
                Sound.shared.play(.ding)
            }
            // Free the single line once the tail is clear of it.
            if t.hasSingle && (t.dist - t.carLen) > t.singleExit {
                t.hasSingle = false; if occupant === t { occupant = nil }
            }

            // Boarding at the platform.
            if t.dist >= t.berthDist - 0.5 && t.dist <= t.berthDist + Track.carUnit * 0.3 {
                if !t.started {
                    t.started = true; t.dwell = dwellTime
                    if t.line == .blue { p2Wait = 0 } else { p1Wait = 0 }
                    Sound.shared.play(.board)
                }
                t.dwell -= dt
                let cap = Double(t.spec.length) * perCar
                let plat = t.line == .blue ? pP2 : pP1
                if t.load < cap && plat > 0 {
                    let take = min(boardOffRate * dt, min(cap - t.load, plat))
                    let before = plat
                    if t.line == .blue { pP2 = max(0, pP2 - take) } else { pP1 = max(0, pP1 - take) }
                    let after = t.line == .blue ? pP2 : pP1
                    if Int(before) != Int(after) {
                        let k = Int(after)
                        sparkles.append(Sparkle(x: platL - 6 + CGFloat(k) * 15,
                                                y: t.line == .blue ? yP2 - 22 : yP1 + 26))
                    }
                    t.load += take; carried += take
                }
                if t.dwell <= 0 { t.boarded = true }
            }
            if t.dist >= t.path.total + overrun { t.finished = true; if occupant === t { occupant = nil } }
        }
        trains.removeAll { $0.finished }
        for i in sparkles.indices { sparkles[i].age += dt }
        sparkles.removeAll { $0.age > sparkleLife }

        overP2 = pP2 >= platformCap ? overP2 + dt : 0
        overP1 = pP1 >= platformCap ? overP1 + dt : 0
        peakFill = max(peakFill, max(pP2, pP1) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = levelStars(def, carried: Int(carried))
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
            Sound.shared.play(.win)
        } else if overP2 > overflowGrace || overP1 > overflowGrace {
            outcome = .lost
            stars = levelStars(def, carried: Int(carried))
            Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }
}
