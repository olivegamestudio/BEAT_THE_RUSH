import SwiftUI

/// Lostwithiel — a double-track section in the Fowey valley, no platforms. Pure congestion: trains
/// run left and right on their own lane, so normally it flows. Partway through, the slow china-clay
/// freight fails on the up (top) lane and blocks it. From then on the up-line trains must cross over
/// and share the down lane with the oncoming traffic — taking turns over that stretch — while the
/// player calls the rescue loco out of its siding to drag the casualty into the refuge siding and
/// reopen the road.
///
/// Flow is deliberately simple: two independent lanes (no head-on possible) until the block, then a
/// single Saltash-style route light governs the one shared stretch. The rescue is the level.

enum LwRole { case service, freight, rescue }

@MainActor
final class LwTrain: Identifiable {
    let id = UUID()
    var spec: Train
    let dir: LostwithielStation.Dir     // east = left→right (up/top lane), west = right→left (down/bottom lane)
    var role: LwRole = .service
    var path: RoutePath
    var dist: CGFloat = 0
    var bodyLen: CGFloat                 // tail length for following/collision (freight is long)
    var diverting = false               // an up-line train routed across onto the down lane past the block
    var finished = false
    var blocked = false
    var stopped = 0.0
    var railAspect = 0
    var dead = false                    // the freight, once it has failed
    var hauling = false                 // the rescue has coupled the casualty and is dragging it clear
    weak var casualty: LwTrain?
    let smokeRate: Double

    init(_ spec: Train, _ dir: LostwithielStation.Dir, _ path: RoutePath, body: CGFloat, smoke: Double) {
        self.spec = spec; self.dir = dir; self.path = path; self.bodyLen = body; self.smokeRate = smoke
    }
}

@MainActor
final class LostwithielStation: ObservableObject {
    enum Dir { case east, west }
    let def: StationDef
    var name: String { def.name }

    // MARK: geometry (design space, H = 452)
    let yTop: CGFloat = 196             // up lane — eastbound
    let yBot: CGFloat = 300             // down lane — westbound
    let xW: CGFloat = -340              // west portal, off-screen
    let xE: CGFloat = 1560              // east portal, off-screen
    let xCW: CGFloat = 380              // west crossover
    let xCE: CGFloat = 900              // east crossover
    let xOff: CGFloat = 70              // how far a crossover slews across between the lanes
    let xFreight: CGFloat = 860         // where the clay freight's engine dies, on the up lane
    let xSideTurn: CGFloat = 1000       // where the St Blazey line trails off the up lane
    var stBlazey: CGPoint { CGPoint(x: 1440, y: -120) }   // the St Blazey line, off the up lane to the east

    // The shared stretch of the down lane both directions must take turns over once the up lane is blocked.
    var contestL: CGFloat { xCW + xOff }
    var contestR: CGFloat { xCE - xOff }

    // Automatic filter signals spacing the two approaches, so arrivals queue a block apart, not nose-to-tail.
    let blockXsUp: [CGFloat] = [20, 220]        // up-line approach (eastbound), west of the crossover
    let blockXsDown: [CGFloat] = [1200, 1000]   // down-line approach (westbound), east of the crossover
    private let blockLen: CGFloat = 180

    /// Is the block just ahead of the signal at `sx` (in `dir`) held by another service?
    func blockHeld(_ sx: CGFloat, _ dir: Dir, except t: LwTrain? = nil) -> Bool {
        trains.contains { o in
            guard o !== t, !o.finished, o.role == .service, o.dir == dir else { return false }
            let x = headX(o)
            return dir == .east ? (x > sx && x < sx + blockLen) : (x < sx && x > sx - blockLen)
        }
    }
    /// A filter signal's aspect: 2 red (block ahead held), 1 amber (next block held), 0 green.
    func blockAspect(_ sx: CGFloat, _ dir: Dir) -> Int {
        if blockHeld(sx, dir) { return 2 }
        let xs = dir == .east ? blockXsUp : blockXsDown
        let next = dir == .east ? xs.filter { $0 > sx }.min() : xs.filter { $0 < sx }.max()
        if let n = next, blockHeld(n, dir) { return 1 }
        return 0
    }

    @Published var trains: [LwTrain] = []
    @Published var carried = 0.0        // trains sent safely through — the score
    @Published var eastClear = true             // the up-line signal — red holds eastbounds at the west crossover
    @Published var westClear = true             // the down-line signal — red holds westbounds at the east crossover
    @Published var broken = false               // the freight has failed and is blocking the up lane
    @Published var rescued = false
    @Published var rescueReady = false          // the rescue loco is in its siding, waiting for the call
    @Published var outcome: GameOutcome = .playing
    @Published var stars = 0

