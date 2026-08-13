import SwiftUI

/// Newark — the famous flat crossing, where the East Coast Main Line crosses the Nottingham–Lincoln
/// (Castle) line on the level. Two lines, one diamond: only one train can be on the crossover at a time,
/// so the player grants it — main line or Castle line — and the two take turns. Each line has a platform
/// its trains load at before they reach the diamond.
/// A RailVehicle (RailKit piece 3): the shared engine drives dist/v/railAspect/stopped; the fields here
/// are Newark's own — which line, its platform berth, where it reaches the diamond, and its boarding state.
final class NewarkTrain: RailVehicle {
    enum Line { case ecml, castle }
    let line: Line
    let entryDist: CGFloat          // distance at the platform entrance (held by the entry signal)
    let berthDist: CGFloat          // where it berths and waits at the starter
    let crossDist: CGFloat          // distance at which the front reaches the diamond
    var boarded = false
    var started = false
    var dwell = 0.0
    var load = 0.0
    var hasCross = false            // currently occupying the diamond
    init(_ spec: Train, _ line: Line, _ path: RoutePath, entry: CGFloat, berth: CGFloat, cross: CGFloat, lane: Int) {
        self.line = line; entryDist = entry; berthDist = berth; crossDist = cross
        super.init(spec: spec, path: path, lane: lane)
    }
}

@MainActor
final class NewarkStation: ObservableObject {
    typealias Line = NewarkTrain.Line
    let def: StationDef
    var name: String { def.name }

    // Geometry (design space W ≈ 1400, H = 452)
    let yEcml: CGFloat = 252       // East Coast Main Line — horizontal
    let yCastle: CGFloat = 132     // Castle line platform — horizontal lead before it dives to the crossing
    let xD: CGFloat = 980          // the flat crossing (diamond), on the main line
    let platL: CGFloat = 380
    let platR: CGFloat = 860
    var platC: CGFloat { (platL + platR) / 2 }
    let spawnL: CGFloat = -320
    let spawnR: CGFloat = 1720
    /// The point where the two lines cross.
    var diamond: CGPoint { CGPoint(x: xD, y: yEcml) }

    // --- RailKit piece 3: the shared movement engine owns the trains; `trains` is a view onto its roster.
    // ECML trains run on lane 0, Castle on lane 1, so the engine's built-in lane-follow spaces each line
    // (the two lines only meet at the diamond, handled by the occupant resource in the ceiling hook).
    let sim: RailSim<NewarkTrain>
    var trains: [NewarkTrain] { sim.vehicles }
    @Published var carried = 0.0
    @Published var pEcml = 1.0
    @Published var pCastle = 1.0
    // --- RailKit piece 2: two lights per line as player-tappable HoldSignals — an entry signal (admit
    // into the platform) and a platform starter (send the loaded train over the crossing). Entry defaults
    // cleared (trains flow in); the starter defaults held (you work it).
    let entryEcmlSig = HoldSignal("entryE", at: .zero, cleared: true)
    let entryCastleSig = HoldSignal("entryC", at: .zero, cleared: true)
    let starterEcmlSig = HoldSignal("startE", at: .zero, cleared: false)
    let starterCastleSig = HoldSignal("startC", at: .zero, cleared: false)
    @Published var outcome: GameOutcome = .playing
    @Published var stars = 0
    @Published var sparkles: [Sparkle] = []

    var animT = 0.0
    private var eWait = 0.0, cWait = 0.0
    let agitateAfter = 22.0
    private func moodFor(_ w: Double, _ p: Double) -> Mood {
        if p < 1 { return .happy }
        if w > agitateAfter { return .cross }
        if w > agitateAfter * 0.55 { return .waiting }
        return .happy
    }
    var ecmlMood: Mood { moodFor(eWait, pEcml) }
    var castleMood: Mood { moodFor(cWait, pCastle) }
    var ecmlAgitated: Bool { pEcml >= 1 && eWait > agitateAfter }
    var castleAgitated: Bool { pCastle >= 1 && cWait > agitateAfter }

    let baseSpeed: CGFloat = 74
    let dwellTime = 2.6
    let perCar = 3.0
    let boardOffRate = 6.0
    let platformCap = 16.0
    let overflowGrace = 18.0

