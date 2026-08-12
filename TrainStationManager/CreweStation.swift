import SwiftUI

/// Crewe — a big through junction of twelve platforms, built to the agreed plan:
///  • P1 through across the top
///  • P2–4 east-facing bays (buffers west), stacked on the right
///  • P5 / P6 platform lines with **two fast lines between them** that expresses fly through
///  • P7/8 west-facing bays and P9/10 east-facing bays around a central **concourse**
///  • P11 and P12 are the two faces of a single line across the bottom
///  • **West throat:** 4 tracks fan in, one turnout at a time. **East throat:** 7 tracks (5 + 2 fast).
///
/// This pass lays the geometry and runs traffic on the through platforms; the bays, the expresses on
/// the fast lines, and the breakdown-and-rescue mechanic build on top of it next.
enum CreweKind { case through, bayEast, bayWest }   // bayEast: buffers west, opens east · bayWest: mirror

struct CrewePlat {
    let id: Int
    let y: CGFloat            // the platform's running line
    let xL: CGFloat           // the track extent
    let xR: CGFloat
    let kind: CreweKind
    let slabAbove: Bool       // platform slab drawn above the line (P5) or below (everything else)
    var slabL: CGFloat? = nil // slab extent, if it differs from the track (a face on part of a through line)
    var slabR: CGFloat? = nil
    var ownsLine: Bool = true // false = a platform face that shares another platform's line (draws no track of its own)
    var through: Bool { kind == .through }
    var sLeft: CGFloat { slabL ?? xL }
    var sRight: CGFloat { slabR ?? xR }
}

final class CreweTrain: Identifiable {
    let id = UUID()
    var spec: Train
    var target: Int
    var path: RoutePath
    var berthDist: CGFloat = 0
    var dist: CGFloat = 0
    var committed = false
    var boarded = false
    var started = false
    var dwell = 0.0
    var load = 0.0
    var v: CGFloat = 0
    var stopped = 0.0
    var spawnedNext = false
    var entryLen: CGFloat = 0       // distance from the east spawn to the platform's east end
    var entryFast: CGFloat = 0      // which fast line it runs in through the throat
    var railAspect = 0
    var finished = false
    enum Phase { case arriving, berthed, departing }
    var phase: Phase = .arriving
    var carLen: CGFloat { spec.carLength }
    init(_ spec: Train, target: Int, _ path: RoutePath) { self.spec = spec; self.target = target; self.path = path }
}

@MainActor
final class CreweStation: ObservableObject {
    let def: StationDef
    var name: String { def.name }

    // Platform / track geometry (design space; wide and pannable). West = small x, East = large x.
    let plats: [CrewePlat]
    let fastY: [CGFloat] = [262, 316]     // the two fast lines between P5 and P6
    let singleY: CGFloat = 606            // the single line, faced by P11 (above) and P12 (below)
    let throatY: CGFloat = 289            // where the running lines bunch together in the throats
    let xSL: CGFloat = 300, xSR: CGFloat = 1300      // platform west / east ends
    let xW: CGFloat = -760, xE: CGFloat = 2360       // spawn / exit — long throats so the staggers feed in gently
    // West throat: 4 tracks gather over a long, gentle staircase.
    let xWMouth: CGFloat = -120                      // where the 4 tracks bunch together
    // East throat: 7 tracks (5 + 2 fast) fan over a staircase.
    let xEMouth: CGFloat = 1740
    let throughIds = [1, 5, 6, 7, 8]                  // the through lines traffic uses in this pass (bays/single come next)

    @Published var trains: [CreweTrain] = []
    @Published var carried = 0.0
    @Published var passengers: [Double]
    @Published var entranceOpen = true
    @Published var platformHeld: [Bool]              // each platform's starter: true = red, holds the boarded train
    @Published var outcome: GameOutcome = .playing
    @Published var stars = 0
    @Published var sparkles: [Sparkle] = []

    var animT = 0.0
    private var waitClock: [Double]
    let agitateAfter = 8.0
    func agitated(_ i: Int) -> Bool { passengers[i] > 0 && waitClock[i] > agitateAfter }
    func mood(_ i: Int) -> Mood {
        if passengers[i] < 1 { return .happy }
        if waitClock[i] > agitateAfter { return .cross }
        if waitClock[i] > agitateAfter * 0.55 { return .waiting }
        return .happy
    }

    let baseSpeed: CGFloat = 86
    let dwellTime = 2.4
    let perCar = 3.0
    let boardOffRate = 6.5
    let platformCap = 16.0
    let overflowGrace = 9.0

    private var spawnClock = 0.0, nextSpawn = 1.0
    private var paxClock = 0.0, nextPax = 1.0
    private var overflowClock: [Double]
    private var peakFill = 0.0
    private var platEntryLen: [CGFloat] = []          // east-spawn → platform-east-end distance, per platform