    var animT = 0.0
    let baseSpeed: CGFloat = 78
    let freightSpeed: CGFloat = 34      // the loaded clay train really plods
    let rescueSpeed: CGFloat = 104
    let freightWagons = 10
    let wagonUnit: CGFloat = 34         // short four-wheel clay hoods, closer together than a coach
    private var spawnClock = 0.0, nextSpawn = 2.2
    private var throughCount = 0
    private var overClock = 0.0
    let maxBacklog = 6
    let overflowGrace = 16.0
    private var contestDir: Dir? = nil          // which way currently holds the shared single-line stretch

    init(_ def: StationDef) {
        self.def = def
        spawn(.east); spawn(.west)
    }

    func reset() {
        trains = []; carried = 0; outcome = .playing; stars = 0
        eastClear = true; westClear = true; broken = false; rescued = false; rescueReady = false
        animT = 0; throughCount = 0; overClock = 0; spawnClock = 0; nextSpawn = 2.2
        spawn(.east); spawn(.west)
        objectWillChange.send()
    }

    // MARK: paths

    private func servicePath(_ dir: Dir, diverting: Bool) -> RoutePath {
        if dir == .west { return RoutePath([CGPoint(x: xE, y: yBot), CGPoint(x: xW, y: yBot)]) }
        if !diverting { return RoutePath([CGPoint(x: xW, y: yTop), CGPoint(x: xE, y: yTop)]) }
        // Up-line divert: run to the west crossover, slew down onto the down lane, run the shared stretch,
        // slew back up at the east crossover, and away.
        return RoutePath([CGPoint(x: xW, y: yTop), CGPoint(x: xCW, y: yTop),
                          CGPoint(x: xCW + xOff, y: yBot), CGPoint(x: xCE - xOff, y: yBot),
                          CGPoint(x: xCE, y: yTop), CGPoint(x: xE, y: yTop)])
    }

    private func spawn(_ dir: Dir) {
        let len = def.trainLengths.randomElement() ?? 3
        let tint = trainPalette[Int.random(in: 0..<trainPalette.count)]
        let diverting = dir == .east && broken
        let t = LwTrain(Train(length: len, tint: tint, name: ""), dir, servicePath(dir, diverting: diverting),
                        body: CGFloat(len) * Track.carUnit, smoke: Double(Int.random(in: 0..<100)))
        t.diverting = diverting
        trains.append(t)
    }

    private func spawnFreight() {
        let clay = Color(red: 0.80, green: 0.76, blue: 0.68)
        let body = Track.carUnit + CGFloat(freightWagons) * wagonUnit    // engine + ten hoods
        let t = LwTrain(Train(length: 1, tint: clay, name: ""), .east,
                        RoutePath([CGPoint(x: xW, y: yTop), CGPoint(x: xE, y: yTop)]),
                        body: body, smoke: 3)
        t.role = .freight
        trains.insert(t, at: 0)
    }

    // MARK: controls

    /// Tap the route light: clear that direction over the shared stretch, or hold both.
    func clear(_ dir: Dir) { if dir == .east { eastClear.toggle() } else { westClear.toggle() }; objectWillChange.send() }
    func granted(_ dir: Dir) -> Bool { dir == .east ? eastClear : westClear }

    func releaseRescue() {
        guard rescueReady, !trains.contains(where: { $0.role == .rescue }) else { return }
        let orange = Color(red: 0.90, green: 0.46, blue: 0.16)
        // Approach: in off the St Blazey line onto the up lane, running west to the casualty — all on the
        // up lane, so it never cuts across untracked ground.
        let approach = RoutePath([stBlazey, CGPoint(x: xSideTurn, y: yTop),
                                  CGPoint(x: xFreight + Track.carUnit * 0.7, y: yTop)])
        let r = LwTrain(Train(length: 1, tint: orange, name: ""), .west, approach,
                        body: Track.carUnit, smoke: 7)
        r.role = .rescue
        trains.append(r)
        rescueReady = false
        Sound.shared.play(.ding)
        objectWillChange.send()
    }

    // MARK: helpers

    func headX(_ t: LwTrain) -> CGFloat { t.path.sample(t.dist).p.x }
    func headY(_ t: LwTrain) -> CGFloat { t.path.sample(t.dist).p.y }
    private func tailX(_ t: LwTrain) -> CGFloat { t.path.sample(max(0, t.dist - t.bodyLen)).p.x }

