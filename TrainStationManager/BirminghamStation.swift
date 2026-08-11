import SwiftUI

/// Birmingham New Street — twelve through platforms buried under the city, fed from four tracks at each end
/// that alternate in / out / in / out. Every platform can be reached from every approach, so the throat is a
/// full ladder of points. Trains arrive on an "in" road, are routed across the throat to a free platform, call,
/// then leave over an "out" road at the far end.
final class BirmTrain: Identifiable {
    let id = UUID()
    var spec: Train
    var path: RoutePath
    let platform: Int
    let berthDist: CGFloat
    var dist: CGFloat = 0
    var boarded = false
    var started = false
    var dwell = 0.0
    var load = 0.0
    var v: CGFloat = 0
    var stopped = 0.0
    var finished = false
    var railAspect = 0             // 0 green / 1 amber / 2 red — lights the track ahead to show its route
    var carLen: CGFloat { spec.carLength }
    init(_ spec: Train, path: RoutePath, platform: Int, berth: CGFloat) {
        self.spec = spec; self.path = path; self.platform = platform; berthDist = berth
    }
}

@MainActor
final class BirminghamStation: ObservableObject {
    let def: StationDef
    var name: String { def.name }

    // Geometry (design W = 1500, H = 452)
    //
    // Fourteen parallel roads (levels 0–13): the central two (6–7) are the in/out lanes that carry on
    // off-screen; the other twelve are platform faces, grouped into six two-track islands — three fanning
    // above the lanes, three below. Reaching a platform is a *staircase*: the road steps to the adjacent
    // track one crossover at a time, staggered along the throat, so no move is a long diagonal.
    let platformCount = 12
    let trackLevels = 14
    let midY: CGFloat = 226            // stack is centred here
    private let faceGap: CGFloat = 32  // the two tracks that share an island
    private let islandGap: CGFloat = 66
    private let laneGap: CGFloat = 72  // island band ↔ lane band
    private let lanePitch: CGFloat = 32
    let platL: CGFloat = 520           // platform x-extent (where trains berth across)
    let platR: CGFloat = 860
    // Throats reach well past the platforms so each track-change plays out over a long run (pan to follow).
    let xWT: CGFloat = -260            // west throat mouth (staircase spreads between here and platL)
    let xET: CGFloat = 1640            // east throat mouth
    let spawnL: CGFloat = -820
    let spawnR: CGFloat = 2260

    private func gapBefore(_ i: Int) -> CGFloat {
        switch i {
        case 1, 3, 5, 9, 11, 13: return faceGap      // second face of an island
        case 2, 4, 10, 12:       return islandGap    // island ↔ island
        case 6, 8:               return laneGap      // island band ↔ lanes
        case 7:                  return lanePitch    // lane ↔ lane
        default:                 return 0
        }
    }
    private func rawY(_ l: Int) -> CGFloat {
        var y: CGFloat = 0
        if l >= 1 { for i in 1...l { y += gapBefore(i) } }
        return y
    }
    func levelY(_ l: Int) -> CGFloat { rawY(l) - rawY(trackLevels - 1) / 2 + midY }
    let laneLevels = [6, 7]
    func laneIsIn(_ l: Int) -> Bool { l == 6 }                      // 6 arrives, 7 departs
    /// Platform p's road level: 0–5 sit above the lanes (levels 0–5), 6–11 below them (levels 8–13).
    func platformLevel(_ p: Int) -> Int { p <= 5 ? p : p + 2 }
    func platformY(_ p: Int) -> CGFloat { levelY(platformLevel(p)) }
    /// Upper platforms hang off the top lane (6), lower platforms off the bottom lane (7) — each ladder
    /// springs from a real lane, so the centre shows exactly the two lanes and no extra trunk line.
    func laneOf(_ p: Int) -> Int { p <= 5 ? 6 : 7 }
    /// A platform is occupied while a train is berthed there — its starting signals show red.
    func occupied(_ p: Int) -> Bool { trains.contains { !$0.finished && $0.platform == p && $0.started } }
    var islandCount: Int { platformCount / 2 }
    /// Centre-line of island `k` (its two faces), where the platform surface is drawn.
    func islandY(_ k: Int) -> CGFloat {
        let base = k < 3 ? 2 * k : 2 * k + 2      // skip the two lane levels between the upper and lower trios
        return (levelY(base) + levelY(base + 1)) / 2
    }

