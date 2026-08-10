import SwiftUI

/// Dawlish: the sea-wall station. Two through lines run along the coast between the red cliffs and
/// the sea, with a tunnel at each end. Trains emerge from a tunnel, call at their platform, and
/// carry on into the far tunnel. The player's signals hold or release each line.
final class DawTrain: Identifiable {
    let id = UUID()
    var spec: Train
    let dir: DawlishStation.Dir
    let path: RoutePath
    let berthDist: CGFloat
    var dist: CGFloat = 0
    var boarded = false
    var started = false
    var dwell = 0.0
    var toBoard = 0.0
    var finished = false
    var carLen: CGFloat { spec.carLength }
    init(_ spec: Train, _ dir: DawlishStation.Dir, _ path: RoutePath, berth: CGFloat) {
        self.spec = spec; self.dir = dir; self.path = path; berthDist = berth
    }
}

@MainActor
final class DawlishStation: ObservableObject {
    enum Dir { case east, west }
    let def: StationDef
    var name: String { def.name }

    // Geometry (design space W = 1200, H = 452)
    let upY: CGFloat = 246       // up line (eastbound), nearer the cliffs
    let downY: CGFloat = 302     // down line (westbound), nearer the sea
    let tunL: CGFloat = 96       // left tunnel mouth
    let tunR: CGFloat = 1104     // right tunnel mouth
    let platL: CGFloat = 430
    let platR: CGFloat = 770
    let pad: CGFloat = 320       // trains spawn / vanish this far beyond a tunnel

    @Published var trains: [DawTrain] = []
    @Published var carried = 0.0
    @Published var pUp = 1.0     // people on the up platform (eastbound)
    @Published var pDown = 1.0   // people on the down platform (westbound)
    @Published var upHeld = false     // starter signals: hold a line's trains at the platform
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

    let speed: CGFloat = 74
    let dwellTime = 2.4
    let perCar = 3.0
    let boardOffRate = 6.0
    let platformCap = 16.0
    let overflowGrace = 18.0

    let eastPath: RoutePath, westPath: RoutePath
    private let eBerth, wBerth: CGFloat
    private var spawnClock = 0.0, nextSpawn = 1.2
    private var paxClock = 0.0, nextPax = 1.2
    private var overUp = 0.0, overDown = 0.0
    private var peakFill = 0.0

    init(_ def: StationDef) {
        self.def = def
        // Eastbound: out of the left tunnel → up platform → into the right tunnel.
        eastPath = RoutePath([CGPoint(x: tunL - pad, y: upY), CGPoint(x: platR, y: upY),
                              CGPoint(x: tunR + pad, y: upY)])
        eBerth = eastPath.distanceTo(vertex: 1)
        // Westbound: out of the right tunnel → down platform → into the left tunnel.
        westPath = RoutePath([CGPoint(x: tunR + pad, y: downY), CGPoint(x: platL, y: downY),
                              CGPoint(x: tunL - pad, y: downY)])
        wBerth = westPath.distanceTo(vertex: 1)
        spawn(.east)
    }

    func toggle(_ dir: Dir) {
        if dir == .east { upHeld.toggle() } else { downHeld.toggle() }
        objectWillChange.send()
    }

    func reset() {
        trains = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0; sparkles = []
        pUp = 1; pDown = 1; overUp = 0; overDown = 0; upWait = 0; downWait = 0
        upHeld = false; downHeld = false
        spawnClock = 0; nextSpawn = 1.2; paxClock = 0; nextPax = 1.2
        spawn(.east)
        objectWillChange.send()
    }

    private func spawn(_ dir: Dir) {
        let spec = Train(length: def.trainLengths.randomElement() ?? 3,
                         tint: trainPalette.randomElement() ?? .blue, name: "")
        trains.append(dir == .east ? DawTrain(spec, .east, eastPath, berth: eBerth)
                                   : DawTrain(spec, .west, westPath, berth: wBerth))
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        let step = speed * CGFloat(dt)
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
            if trains.count < 8 { spawn(Bool.random() ? .east : .west) }
            nextSpawn = Double.random(in: def.spawnRange.lowerBound...(def.spawnRange.upperBound * 1.4))
        }

        let roster = trains
        for t in roster where !t.finished {
            let held = t.dir == .east ? upHeld : downHeld
            var ceiling = t.path.total
            if !t.boarded { ceiling = min(ceiling, t.berthDist) }      // stop to board
            else if held { ceiling = min(ceiling, t.berthDist) }        // held at the platform
            // don't run into the train ahead on the same line
            var aheadTail = CGFloat.infinity
            for o in roster where o !== t && o.dir == t.dir && !o.finished && o.dist > t.dist {
                aheadTail = min(aheadTail, o.dist - o.carLen)
            }
            if aheadTail.isFinite { ceiling = min(ceiling, aheadTail - gap) }
            t.dist = max(t.dist, min(t.dist + step, ceiling))

            // board once at the platform
            if !t.boarded && t.dist >= t.berthDist - 0.5 {
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
                        sparkles.append(Sparkle(x: (t.dir == .east ? platL + 20 : platR - 20 - CGFloat(k) * 15)
                                                   + (t.dir == .east ? CGFloat(k) * 15 : 0),
                                                y: t.dir == .east ? upY - 26 : downY + 34))
                    }
                    t.toBoard -= take; carried += take
                }
                if t.dwell <= 0 { t.boarded = true }
            }
            if t.dist >= t.path.total { t.finished = true; Sound.shared.play(.depart) }
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