    /// The `dist` at which a train's head first reaches design-x `x` along its path (nil if never).
    func distAtX(_ t: LwTrain, _ x: CGFloat) -> CGFloat? {
        let p = t.path.pts
        for i in 1..<p.count {
            let x0 = p[i - 1].x, x1 = p[i].x
            if x0 != x1 && (x - x0) * (x - x1) <= 0 {
                let a = t.path.distanceTo(vertex: i - 1), b = t.path.distanceTo(vertex: i)
                return a + (b - a) * (x - x0) / (x1 - x0)
            }
        }
        return nil
    }

    /// Is this service currently on the shared down-lane stretch (its body over the contested x-range)?
    private func inContest(_ t: LwTrain) -> Bool {
        guard t.role == .service, abs(headY(t) - yBot) < 20 || t.diverting else { return false }
        let lo = min(headX(t), tailX(t)), hi = max(headX(t), tailX(t))
        return hi > contestL && lo < contestR && abs(headY(t) - yBot) < 30
    }
    private func opposingInContest(_ dir: Dir) -> Bool {
        trains.contains { $0.dir != dir && !$0.finished && inContest($0) }
    }

    var eastBacklog: Int { trains.filter { $0.dir == .east && $0.role == .service && $0.blocked && headX($0) < xCW }.count }
    var westBacklog: Int { trains.filter { $0.dir == .west && $0.role == .service && $0.blocked && headX($0) > xCE }.count }