    private var spawnClock = 0.0, nextSpawn = 1.0
    private var paxClock = 0.0, nextPax = 1.1
    private var overE = 0.0, overC = 0.0
    private var peakFill = 0.0
    private weak var occupant: NewarkTrain?

    // --- RailKit piece 1: the two lines and their shared diamond as named nodes; each train's run-path is
    // stitched from them by route(_:) rather than hand-listed coordinates.
    let graph: RailGraph

    init(_ def: StationDef) {
        self.def = def
        // Keep the Castle line's slope past the diamond, so it runs off the far side at the same angle.
        let exitY = yEcml + (yEcml - yCastle) / (xD - platR) * (spawnR - xD)
        let platCx = (platL + platR) / 2      // platform centre (platC is computed, unusable in init)
        var g = RailGraph()
        for n in [RailNode("eIn", x: spawnL, y: yEcml), RailNode("ePlatL", x: platL, y: yEcml),
                  RailNode("ePlatC", x: platCx, y: yEcml), RailNode("ePlatR", x: platR, y: yEcml),
                  RailNode("diamond", x: xD, y: yEcml), RailNode("eOut", x: spawnR, y: yEcml),
                  RailNode("cIn", x: spawnL, y: yCastle), RailNode("cPlatL", x: platL, y: yCastle),
                  RailNode("cPlatC", x: platCx, y: yCastle), RailNode("cPlatR", x: platR, y: yCastle),
                  RailNode("cOut", x: spawnR, y: exitY)] { g.add(n) }
        graph = g
        sim = RailSim(kin: RailKinematics(speedCap: baseSpeed, accel: 90, decel: 150, followGap: Track.carUnit * 0.85))
        configureSim()
        spawn()
    }

    func entryOpen(_ l: Line) -> Bool { (l == .ecml ? entryEcmlSig : entryCastleSig).cleared }
    func starterOpen(_ l: Line) -> Bool { (l == .ecml ? starterEcmlSig : starterCastleSig).cleared }
    func toggleEntry(_ l: Line) { (l == .ecml ? entryEcmlSig : entryCastleSig).toggle(); objectWillChange.send() }
    func toggleStarter(_ l: Line) { (l == .ecml ? starterEcmlSig : starterCastleSig).toggle(); objectWillChange.send() }
    var diamondOccupied: Bool { occupant != nil }

    /// Wire Newark's rules into the shared engine: the entry/starter/diamond holds (`ceiling`), the
    /// tail-clearing overrun, taking/freeing the diamond and boarding (`onAdvance`), and the finish.
    private func configureSim() {
        let gap = Track.carUnit * 0.85
        sim.overrun = { CGFloat($0.spec.length) * Track.carUnit }
        sim.ceiling = { [weak self] t, _ in
            guard let self else { return .infinity }
            var c = CGFloat.infinity
            // Entry signal — hold on the approach until admitted into the platform.
            if !self.entryOpen(t.line) && t.dist < t.entryDist - 1 { c = min(c, t.entryDist - gap) }
            // Platform starter — load at the berth, then wait there until the starter sends it over the crossing.
            if !(t.boarded && self.starterOpen(t.line)) { c = min(c, t.berthDist) }
            // The crossing takes one train at a time — hold short of the diamond while another is on it.
            if !t.hasCross, self.occupant != nil, self.occupant !== t, (t.dist - t.carLen) < t.crossDist {
                c = min(c, t.crossDist - gap)
            }
            return c
        }
        sim.onAdvance = { [weak self] t, dt in
            guard let self else { return }
            // Take the crossing when dispatched, at it, and it's clear; free it once the tail is over.
            if !t.hasCross && self.occupant == nil && t.boarded && self.starterOpen(t.line) && t.dist >= t.crossDist - gap - 1 {
                t.hasCross = true; self.occupant = t
                Sound.shared.play(.ding)
            }
            if t.hasCross && (t.dist - t.carLen) > t.crossDist {
                t.hasCross = false; if self.occupant === t { self.occupant = nil }
            }
            self.serveBoarding(t, dt)
        }
        sim.isFinished = { $0.dist >= $0.path.total + CGFloat($0.spec.length) * Track.carUnit }
        sim.onFinish = { [weak self] t in if self?.occupant === t { self?.occupant = nil } }
    }