    var laneMidY: CGFloat { (levelY(6) + levelY(7)) / 2 }
    /// Steps from the lane band out to a platform level: how many adjacent crossovers it takes.
    func stepsTo(_ lvl: Int) -> Int { lvl <= 5 ? 6 - lvl : lvl - 7 }
    /// Where platform level `lvl`'s road tees off the staircase, `mouthX`→`platX` being one throat.
    func teeX(_ lvl: Int, _ mouthX: CGFloat, _ platX: CGFloat) -> CGFloat {
        mouthX + CGFloat(stepsTo(lvl)) / 6 * (platX - mouthX)
    }
    /// The staircase from the lane band at `startY` out to platform level `lvl`, stepping one track per crossover.
    func ladderPath(_ mouthX: CGFloat, _ platX: CGFloat, to lvl: Int, startY: CGFloat) -> [CGPoint] {
        let up = lvl <= 5
        let n = stepsTo(lvl)
        let sw = (platX - mouthX) / 6
        let cw = abs(sw) * 0.42
        let dir: CGFloat = sw > 0 ? 1 : -1
        var pts = [CGPoint(x: mouthX, y: startY)]
        var curY = startY
        guard n > 0 else { return pts }
        for j in 1...n {
            let lvlJ = up ? 6 - j : 7 + j
            let xs = mouthX + CGFloat(j) * sw
            pts.append(CGPoint(x: xs - dir * cw, y: curY))       // run along the road
            pts.append(CGPoint(x: xs, y: levelY(lvlJ)))          // crossover to the adjacent road
            curY = levelY(lvlJ)
        }
        return pts   // ends at (teeX, levelY(lvl))
    }

    @Published var trains: [BirmTrain] = []
    @Published var carried = 0.0
    @Published var pax: [Double]        // waiting passengers per platform
    @Published var outcome: GameOutcome = .playing
    @Published var stars = 0
    @Published var sparkles: [Sparkle] = []

    var animT = 0.0
    private var wait: [Double]
    let agitateAfter = 20.0
    func agitated(_ i: Int) -> Bool { pax[i] >= 1 && wait[i] > agitateAfter }
    func mood(_ i: Int) -> Mood {
        if pax[i] < 1 { return .happy }
        if wait[i] > agitateAfter { return .cross }
        if wait[i] > agitateAfter * 0.55 { return .waiting }
        return .happy
    }

    let baseSpeed: CGFloat = 88
    let dwellTime = 2.2
    let perCar = 3.0
    let boardOffRate = 7.0
    let platformCap = 14.0
    let overflowGrace = 16.0

    private var spawnClock = 0.0, nextSpawn = 1.0
    private var paxClock = 0.0, nextPax = 0.9
    private var over: [Double]
    private var peakFill = 0.0

    init(_ def: StationDef) {
        self.def = def
        pax = Array(repeating: 1, count: platformCount)
        wait = Array(repeating: 0, count: platformCount)
        over = Array(repeating: 0, count: platformCount)
        spawn()
    }

    /// Is a platform free to route a fresh train into?
    private func platformFree(_ i: Int) -> Bool {
        !trains.contains { !$0.finished && $0.platform == i }
    }

    private func spawn() {
        let free = (0..<platformCount).filter { platformFree($0) }
        guard let plat = free.randomElement() else { return }
        let spec = Train(length: def.trainLengths.randomElement() ?? 4,
                         tint: trainPalette.randomElement() ?? .blue, name: "")
        // Approach along the platform's lane, up the staircase onto its road; berth; back down to the lane and away.
        let laneY = levelY(laneOf(plat)), inY = laneY, outY = laneY, py = platformY(plat)
        let lvl = platformLevel(plat)
        let wTee = teeX(lvl, xWT, platL), eTee = teeX(lvl, xET, platR)
        let fromWest = Bool.random()
        var pts: [CGPoint] = []
        let li: Int, ri: Int
        if fromWest {
            pts.append(CGPoint(x: spawnL, y: inY))
            pts += ladderPath(xWT, platL, to: lvl, startY: inY)   // ends at (wTee, py)
            li = pts.count - 1
            pts.append(CGPoint(x: eTee, y: py))                   // across the berth
            ri = pts.count - 1
            pts += ladderPath(xET, platR, to: lvl, startY: outY).reversed().dropFirst()  // (eTee,py)… up to (xET,outY)
            pts.append(CGPoint(x: spawnR, y: outY))
        } else {
            pts.append(CGPoint(x: spawnR, y: inY))
            pts += ladderPath(xET, platR, to: lvl, startY: inY)   // ends at (eTee, py)
            ri = pts.count - 1
            pts.append(CGPoint(x: wTee, y: py))
            li = pts.count - 1
            pts += ladderPath(xWT, platL, to: lvl, startY: outY).reversed().dropFirst()
            pts.append(CGPoint(x: spawnL, y: outY))
        }
        let path = RoutePath(pts)
        let berth = (path.distanceTo(vertex: li) + path.distanceTo(vertex: ri)) / 2   // mid-platform
        trains.append(BirmTrain(spec, path: path, platform: plat, berth: berth))
    }