    /// The through-platform indices (0-based) actually served this pass.
    private var throughIdx: [Int] { plats.indices.filter { throughIds.contains(plats[$0].id) } }

    init(_ def: StationDef) {
        self.def = def
        let L = 300.0, R = 1300.0
        let midL = 720.0, midR = 900.0     // concourse gap between the middle bays
        plats = [
            CrewePlat(id: 1,  y: -30, xL: L,    xR: R,    kind: .through, slabAbove: true),    // platform above the line so the train isn't on it
            CrewePlat(id: 2,  y: 34,  xL: 820,  xR: R,    kind: .bayEast, slabAbove: false),
            CrewePlat(id: 3,  y: 88,  xL: 820,  xR: R,    kind: .bayEast, slabAbove: false),
            CrewePlat(id: 4,  y: 142, xL: 820,  xR: R,    kind: .bayEast, slabAbove: false),
            CrewePlat(id: 5,  y: 220, xL: L,    xR: R,    kind: .through, slabAbove: true),   // clear of 4 above and the fast lines below
            CrewePlat(id: 6,  y: 360, xL: L,    xR: R,    kind: .through, slabAbove: false),  // below the fast lines
            // 7/9 and 8/10 are the left and right faces of two straight-through lines (no concourse, no buffers)
            CrewePlat(id: 7,  y: 424, xL: L,    xR: R,    kind: .through, slabAbove: true,  slabL: L,    slabR: midL),
            CrewePlat(id: 9,  y: 424, xL: midR, xR: R,    kind: .through, slabAbove: true,  ownsLine: false),
            CrewePlat(id: 8,  y: 488, xL: L,    xR: R,    kind: .through, slabAbove: true,  slabL: L,    slabR: midL),
            CrewePlat(id: 10, y: 488, xL: midR, xR: R,    kind: .through, slabAbove: true,  ownsLine: false),
            CrewePlat(id: 11, y: 566, xL: L,    xR: R,    kind: .through, slabAbove: true,  ownsLine: false),   // top face of the single line
            CrewePlat(id: 12, y: 652, xL: L,    xR: R,    kind: .through, slabAbove: false, ownsLine: false),  // bottom face of the single line
        ]
        passengers = Array(repeating: 0, count: 12)
        platformHeld = Array(repeating: false, count: 12)
        waitClock = Array(repeating: 0, count: 12)
        overflowClock = Array(repeating: 0, count: 12)
        platEntryLen = plats.indices.map { entryLenOf(buildPath(to: $0), $0) }
        spawn()
    }

    /// The path-distance to a platform's west end — a train has cleared the platform once its tail passes here.
    private func platWestDist(_ i: Int) -> CGFloat { platEntryLen[i] + (xSR - plats[i].xL) }

    // MARK: geometry — the staircase throats

    /// The west throat gathers the four tracks over a long staircase: a platform holds its line to a
    /// staggered turnout `x`, then steps down onto the running line into the mouth. Higher platforms
    /// keep their line further in before stepping, so the tracks merge one at a time.
    /// Platforms branch off the two fast lines — those above the middle come off the top fast line, those
    /// below come off the bottom one. The further a platform sits from its fast line, the earlier it peels
    /// away, so they split off gradually, one at a time.
    func fastLineFor(_ y: CGFloat) -> CGFloat { y < throatY ? fastY[0] : fastY[1] }
    func throatOrder(_ y: CGFloat) -> Int { min(9, Int((abs(y - fastLineFor(y)) / 34).rounded())) }

    /// Throat geometry at one end. The outer platform groups gather into one line first, then that line
    /// joins its fast line (top group → top fast line, bottom group → bottom fast line). Platforms 5 and 6,
    /// which sit right against the fast lines, turn straight onto them.
    /// The east top group cascades: 1 and 2 merge, then into 3, then 4, then onto the top fast line — each
    /// merge staggered further out than the last.
    private func topCascade(from y: CGFloat) -> [CGPoint] {
        let ys = [plats[0].y, plats[1].y, plats[2].y, plats[3].y, fastY[0]]
        let r = ys.firstIndex(where: { abs($0 - y) < 6 }) ?? 0
        var pts = [CGPoint(x: xSR, y: y)]
        for m in (r + 1)...4 {
            let xm = xSR + 150 + CGFloat(m - 1) * 190     // each successive merge is further east
            pts.append(CGPoint(x: xm - 95, y: ys[m - 1])) // run along the current line
            pts.append(CGPoint(x: xm, y: ys[m]))          // then merge onto the next
        }
        pts.append(CGPoint(x: xE, y: fastY[0]))
        return pts
    }

