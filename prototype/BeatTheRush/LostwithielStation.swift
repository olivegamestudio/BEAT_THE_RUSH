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

/// A RailVehicle (RailKit piece 3): the shared engine drives `dist`, `railAspect`, `stopped`, `blocked`;
/// the fields here are Lostwithiel's own — direction, role, the long body used for following, and the
/// breakdown/rescue state.
final class LwTrain: RailVehicle {
    let dir: LostwithielStation.Dir     // east = left→right (up/top lane), west = right→left (down/bottom lane)
    var role: LwRole = .service
    var bodyLen: CGFloat                 // tail length for following/collision (freight is long)
    var diverting = false               // an up-line train routed across onto the down lane past the block
    var dead = false                    // the freight, once it has failed
    var hauling = false                 // the rescue has coupled the casualty and is dragging it clear
    weak var casualty: LwTrain?
    let smokeRate: Double

    init(_ spec: Train, _ dir: LostwithielStation.Dir, _ path: RoutePath, body: CGFloat, smoke: Double, lane: Int) {
        self.dir = dir; self.bodyLen = body; self.smokeRate = smoke
        super.init(spec: spec, path: path, lane: lane)
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
    var stBlazey: CGPoint { CGPoint(x: xE + 400, y: yTop - 62) }        // the St Blazey line runs east, off-scene
    var blazeTurn: CGPoint { CGPoint(x: xSideTurn + 130, y: yTop - 62) } // where it levels off, heading east

    // The shared stretch of the down lane both directions must take turns over once the up lane is blocked.
    var contestL: CGFloat { xCW + xOff }
    var contestR: CGFloat { xCE - xOff }

    // --- RailKit piece 1: the two running lanes and the two crossovers as named nodes; the service and
    // divert run-paths are stitched from them by route(_:).
    let graph: RailGraph

    // --- RailKit piece 2: the automatic filter signals are a BlockSignal chain per approach, spacing
    // arrivals a block apart. Each block runs from its signal to the next filter (or the crossover); the
    // chain's .next gives the amber look-ahead. Built in init, refreshed each tick from live positions.
    let blockXsUp: [CGFloat] = [20, 220]        // up-line approach (eastbound), west of the crossover
    let blockXsDown: [CGFloat] = [1200, 1000]   // down-line approach (westbound), east of the crossover
    let blockSignalsUp: [BlockSignal]
    let blockSignalsDown: [BlockSignal]
    /// A filter signal's stored aspect (2 red / 1 amber / 0 green), refreshed each tick by updateBlockSignals.
    func blockAspect(_ sx: CGFloat, _ dir: Dir) -> Int {
        (dir == .east ? blockSignalsUp : blockSignalsDown).first { abs($0.axis - sx) < 0.5 }?.aspect ?? 0
    }
    /// Refresh every filter signal from the live service positions in its direction.
    private func updateBlockSignals() {
        for s in blockSignalsUp { s.update { self.serviceHeadInRange($0, .east) } }
        for s in blockSignalsDown { s.update { self.serviceHeadInRange($0, .west) } }
    }
    /// Whether any service of `dir` has its head within the block range `r`.
    private func serviceHeadInRange(_ r: ClosedRange<CGFloat>, _ dir: Dir) -> Bool {
        trains.contains { o in
            guard !o.finished, o.role == .service, o.dir == dir else { return false }
            let x = self.headX(o)
            return x >= r.lowerBound && x <= r.upperBound
        }
    }

    // --- RailKit piece 3: the shared movement engine owns the trains; `trains` is a view onto its roster.
    let sim: RailSim<LwTrain>
    var trains: [LwTrain] { sim.vehicles }
    private var laneSeq = 0      // each train gets its own lane so the engine's lane-follow never fires;
                                 // Lostwithiel does its own body-length following in the ceiling hook
    @Published var carried = 0.0        // trains sent safely through — the score
    // --- RailKit piece 2: the two route lights are independent player-tappable HoldSignals (cleared =
    // green over the shared stretch). Not a group — either direction can be set on its own.
    let upHold = HoldSignal("east", at: .zero, cleared: true)     // up-line — red holds eastbounds at the west crossover
    let downHold = HoldSignal("west", at: .zero, cleared: true)   // down-line — red holds westbounds at the east crossover
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
        var g = RailGraph()
        for n in [RailNode("wTop", x: xW, y: yTop),  RailNode("eTop", x: xE, y: yTop),
                  RailNode("wBot", x: xW, y: yBot),  RailNode("eBot", x: xE, y: yBot),
                  RailNode("cwTop", x: xCW, y: yTop), RailNode("cwBot", x: xCW + xOff, y: yBot),
                  RailNode("ceBot", x: xCE - xOff, y: yBot), RailNode("ceTop", x: xCE, y: yTop)] { g.add(n) }
        graph = g
        // Build each approach's filter chain: block runs from its signal to the next filter, else the crossover.
        let upXs = blockXsUp.sorted(), dnXs = blockXsDown.sorted(by: >)
        let yT = yTop - 26, yB = yBot + 26, cw = xCW, ce = xCE
        var upS: [BlockSignal] = []
        for (i, sx) in upXs.enumerated() {
            let end = i + 1 < upXs.count ? upXs[i + 1] : cw
            upS.append(BlockSignal("up\(sx)", at: CGPoint(x: sx, y: yT), axis: sx, forward: 1, blockLen: end - sx))
        }
        var dnS: [BlockSignal] = []
        for (i, sx) in dnXs.enumerated() {
            let end = i + 1 < dnXs.count ? dnXs[i + 1] : ce
            dnS.append(BlockSignal("dn\(sx)", at: CGPoint(x: sx, y: yB), axis: sx, forward: -1, blockLen: sx - end))
        }
        if upS.count > 1 { for i in 0..<upS.count - 1 { upS[i].next = upS[i + 1] } }
        if dnS.count > 1 { for i in 0..<dnS.count - 1 { dnS[i].next = dnS[i + 1] } }
        blockSignalsUp = upS; blockSignalsDown = dnS

        // Lostwithiel runs a constant-speed model: the huge accel/decel make RailSim's eased step behave
        // like the old fixed-step move (full speed until the ceiling, then a hard stop) — so the feel is
        // unchanged while the shared engine still owns following, route-lighting and the roster.
        sim = RailSim(kin: RailKinematics(speedCap: baseSpeed, accel: 100000, decel: 100000))
        configureSim()
        spawn(.east); spawn(.west)
    }