    func reset() {
        trains = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0; sparkles = []
        pax = Array(repeating: 1, count: platformCount)
        wait = Array(repeating: 0, count: platformCount)
        over = Array(repeating: 0, count: platformCount)
        spawnClock = 0; nextSpawn = 1.0; paxClock = 0; nextPax = 0.9
        spawn()
        objectWillChange.send()
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        let gap = Track.carUnit * 0.7

        animT += dt
        for i in 0..<platformCount { wait[i] = pax[i] >= 1 ? wait[i] + dt : 0 }

        paxClock += dt
        if paxClock >= nextPax {
            paxClock = 0
            let i = Int.random(in: 0..<platformCount)
            pax[i] = min(pax[i] + 1, platformCap)
            nextPax = Double.random(in: def.spawnRange)
        }
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            if trains.count < 8 { spawn() }
            nextSpawn = Double.random(in: def.spawnRange.lowerBound...(def.spawnRange.upperBound * 1.2))
        }

        let roster = trains
        for t in roster where !t.finished {
            let overrun = CGFloat(t.spec.length) * Track.carUnit
            var ceiling = t.path.total + overrun
            if !t.boarded { ceiling = min(ceiling, t.berthDist) }
            var aheadTail = CGFloat.infinity
            for o in roster where o !== t && !o.finished && o.dist > t.dist {
                if o.platform == t.platform { aheadTail = min(aheadTail, o.dist - o.carLen) }
            }
            if aheadTail.isFinite { ceiling = min(ceiling, aheadTail - gap) }

            let headroom = max(0, ceiling - t.dist)
            let accel: CGFloat = 100, decel: CGFloat = 170
            let target = min(baseSpeed, sqrt(2 * decel * headroom))
            if t.v < target { t.v = min(target, t.v + accel * CGFloat(dt)) }
            else { t.v = max(target, t.v - decel * CGFloat(dt)) }
            t.dist = max(t.dist, min(t.dist + t.v * CGFloat(dt), ceiling))
            t.stopped = t.v < 5 ? t.stopped + dt : 0
            // Light the road ahead so each shuffle out to a platform and back reads at a glance.
            t.railAspect = railAspect(headroom: ceiling - t.dist, clearToEnd: ceiling >= t.path.total - 1)

            if t.dist >= t.berthDist - 0.5 && t.dist <= t.berthDist + Track.carUnit * 0.3 {
                if !t.started {
                    t.started = true; t.dwell = dwellTime; wait[t.platform] = 0
                    Sound.shared.play(.board)
                }
                t.dwell -= dt
                let cap = Double(t.spec.length) * perCar
                if t.load < cap && pax[t.platform] > 0 {
                    let take = min(boardOffRate * dt, min(cap - t.load, pax[t.platform]))
                    let before = pax[t.platform]
                    pax[t.platform] = max(0, pax[t.platform] - take)
                    if Int(before) != Int(pax[t.platform]) {
                        let k = Int(pax[t.platform])
                        sparkles.append(Sparkle(x: platL + 20 + CGFloat(k) * 14, y: platformY(t.platform) - 20))
                    }
                    t.load += take; carried += take
                }
                if t.dwell <= 0 { t.boarded = true }
            }
            if t.dist >= t.path.total + overrun { t.finished = true }
        }
        trains.removeAll { $0.finished }
        for i in sparkles.indices { sparkles[i].age += dt }
        sparkles.removeAll { $0.age > sparkleLife }

        for i in 0..<platformCount { over[i] = pax[i] >= platformCap ? over[i] + dt : 0 }
        peakFill = max(peakFill, (pax.max() ?? 0) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = levelStars(def, carried: Int(carried))
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
            Sound.shared.play(.win)
        } else if (over.max() ?? 0) > overflowGrace {
            outcome = .lost
            stars = levelStars(def, carried: Int(carried))
            Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }
}