    private func throatPoints(_ y: CGFloat, east: Bool) -> [CGPoint] {
        if east && y < plats[4].y - 20 { return topCascade(from: y) }   // 1→2→3→4→fast on the east
        let edge: CGFloat = east ? xSR : xSL
        let dir: CGFloat = east ? 1 : -1
        let far: CGFloat = east ? xE : xW
        let ord = CGFloat(min(6, throatOrder(y)))
        var pts: [CGPoint]
        if y < plats[4].y - 20 {                 // west top group (just P1): gather onto the top fast line
            let gy: CGFloat = 150
            pts = [CGPoint(x: edge, y: y), CGPoint(x: edge + dir * (80 + ord * 82), y: gy),
                   CGPoint(x: edge + dir * 660, y: gy), CGPoint(x: edge + dir * 830, y: fastY[0]), CGPoint(x: far, y: fastY[0])]
        } else if y > plats[5].y + 20 {          // bottom group: join a gathering line one at a time, then the bottom fast line
            let gy: CGFloat = 486
            pts = [CGPoint(x: edge, y: y), CGPoint(x: edge + dir * (80 + ord * 82), y: gy),
                   CGPoint(x: edge + dir * 660, y: gy), CGPoint(x: edge + dir * 830, y: fastY[1]), CGPoint(x: far, y: fastY[1])]
        } else {                                  // P5 / P6: straight onto their fast line
            let mergeX = edge + dir * (40 + ord * 120)
            pts = [CGPoint(x: edge, y: y), CGPoint(x: mergeX, y: fastLineFor(y)), CGPoint(x: far, y: fastLineFor(y))]
        }
        return east ? pts : pts.reversed()        // west runs far → platform
    }
    private func westThroatPoints(_ y: CGFloat) -> [CGPoint] { throatPoints(y, east: false) }
    private func eastThroatPoints(_ y: CGFloat) -> [CGPoint] { throatPoints(y, east: true) }

    /// Through-platform route — trains arrive **from the east**: in down the east throat, along the platform,
    /// out down the west throat.
    private func buildPath(to i: Int) -> RoutePath {
        let pl = plats[i]
        let pts = Array(eastThroatPoints(pl.y).reversed()) + Array(westThroatPoints(pl.y).reversed())
        return RoutePath(pts)
    }
    /// The east spawn → platform-east-end distance for platform `i`.
    private func entryLenOf(_ p: RoutePath, _ i: Int) -> CGFloat {
        p.distanceTo(vertex: eastThroatPoints(plats[i].y).count - 1)
    }

    // MARK: routing

    /// A platform is taken until the train on it has run its whole length clear of the platform's west end.
    private func platformTaken(_ i: Int, except t: CreweTrain? = nil) -> Bool {
        trains.contains { o in
            guard o !== t, !o.finished, o.target == i else { return false }
            return (o.dist - o.spec.carLength) < platWestDist(i)
        }
    }
    private func pickPlatform(except t: CreweTrain? = nil) -> Int {
        let free = throughIdx.filter { !platformTaken($0, except: t) }
        if let best = free.max(by: { passengers[$0] < passengers[$1] }) { return best }
        return throughIdx.min(by: { passengers[$0] < passengers[$1] }) ?? throughIdx.first ?? 0
    }

    func reset() {
        trains = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0
        passengers = Array(repeating: 0, count: 12)
        waitClock = Array(repeating: 0, count: 12)
        overflowClock = Array(repeating: 0, count: 12)
        entranceOpen = true; platformHeld = Array(repeating: false, count: 12); sparkles = []; animT = 0
        spawnClock = 0; nextSpawn = 1; paxClock = 0; nextPax = 1
        spawn()
        objectWillChange.send()
    }

    func toggleEntrance() { entranceOpen.toggle(); objectWillChange.send() }
    func toggleStarter(_ i: Int) { platformHeld[i].toggle(); objectWillChange.send() }

    /// A platform is occupied (its entry signal red) while a train is berthing or berthed on it.
    func platformOccupied(_ i: Int) -> Bool {
        trains.contains { !$0.finished && $0.target == i && ($0.phase == .berthed || ($0.phase == .arriving && $0.dist >= $0.entryLen)) }
    }

    private func spawn() {
        let len = def.trainLengths.randomElement() ?? 4
        let spec = Train(length: len, tint: trainPalette.randomElement() ?? .blue, name: "")
        let target = pickPlatform()
        let pl = plats[target]
        let path = buildPath(to: target)
        let t = CreweTrain(spec, target: target, path)
        t.entryLen = platEntryLen[target]
        t.entryFast = fastLineFor(pl.y)
        t.berthDist = t.entryLen + (xSR - (pl.xL + 180))   // pull in along the platform to its west portion
        t.committed = true
        trains.append(t)
    }

    // MARK: simulation

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        let step = baseSpeed * CGFloat(dt)
        let gap = Track.carUnit * 0.6
        animT += dt
        for i in passengers.indices { waitClock[i] = passengers[i] > 0 ? waitClock[i] + dt : 0 }

