import SwiftUI

/// Newark — the famous flat crossing, where the East Coast Main Line crosses the Nottingham–Lincoln
/// (Castle) line on the level. Two lines, one diamond: only one train can be on the crossover at a time,
/// so the player grants it — main line or Castle line — and the two take turns. Each line has a platform
/// its trains load at before they reach the diamond.
final class NewarkTrain: Identifiable {
    enum Line { case ecml, castle }
    let id = UUID()
    var spec: Train
    let line: Line
    let path: RoutePath
    let berthDist: CGFloat
    let crossDist: CGFloat          // distance at which the front reaches the diamond
    var dist: CGFloat = 0
    var boarded = false
    var started = false
    var dwell = 0.0
    var load = 0.0
    var hasCross = false            // currently occupying the diamond
    var v: CGFloat = 0
    var stopped = 0.0
    var finished = false
    var carLen: CGFloat { spec.carLength }
    init(_ spec: Train, _ line: Line, _ path: RoutePath, berth: CGFloat, cross: CGFloat) {
        self.spec = spec; self.line = line; self.path = path
        berthDist = berth; crossDist = cross
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
    let platL: CGFloat = 430
    let platR: CGFloat = 720
    var platC: CGFloat { (platL + platR) / 2 }
    let spawnL: CGFloat = -320
    let spawnR: CGFloat = 1720
    /// The point where the two lines cross.
    var diamond: CGPoint { CGPoint(x: xD, y: yEcml) }

    @Published var trains: [NewarkTrain] = []
    @Published var carried = 0.0
    @Published var pEcml = 1.0
    @Published var pCastle = 1.0
    @Published var grant: Line? = nil        // which line is cleared over the crossing
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

    init(_ def: StationDef) { self.def = def; spawn() }

    /// Set (or clear) the crossing for a line.
    func setGrant(_ g: Line) { grant = (grant == g) ? nil : g; objectWillChange.send() }
    var diamondOccupied: Bool { occupant != nil }
    private func mayTakeDiamond(_ t: NewarkTrain) -> Bool { occupant == nil && grant == t.line }

    private func spawn() {
        let line: Line = Bool.random() ? .ecml : .castle
        let spec = Train(length: def.trainLengths.randomElement() ?? 3,
                         tint: line == .ecml ? Color(red: 0.30, green: 0.55, blue: 0.86)
                                             : Color(red: 0.86, green: 0.44, blue: 0.30),
                         name: "")
        let path: RoutePath, berthV: Int, diamondV: Int
        if line == .ecml {   // straight along the main line, load, then over the crossing and away east
            path = RoutePath([CGPoint(x: spawnL, y: yEcml), CGPoint(x: platC, y: yEcml),
                              CGPoint(x: xD, y: yEcml), CGPoint(x: spawnR, y: yEcml)])
            berthV = 1; diamondV = 2
        } else {             // load on the Castle platform, dive to the crossing, away to the south
            let exitY = yEcml + (yEcml - yCastle) / (xD - platR) * (spawnR - xD)   // keep the same slope past the diamond
            path = RoutePath([CGPoint(x: spawnL, y: yCastle), CGPoint(x: platC, y: yCastle),
                              CGPoint(x: platR, y: yCastle), CGPoint(x: xD, y: yEcml),
                              CGPoint(x: spawnR, y: exitY)])
            berthV = 1; diamondV = 3
        }
        trains.append(NewarkTrain(spec, line, path, berth: path.distanceTo(vertex: berthV),
                                  cross: path.distanceTo(vertex: diamondV)))
    }

    func reset() {
        trains = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0; sparkles = []
        pEcml = 1; pCastle = 1; overE = 0; overC = 0; eWait = 0; cWait = 0; grant = nil
        spawnClock = 0; nextSpawn = 1.0; paxClock = 0; nextPax = 1.1
        spawn()
        objectWillChange.send()
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        let gap = Track.carUnit * 0.85

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

        let roster = trains
        for t in roster where !t.finished {
            let overrun = CGFloat(t.spec.length) * Track.carUnit
            var ceiling = t.path.total + overrun
            // Load at the platform first.
            if !t.boarded { ceiling = min(ceiling, t.berthDist) }
            // Hold short of the diamond unless it's granted our way and clear — and we've finished loading.
            if !t.hasCross && (t.dist - t.carLen) < t.crossDist {
                if !(t.boarded && mayTakeDiamond(t)) {
                    ceiling = min(ceiling, t.crossDist - gap)
                }
            }
            // Follow the train ahead on the same line.
            var aheadTail = CGFloat.infinity
            for o in roster where o !== t && !o.finished && o.line == t.line && o.dist > t.dist {
                aheadTail = min(aheadTail, o.dist - o.carLen)
            }
            if aheadTail.isFinite { ceiling = min(ceiling, aheadTail - gap) }

            let headroom = max(0, ceiling - t.dist)
            let accel: CGFloat = 90, decel: CGFloat = 150
            let target = min(baseSpeed, sqrt(2 * decel * headroom))
            if t.v < target { t.v = min(target, t.v + accel * CGFloat(dt)) }
            else { t.v = max(target, t.v - decel * CGFloat(dt)) }
            t.dist = max(t.dist, min(t.dist + t.v * CGFloat(dt), ceiling))
            t.stopped = t.v < 5 ? t.stopped + dt : 0

            // Take the crossing when at it, boarded, granted and clear; free it once the tail is over.
            if !t.hasCross && t.boarded && mayTakeDiamond(t) && t.dist >= t.crossDist - gap - 1 {
                t.hasCross = true; occupant = t
                Sound.shared.play(.ding)
            }
            if t.hasCross && (t.dist - t.carLen) > t.crossDist {
                t.hasCross = false; if occupant === t { occupant = nil }
            }

            // Boarding.
            if t.dist >= t.berthDist - 0.5 && t.dist <= t.berthDist + Track.carUnit * 0.3 {
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
                        sparkles.append(Sparkle(x: platL - 6 + CGFloat(k) * 15,
                                                y: (t.line == .ecml ? yEcml : yCastle) - 22))
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

        overE = pEcml >= platformCap ? overE + dt : 0
        overC = pCastle >= platformCap ? overC + dt : 0
        peakFill = max(peakFill, max(pEcml, pCastle) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = starsFor(peakFill: peakFill)
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
            Sound.shared.play(.win)
        } else if overE > overflowGrace || overC > overflowGrace {
            outcome = .lost
            Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }
}
