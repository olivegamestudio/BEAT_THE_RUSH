import SwiftUI

/// Dawlish Warren: the sandy spit at the mouth of the Exe. Four lines run between the two
/// platforms — an outer platform loop each side where stopping trains call, and two fast lines
/// down the middle where expresses race straight through without stopping.
final class DawTrain: Identifiable {
    let id = UUID()
    var spec: Train
    let dir: DawlishStation.Dir
    let express: Bool
    let path: RoutePath
    let berthDist: CGFloat        // where a stopping train halts (ignored for expresses)
    let speed: CGFloat
    var dist: CGFloat = 0
    var boarded = false
    var started = false
    var dwell = 0.0
    var toBoard = 0.0
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

    // Geometry (design space W = 1200, H = 452) — four lines between the platforms.
    let upPlatY: CGFloat = 230     // eastbound platform loop (top)
    let upFastY: CGFloat = 264     // eastbound fast line
    let downFastY: CGFloat = 296   // westbound fast line
    let downPlatY: CGFloat = 330   // westbound platform loop (bottom)
    let tunL: CGFloat = 96
    let tunR: CGFloat = 1104
    let platL: CGFloat = 430
    let platR: CGFloat = 770
    let pad: CGFloat = 340

    @Published var trains: [DawTrain] = []
    @Published var carried = 0.0
    @Published var pUp = 1.0
    @Published var pDown = 1.0
    @Published var upHeld = false
    @Published var downHeld = false
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

    let baseSpeed: CGFloat = 72
    let dwellTime = 2.4
    let perCar = 3.0
    let boardOffRate = 6.0
    let platformCap = 16.0
    let overflowGrace = 18.0

    private let eastPlat, eastFast, westPlat, westFast: RoutePath
    private let ePlatBerth, wPlatBerth: CGFloat
    private var spawnClock = 0.0, nextSpawn = 1.0
    private var paxClock = 0.0, nextPax = 1.2
    private var overUp = 0.0, overDown = 0.0
    private var peakFill = 0.0

    init(_ def: StationDef) {
        self.def = def
        eastPlat = RoutePath([CGPoint(x: tunL - pad, y: upPlatY), CGPoint(x: platR, y: upPlatY),
                              CGPoint(x: tunR + pad, y: upPlatY)])
        ePlatBerth = eastPlat.distanceTo(vertex: 1)
        eastFast = RoutePath([CGPoint(x: tunL - pad, y: upFastY), CGPoint(x: tunR + pad, y: upFastY)])
        westPlat = RoutePath([CGPoint(x: tunR + pad, y: downPlatY), CGPoint(x: platL, y: downPlatY),
                              CGPoint(x: tunL - pad, y: downPlatY)])
        wPlatBerth = westPlat.distanceTo(vertex: 1)
        westFast = RoutePath([CGPoint(x: tunR + pad, y: downFastY), CGPoint(x: tunL - pad, y: downFastY)])
        spawn()
    }

    func toggle(_ dir: Dir) {
        if dir == .east { upHeld.toggle() } else { downHeld.toggle() }
        objectWillChange.send()
    }

    func reset() {
        trains = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0; sparkles = []
        pUp = 1; pDown = 1; overUp = 0; overDown = 0; upWait = 0; downWait = 0
        upHeld = false; downHeld = false
        spawnClock = 0; nextSpawn = 1.0; paxClock = 0; nextPax = 1.2
        spawn()
        objectWillChange.send()
    }

    private func spawn() {
        let spec = Train(length: def.trainLengths.randomElement() ?? 3,
                         tint: trainPalette.randomElement() ?? .blue, name: "")
        let east = Bool.random()
        let express = Double.random(in: 0...1) < def.expressChance
        if east {
            let path = express ? eastFast : eastPlat
            trains.append(DawTrain(spec, .east, express: express, path,
                                   berth: express ? path.total + 1 : ePlatBerth,
                                   speed: express ? baseSpeed * 1.7 : baseSpeed))
        } else {
            let path = express ? westFast : westPlat
            trains.append(DawTrain(spec, .west, express: express, path,
                                   berth: express ? path.total + 1 : wPlatBerth,
                                   speed: express ? baseSpeed * 1.7 : baseSpeed))
        }
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        let gap = Track.carUnit * 0.6

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
            if trains.count < 9 { spawn() }
            nextSpawn = Double.random(in: def.spawnRange.lowerBound...(def.spawnRange.upperBound * 1.3))
        }

        let roster = trains
        for t in roster where !t.finished {
            let held = !t.express && (t.dir == .east ? upHeld : downHeld)
            var ceiling = t.path.total
            if !t.express && (!t.boarded || held) { ceiling = min(ceiling, t.berthDist) }
            // don't run into the train ahead on the same line (share a line only same dir+kind)
            var aheadTail = CGFloat.infinity
            for o in roster where o !== t && !o.finished && o.dir == t.dir && o.express == t.express && o.dist > t.dist {
                aheadTail = min(aheadTail, o.dist - o.carLen)
            }
            if aheadTail.isFinite { ceiling = min(ceiling, aheadTail - gap) }
            t.dist = max(t.dist, min(t.dist + t.speed * CGFloat(dt), ceiling))

            if !t.express && !t.boarded && t.dist >= t.berthDist - 0.5 {
                if !t.started {
                    t.started = true
                    t.dwell = dwellTime
                    t.toBoard = min(t.dir == .east ? pUp : pDown, Double(t.spec.length) * perCar)
                    if t.dir == .east { upWait = 0 } else { downWait = 0 }
                    Sound.shared.play(.board)
                }
                t.dwell -= dt
                if t.toBoard > 0 {
                    let take = min(boardOffRate * dt, t.toBoard)
                    let before = t.dir == .east ? pUp : pDown
                    if t.dir == .east { pUp = max(0, pUp - take) } else { pDown = max(0, pDown - take) }
                    let after = t.dir == .east ? pUp : pDown
                    if Int(before) != Int(after) {
                        let k = Int(after)
                        sparkles.append(Sparkle(x: platL + 20 + CGFloat(k) * 15,
                                                y: t.dir == .east ? upPlatY - 26 : downPlatY + 30))
                    }
                    t.toBoard -= take; carried += take
                }
                if t.dwell <= 0 { t.boarded = true }
            }
            if t.dist >= t.path.total { t.finished = true; if !t.express { Sound.shared.play(.depart) } }
        }
        trains.removeAll { $0.finished }
        for i in sparkles.indices { sparkles[i].age += dt }
        sparkles.removeAll { $0.age > sparkleLife }

        overUp = pUp >= platformCap ? overUp + dt : 0
        overDown = pDown >= platformCap ? overDown + dt : 0
        peakFill = max(peakFill, max(pUp, pDown) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = starsFor(peakFill: peakFill)
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
            Sound.shared.play(.win)
        } else if overUp > overflowGrace || overDown > overflowGrace {
            outcome = .lost
            Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }
}