        paxClock += dt
        if paxClock >= nextPax {
            paxClock = 0
            if let p = throughIdx.randomElement(), passengers[p] < platformCap { passengers[p] += 1 }
            nextPax = Double.random(in: def.spawnRange)
        }
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            if trains.count < 6 { spawn() }
            nextSpawn = Double.random(in: def.spawnRange.lowerBound...(def.spawnRange.upperBound * 1.3))
        }

        let roster = trains
        var spawnCount = 0
        for idx in roster.indices {
            let t = roster[idx]
            guard !t.finished else { continue }
            switch t.phase {
            case .arriving:
                var ceiling = t.berthDist
                if !entranceOpen {
                    let stop = t.path.distanceTo(vertex: 1) - gap   // held at the east home signal
                    if stop >= t.dist { ceiling = min(ceiling, stop) }
                }
                // Hold behind any train genuinely ahead: on the same platform road, or ahead in the same
                // fast line while both are still gathering down the east throat.
                var aheadTail = CGFloat.infinity
                for o in roster where o !== t && !o.finished && o.dist > t.dist {
                    let sameFastInThroat = t.dist < t.entryLen && o.dist < o.entryLen && o.entryFast == t.entryFast
                    if o.target == t.target || sameFastInThroat {
                        aheadTail = min(aheadTail, o.dist - o.spec.carLength)
                    }
                }
                if aheadTail.isFinite { ceiling = min(ceiling, aheadTail - gap) }
                // Don't enter the platform until it's clear of the previous train — hold out at the entry.
                if t.dist < t.entryLen && platformTaken(t.target, except: t) {
                    ceiling = min(ceiling, t.entryLen - gap)
                }
                let next = min(t.dist + step, ceiling)
                t.stopped = next < t.dist + step - 0.01 && ceiling < t.berthDist ? t.stopped + dt : 0
                t.dist = max(t.dist, next)
                t.railAspect = railAspect(headroom: ceiling - t.dist, clearToEnd: ceiling >= t.berthDist - 1)
                if !t.spawnedNext && t.dist >= t.entryLen { t.spawnedNext = true; spawnCount += 1 }
                if t.dist >= t.berthDist {
                    t.dist = t.berthDist; t.phase = .berthed; t.stopped = 0
                    waitClock[t.target] = 0; t.dwell = dwellTime
                    Sound.shared.play(.board)
                }
            case .berthed:
                if t.dwell > 0 { t.dwell -= dt }
                let cap = Double(t.spec.length) * perCar
                if t.load < cap && passengers[t.target] > 0 {
                    let take = min(boardOffRate * dt, min(cap - t.load, passengers[t.target]))
                    let before = passengers[t.target]
                    passengers[t.target] = max(0, passengers[t.target] - take)
                    if Int(before) != Int(passengers[t.target]) {
                        let k = Int(passengers[t.target])
                        sparkles.append(Sparkle(x: plats[t.target].xL + 120 + CGFloat(k) * 15, y: plats[t.target].y + 24))
                    }
                    t.load += take; carried += take
                }
                t.railAspect = platformHeld[t.target] ? 2 : 0     // starter red holds it; green sends it away
                if t.dwell <= 0 && !platformHeld[t.target] { t.phase = .departing; Sound.shared.play(.depart) }
            case .departing:
                var ceiling = t.path.total + t.spec.carLength
                for o in roster where o !== t && !o.finished && o.target == t.target && o.dist > t.dist {
                    ceiling = min(ceiling, o.dist - o.spec.carLength - gap)
                }
                t.dist = max(t.dist, min(t.dist + step, ceiling))
                t.railAspect = railAspect(headroom: ceiling - t.dist, clearToEnd: ceiling >= t.path.total - 1)
                if t.dist >= t.path.total + t.spec.carLength { t.finished = true }
            }
        }
        if roster.contains(where: { $0.finished }) { trains.removeAll { $0.finished } }
        for _ in 0..<spawnCount { spawn() }
        for i in sparkles.indices { sparkles[i].age += dt }
        sparkles.removeAll { $0.age > sparkleLife }

        for i in passengers.indices { overflowClock[i] = passengers[i] >= platformCap ? overflowClock[i] + dt : 0 }
        peakFill = max(peakFill, (passengers.max() ?? 0) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = levelStars(def, carried: Int(carried))
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
            Sound.shared.play(.win)
        } else if overflowClock.contains(where: { $0 > overflowGrace }) {
            outcome = .lost
            stars = levelStars(def, carried: Int(carried))
            Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }

    // MARK: geometry exposed to the view

    func westThroat(_ y: CGFloat) -> [CGPoint] { westThroatPoints(y) }
    func eastThroat(_ y: CGFloat) -> [CGPoint] { eastThroatPoints(y) }
}