    /// Wire Lostwithiel's rules into the shared engine. Per-role speed (with the failing freight's ramp),
    /// movement authority (`ceiling`), the rescue's haul-out overrun, the breakdown/rescue script
    /// (`onAdvance`) and the finish/score all plug in here.
    private func configureSim() {
        let gap = Track.carUnit * 2.2
        // Per-role top speed; the clay freight grinds to a halt as it fails rather than a dead stop.
        sim.kinematics = { [weak self] t in
            guard let self else { return RailKinematics(speedCap: 78, accel: 100000, decel: 100000) }
            var speed = t.role == .freight ? self.freightSpeed : (t.role == .rescue ? self.rescueSpeed : self.baseSpeed)
            if t.role == .freight, !t.dead {
                let dd = self.xFreight - self.headX(t)
                if dd < 130 { speed *= max(0.12, dd / 130) }
            }
            return RailKinematics(speedCap: speed, accel: 100000, decel: 100000)
        }
        // While hauling, the rescue runs its whole consist off the far end, so it may overrun the path.
        sim.overrun = { $0.role == .rescue && $0.hauling ? $0.bodyLen + Track.carUnit : 0 }
        sim.ceiling = { [weak self] t, roster in
            guard let self else { return .infinity }
            if t.dead { return t.dist }        // the failed freight is a fixed wall until the rescue drags it clear
            var ceiling = CGFloat.infinity
            // Don't overrun a same-direction train ahead (freight included; the rescue is never followed).
            for o in roster where o !== t && !o.finished && o.dir == t.dir && o.role != .rescue && o.dist > t.dist {
                ceiling = min(ceiling, o.dist - o.bodyLen - gap)
            }
            // The dead freight is a wall on the up lane — up-line trains still committed to it stop short.
            if let f = roster.first(where: { $0.dead }), t.role == .service, !t.diverting, t.dir == .east {
                if let d = self.distAtX(t, self.tailX(f) - gap), d > t.dist { ceiling = min(ceiling, d) }
            }
            // Single-line working: a service honours its own signal, and after the block also holds if the
            // other way is currently in the shared stretch, so they never meet.
            if t.role == .service {
                let holdX = t.dir == .east ? self.xCW : self.xCE
                var mayPass = self.granted(t.dir)
                if self.broken, (t.diverting || t.dir == .west), let c = self.contestDir, c != t.dir { mayPass = false }
                if !mayPass, let h = self.distAtX(t, holdX), t.dist <= h - gap { ceiling = min(ceiling, h - gap) }
                for sx in (t.dir == .east ? self.blockXsUp : self.blockXsDown) {
                    let approaching = t.dir == .east ? self.headX(t) < sx - 1 : self.headX(t) > sx + 1
                    if approaching, self.blockAspect(sx, t.dir) == 2, let h = self.distAtX(t, sx), t.dist <= h - gap {
                        ceiling = min(ceiling, h - gap)
                    }
                }
            }
            // The rescue holds short of anything ahead on the road.
            if t.role == .rescue, self.rescueMeetsTrain(t) { ceiling = min(ceiling, t.dist) }
            return ceiling
        }
        sim.onAdvance = { [weak self] t, _ in
            guard let self else { return }
            // The freight plods up the up lane and fails at the appointed spot — the inciting event.
            if t.role == .freight && !t.dead && self.headX(t) >= self.xFreight {
                t.dead = true; self.broken = true; self.rescueReady = true
                self.divertUpTrains()
                Sound.shared.play(.ding)
            }
            if t.role == .rescue { self.runRescue(t) }
        }
        // A service finishes at the far portal (scored); the freight and rescue finish inside runRescue.
        sim.isFinished = { $0.role == .service && $0.dist >= $0.path.total - 1 }
        sim.onFinish = { [weak self] t in
            guard let self, t.role == .service else { return }
            self.carried += 1; self.throughCount += 1; Sound.shared.play(.depart)
        }
    }