    /// Board a train while it stands at its berth, topping up until it pulls away.
    private func serveBoarding(_ t: NewarkTrain, _ dt: Double) {
        guard t.dist >= t.berthDist - 0.5, t.dist <= t.berthDist + Track.carUnit * 0.3 else { return }
        if !t.started {
            t.started = true; t.dwell = dwellTime
            if t.line == .ecml { eWait = 0 } else { cWait = 0 }
            Sound.shared.play(.board)
        }
        t.dwell -= dt
        let cap = Double(t.spec.length) * perCar
        let plat = t.line == .ecml ? pEcml : pCastle
        if t.load < cap && plat > 0 {
            let take = min(boardOffRate * dt, min(cap - t.load, plat))
            let before = plat
            if t.line == .ecml { pEcml = max(0, pEcml - take) } else { pCastle = max(0, pCastle - take) }
            let after = t.line == .ecml ? pEcml : pCastle
            if Int(before) != Int(after) {
                let k = Int(after)
                sparkles.append(Sparkle(x: platL - 6 + CGFloat(k) * 15, y: (t.line == .ecml ? yEcml : yCastle) - 22))
            }
            t.load += take; carried += take
        }
        if t.dwell <= 0 { t.boarded = true }
    }

    private func spawn() {
        let line: Line = Bool.random() ? .ecml : .castle
        let spec = Train(length: def.trainLengths.randomElement() ?? 3,
                         tint: line == .ecml ? Color(red: 0.30, green: 0.55, blue: 0.86)
                                             : Color(red: 0.86, green: 0.44, blue: 0.30),
                         name: "")
        // ECML runs straight; Castle loads then dives to the diamond and away south. Vertices: 1 = platform
        // entrance, 2 = berth, 4 = the diamond.
        let path = line == .ecml
            ? graph.route(["eIn", "ePlatL", "ePlatC", "ePlatR", "diamond", "eOut"])
            : graph.route(["cIn", "cPlatL", "cPlatC", "cPlatR", "diamond", "cOut"])
        sim.vehicles.append(NewarkTrain(spec, line, path, entry: path.distanceTo(vertex: 1),
                                        berth: path.distanceTo(vertex: 2), cross: path.distanceTo(vertex: 4),
                                        lane: line == .ecml ? 0 : 1))
    }

    func reset() {
        sim.vehicles = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0; sparkles = []
        pEcml = 1; pCastle = 1; overE = 0; overC = 0; eWait = 0; cWait = 0
        entryEcmlSig.cleared = true; entryCastleSig.cleared = true
        starterEcmlSig.cleared = false; starterCastleSig.cleared = false
        spawnClock = 0; nextSpawn = 1.0; paxClock = 0; nextPax = 1.1
        spawn()
        objectWillChange.send()
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }

        animT += dt
        eWait = pEcml >= 1 ? eWait + dt : 0
        cWait = pCastle >= 1 ? cWait + dt : 0

        paxClock += dt
        if paxClock >= nextPax {
            paxClock = 0
            if Bool.random() { pEcml = min(pEcml + 1, platformCap) } else { pCastle = min(pCastle + 1, platformCap) }
            nextPax = Double.random(in: def.spawnRange)
        }
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            if trains.count < 6 { spawn() }
            nextSpawn = Double.random(in: def.spawnRange.lowerBound...(def.spawnRange.upperBound * 1.3))
        }

        // RailKit piece 3: the shared engine drives everyone — lane-follow per line, route-lighting, and
        // (via the hooks) the entry/starter/diamond holds, taking the crossing, and boarding.
        sim.step(dt)

        for i in sparkles.indices { sparkles[i].age += dt }
        sparkles.removeAll { $0.age > sparkleLife }

        overE = pEcml >= platformCap ? overE + dt : 0
        overC = pCastle >= platformCap ? overC + dt : 0
        peakFill = max(peakFill, max(pEcml, pCastle) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = levelStars(def, carried: Int(carried))
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
            Sound.shared.play(.win)
        } else if overE > overflowGrace || overC > overflowGrace {
            outcome = .lost
            stars = levelStars(def, carried: Int(carried))
            Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }
}
