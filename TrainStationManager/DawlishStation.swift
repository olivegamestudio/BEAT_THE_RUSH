import SwiftUI

/// Dawlish Warren on the sandy Exe spit. Two through tracks run across; at each end a pair of
/// points can turn a stopping train off into a platform loop and back onto the main. Expresses
/// keep to the main and race straight through.
final class DawTrain: Identifiable {
    let id = UUID()
    var spec: Train
    let dir: DawlishStation.Dir
    let express: Bool
    let path: RoutePath
    let berthDist: CGFloat
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
        let path = east ? (express ? eMain : eStop) : (express ? wMain : wStop)
        let berth = express ? path.total + 1 : (east ? eBerth : wBerth)
        trains.append(DawTrain(spec, east ? .east : .west, express: express, path,
                               berth: berth, speed: express ? baseSpeed * 1.7 : baseSpeed))
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
            var aheadTail = CGFloat.infinity   // share a route only with same dir + same kind (main vs loop)
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
                                                y: t.dir == .east ? upLoopY - 26 : downLoopY + 30))
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