    /// Single-line working over the shared stretch: whoever is in it holds it; when it empties, hand it to
    /// the waiting side, alternating, so neither is starved and traffic flows around the block by itself.
    private func computeContestDir() {
        let roster = trains
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
    }

    func reset() {
        sim.vehicles = []; laneSeq = 0; carried = 0; outcome = .playing; stars = 0
        upHold.cleared = true; downHold.cleared = true; broken = false; rescued = false; rescueReady = false
        animT = 0; throughCount = 0; overClock = 0; spawnClock = 0; nextSpawn = 2.2
        spawn(.east); spawn(.west)
        objectWillChange.send()
    }

    // MARK: paths

    private func servicePath(_ dir: Dir, diverting: Bool) -> RoutePath {
        if dir == .west { return graph.route(["eBot", "wBot"]) }
        if !diverting { return graph.route(["wTop", "eTop"]) }
        // Up-line divert: run to the west crossover, slew down onto the down lane, run the shared stretch,
        // slew back up at the east crossover, and away.
        return graph.route(["wTop", "cwTop", "cwBot", "ceBot", "ceTop", "eTop"])
    }

    private func spawn(_ dir: Dir) {
        let len = def.trainLengths.randomElement() ?? 3
        let tint = trainPalette[Int.random(in: 0..<trainPalette.count)]
        let diverting = dir == .east && broken
        laneSeq += 1
        let t = LwTrain(Train(length: len, tint: tint, name: ""), dir, servicePath(dir, diverting: diverting),
                        body: CGFloat(len) * Track.carUnit, smoke: Double(Int.random(in: 0..<100)), lane: laneSeq)
        t.diverting = diverting
        sim.vehicles.append(t)
    }

    private func spawnFreight() {
        let clay = Color(red: 0.80, green: 0.76, blue: 0.68)
        let body = Track.carUnit + CGFloat(freightWagons) * wagonUnit    // engine + ten hoods
        laneSeq += 1
        let t = LwTrain(Train(length: 1, tint: clay, name: ""), .east,
                        graph.route(["wTop", "eTop"]),
                        body: body, smoke: 3, lane: laneSeq)
        t.role = .freight
        sim.vehicles.insert(t, at: 0)
    }

    // MARK: controls

    /// Tap the route light: clear that direction over the shared stretch, or hold it.
    func clear(_ dir: Dir) { (dir == .east ? upHold : downHold).toggle(); objectWillChange.send() }
    func granted(_ dir: Dir) -> Bool { (dir == .east ? upHold : downHold).cleared }

    func releaseRescue() {
        guard rescueReady, !trains.contains(where: { $0.role == .rescue }) else { return }
        let orange = Color(red: 0.90, green: 0.46, blue: 0.16)
        // Approach: in off the St Blazey line onto the up lane, running west to the casualty — all on the
        // up lane, so it never cuts across untracked ground.
        let approach = RoutePath([stBlazey, blazeTurn, CGPoint(x: xSideTurn, y: yTop),
                                  CGPoint(x: xFreight + Track.carUnit * 0.7, y: yTop)])
        laneSeq += 1
        let r = LwTrain(Train(length: 1, tint: orange, name: ""), .west, approach,
                        body: Track.carUnit, smoke: 7, lane: laneSeq)
        r.role = .rescue
        sim.vehicles.append(r)
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

        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            if trains.filter({ $0.role == .service }).count < 6 { spawn(Bool.random() ? .east : .west) }
            nextSpawn = Double.random(in: def.spawnRange)
        }
        if !broken && throughCount >= 3 && !trains.contains(where: { $0.role == .freight }) { spawnFreight() }

        // RailKit piece 3: set the single-line direction, refresh the filter signals, then let the shared
        // engine drive everyone (following, route-lighting, and — via the hooks — the breakdown/rescue).
        updateBlockSignals()
        computeContestDir()
        sim.step(dt)

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
                                    CGPoint(x: xSideTurn, y: yTop), blazeTurn, stBlazey])
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