    // MARK: simulation

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        animT += dt
        let gap = Track.carUnit * 0.9

        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            if trains.filter({ $0.role == .service }).count < 8 { spawn(Bool.random() ? .east : .west) }
            nextSpawn = Double.random(in: def.spawnRange)
        }
        if !broken && throughCount >= 3 && !trains.contains(where: { $0.role == .freight }) { spawnFreight() }

        let roster = trains
        let deadFreight = roster.first { $0.dead }
        // Single-line working over the shared stretch: whoever is in it holds it; when it empties, hand it
        // to the waiting side, alternating, so neither is starved and traffic flows around the block by itself.
        if let occ = roster.first(where: { $0.role == .service && inContest($0) }) {
            contestDir = occ.dir
        } else {
            let eastWaiting = roster.contains { $0.role == .service && $0.diverting && headX($0) > xCW - 80 && headX($0) < xCW + 6 }
            let westWaiting = roster.contains { $0.role == .service && $0.dir == .west && headX($0) < xCE + 80 && headX($0) > xCE - 6 }
            if eastWaiting && westWaiting { contestDir = (contestDir == .east) ? .west : .east }
            else if eastWaiting { contestDir = .east }
            else if westWaiting { contestDir = .west }
            else { contestDir = nil }
        }
        for t in roster where !t.finished {
            if t.dead { t.railAspect = 2; continue }
            var speed = t.role == .freight ? freightSpeed : (t.role == .rescue ? rescueSpeed : baseSpeed)
            if t.role == .freight, !t.dead {              // grind to a halt as it fails, rather than a dead stop
                let dd = xFreight - headX(t)
                if dd < 130 { speed *= max(0.12, dd / 130) }
            }
            var ceiling = t.path.total

            // Don't overrun a same-direction train ahead.
            for o in roster where o !== t && !o.finished && o.dir == t.dir && o.role != .rescue && o.dist > t.dist {
                ceiling = min(ceiling, o.dist - o.bodyLen - gap)       // everything queues behind the train ahead, freight included
            }
            // The dead freight is a wall on the up lane — up-line trains still committed to it stop short.
            if let f = deadFreight, t.role == .service, !t.diverting, t.dir == .east {
                if let d = distAtX(t, tailX(f) - gap), d > t.dist { ceiling = min(ceiling, d) }
            }
            // Single-line working over the shared stretch: a diverting up-train, or any down-train, may only
            // enter when the route is granted its way and no one is coming the other way.
            // A service honours its own signal at all times — a red holds it at its crossover. After the
            // block it also holds if the other way is currently in the shared stretch, so they never meet.
            if t.role == .service {
                let holdX = t.dir == .east ? xCW : xCE
                var mayPass = granted(t.dir)
                if broken, (t.diverting || t.dir == .west), let c = contestDir, c != t.dir { mayPass = false }
                if !mayPass, let h = distAtX(t, holdX), t.dist <= h - gap { ceiling = min(ceiling, h - gap) }
                // Filter signals space the approach: hold a block back if the block ahead is held.
                for sx in (t.dir == .east ? blockXsUp : blockXsDown) {
                    let approaching = t.dir == .east ? headX(t) < sx - 1 : headX(t) > sx + 1
                    if approaching, blockHeld(sx, t.dir, except: t), let h = distAtX(t, sx), t.dist <= h - gap {
                        ceiling = min(ceiling, h - gap)
                    }
                }
            }
            // The rescue holds short of any train ahead; while hauling it runs the whole consist off the
            // scene, so let it overrun the path end.
            if t.role == .rescue {
                ceiling = t.hauling ? (t.path.total + t.bodyLen + Track.carUnit) : t.path.total
                if rescueMeetsTrain(t) { ceiling = min(ceiling, t.dist) }
            }

            let step = speed * CGFloat(dt)
            let next = min(t.dist + step, ceiling)
            t.blocked = next < t.dist + step - 0.01 && next < t.path.total - 1
            t.stopped = t.blocked ? t.stopped + dt : 0
            t.dist = max(t.dist, next)
            t.railAspect = railAspect(headroom: ceiling - t.dist, clearToEnd: ceiling >= t.path.total - 1, amber: false)

            // The freight plods up the up lane and fails at the appointed spot — the inciting event.
            if t.role == .freight && !t.dead && headX(t) >= xFreight {
                t.dead = true; broken = true; rescueReady = true
                divertUpTrains()
                Sound.shared.play(.ding)
            }
            if t.role == .rescue { runRescue(t) }

            if t.role == .service && t.dist >= t.path.total - 1 {
                t.finished = true; carried += 1; throughCount += 1; Sound.shared.play(.depart)
            }
        }
        trains.removeAll { $0.finished }

        let backlog = max(eastBacklog, westBacklog)
        overClock = backlog > maxBacklog ? overClock + dt : 0
        if carried >= Double(def.goal) && rescued {
            outcome = .won; stars = levelStars(def, carried: Int(carried))
            Progress.record(stars: stars, at: def.id); Progress.clear(def.id); Sound.shared.play(.win)
        } else if overClock > overflowGrace {
            outcome = .lost; stars = levelStars(def, carried: Int(carried)); Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }

    /// When the block appears, reroute every up-line service that hasn't yet reached the west crossover
    /// onto the divert path (they keep their distance — both paths coincide up to the crossover).
    private func divertUpTrains() {
        for t in trains where t.role == .service && t.dir == .east && !t.diverting {
            if headX(t) < xCW - 4 { t.path = servicePath(.east, diverting: true); t.diverting = true }
        }
    }

    private func runRescue(_ r: LwTrain) {
        guard let f = trains.first(where: { $0.role == .freight }) else { return }
        if !r.hauling {
            if r.dist >= r.path.total - 1 {
                r.hauling = true; r.casualty = f; f.dead = false
                // Haul-out starts well west of the casualty, so the whole consist sits on the line (nothing
                // pops in), and runs east along the up lane off toward St Blazey.
                r.path = RoutePath([CGPoint(x: xFreight - 520, y: yTop),
                                    CGPoint(x: xSideTurn, y: yTop), stBlazey])
                r.bodyLen = Track.carUnit * 1.15 + Track.carUnit * 0.92 + CGFloat(freightWagons) * wagonUnit
                r.dist = distAtX(r, xFreight + Track.carUnit * 0.7) ?? 0
                Sound.shared.play(.ding)
            }
        } else if r.dist - r.bodyLen - Track.carUnit >= r.path.total {
            // The whole consist has run off the far end — the road is open again.
            f.finished = true; r.finished = true
            rescued = true; broken = false
            Sound.shared.play(.depart)
        }
    }

    /// True if any train (other than the rescue's own casualty) sits just ahead of the rescue on the
    /// road — sampled from real positions, so it holds whichever lane the other train is on.
    private func rescueMeetsTrain(_ r: LwTrain) -> Bool {
        let ahead = r.path.sample(min(r.path.total, r.dist + 1.2 * Track.carUnit)).p
        for o in trains where o !== r && !o.finished && o.role != .rescue && o !== r.casualty {
            var d = o.dist
            let end = max(0, o.dist - o.bodyLen)
            while d >= end {
                let p = o.path.sample(d).p
                if hypot(p.x - ahead.x, p.y - ahead.y) < 0.85 * Track.carUnit { return true }
                d -= Track.carUnit * 0.5
            }
        }
        return false
    }
}
