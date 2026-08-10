import SwiftUI

/// Saltash: two platforms with two running lines between them, feeding a single-track
/// bridge (the Royal Albert Bridge) off the east end. Trains find their own way to a platform
/// and out; only one may be on the bridge at a time, so the two directions take turns. The
/// player's only control is the signals — tap a red one to clear that direction onto the bridge.
final class SaltTrain: Identifiable {
    let id = UUID()
    var spec: Train
    let dir: SaltashStation.Dir
    let path: RoutePath
    let berthDist: CGFloat
    let bridgeEnter: CGFloat
    let bridgeExit: CGFloat
    var dist: CGFloat = 0
    var boarded = false
    var dwell = 0.0
    var toBoard = 0.0
    var started = false
    var hasBridge = false
    var finished = false
    var blocked = false
    var carLen: CGFloat { spec.carLength }

    init(_ spec: Train, _ dir: SaltashStation.Dir, _ path: RoutePath,
         berth: CGFloat, enter: CGFloat, exit: CGFloat) {
        self.spec = spec; self.dir = dir; self.path = path
        berthDist = berth; bridgeEnter = enter; bridgeExit = exit
    }
}

@MainActor
final class SaltashStation: ObservableObject {
    enum Dir { case east, west }
    let def: StationDef
    var name: String { def.name }

    // Geometry (design space W=960, H=452)
    let yTop: CGFloat = 196      // top running line — eastbound (trains drive on the left)
    let yBot: CGFloat = 256      // bottom running line — westbound
    let yBridge: CGFloat = 226   // the single bridge line
    let xMerge: CGFloat = 542    // west throat: the two platform lines converge to the bridge
    let xBridgeW: CGFloat = 590  // west end of the bridge
    let xBridgeE: CGFloat = 950  // east end of the bridge (three arches long)
    let xMergeE: CGFloat = 998   // east throat: the bridge splits back to two lines
    let platL: CGFloat = 314     // platforms sit right by the bridge
    let platR: CGFloat = 534
    let exitW: CGFloat = -90
    let exitE: CGFloat = 1120    // eastbound leaves east on the bottom line
    let entryE: CGFloat = 1180   // westbound arrives from the east on the top line
    let riverL: CGFloat = 628    // the Tamar — a vertical band the bridge crosses
    let riverR: CGFloat = 912

    @Published var trains: [SaltTrain] = []
    @Published var bridgeGreen: Dir? = .east   // direction currently cleared onto the bridge; nil = both held
    @Published var carried = 0.0
    @Published var pTop = 1.0    // passengers on the top (eastbound) platform
    @Published var pBot = 1.0    // passengers on the bottom (westbound) platform
    @Published var outcome: GameOutcome = .playing
    @Published var stars = 0
    private var overTop = 0.0, overBot = 0.0   // seconds each platform has sat full
    private var peakFill = 0.0
    let overflowGrace = 8.0

    let speed: CGFloat = 66
    let dwellTime = 2.6
    let perCar = 3.0
    let boardOffRate = 6.0
    let platformCap = 12.0

    let eastPath: RoutePath, westPath: RoutePath
    private let eBerth, eEnter, eExit: CGFloat
    private let wBerth, wEnter, wExit: CGFloat
    private var spawnClock = 0.0, nextSpawn = 1.5
    private var paxClock = 0.0, nextPax = 1.4
    private weak var occupant: SaltTrain?

    init(_ def: StationDef) {
        self.def = def
        // Eastbound runs on the top line (left-hand running): in from the west → top platform →
        // west throat → bridge → east throat back to the top line → out east.
        eastPath = RoutePath([CGPoint(x: exitW, y: yTop), CGPoint(x: platR, y: yTop),
                              CGPoint(x: xMerge, y: yTop), CGPoint(x: xBridgeW, y: yBridge),
                              CGPoint(x: xBridgeE, y: yBridge), CGPoint(x: xMergeE, y: yTop),
                              CGPoint(x: exitE, y: yTop)])
        eBerth = eastPath.distanceTo(vertex: 1)
        eEnter = eastPath.distanceTo(vertex: 3)
        eExit  = eastPath.distanceTo(vertex: 4)
        // Westbound runs on the bottom line: in from the east → east throat → bridge → west
        // throat → bottom platform → out west. Its own track each side, never shared.
        westPath = RoutePath([CGPoint(x: entryE, y: yBot), CGPoint(x: xMergeE, y: yBot),
                              CGPoint(x: xBridgeE, y: yBridge), CGPoint(x: xBridgeW, y: yBridge),
                              CGPoint(x: xMerge, y: yBot), CGPoint(x: platL, y: yBot),
                              CGPoint(x: exitW, y: yBot)])
        wEnter = westPath.distanceTo(vertex: 2)
        wExit  = westPath.distanceTo(vertex: 3)
        wBerth = westPath.distanceTo(vertex: 5)
        spawn(.east)
    }

    /// Tap a signal: clear that direction (green), or hold both (red) if it was already cleared.
    /// Only one direction is ever cleared — the single line makes the two take turns.
    func clear(_ dir: Dir) { bridgeGreen = (bridgeGreen == dir) ? nil : dir; objectWillChange.send() }

    /// Green portal (a direction may enter the bridge): it's cleared and the bridge is empty.
    func portalGreen(_ dir: Dir) -> Bool { bridgeGreen == dir && occupant == nil }

    /// The near end of a train's platform — trains wait here rather than piling onto the platform.
    private func platEntryDist(_ t: SaltTrain) -> CGFloat { t.berthDist - (platR - platL) }
    /// Is a same-direction train standing on that direction's platform right now?
    private func platformBusy(_ dir: Dir, except t: SaltTrain? = nil) -> Bool {
        trains.contains { o in
            o !== t && o.dir == dir && !o.finished
                && o.dist >= platEntryDist(o) - 1 && o.dist < o.berthDist + Track.carUnit
        }
    }
    var topBusy: Bool { platformBusy(.east) }   // eastbound platform (top) occupied
    var botBusy: Bool { platformBusy(.west) }   // westbound platform (bottom) occupied

    private func spawn(_ dir: Dir) {
        let spec = Train(length: def.trainLengths.randomElement() ?? 3,
                         tint: trainPalette.randomElement() ?? .blue, name: "")
        if dir == .east {
            trains.append(SaltTrain(spec, .east, eastPath, berth: eBerth, enter: eEnter, exit: eExit))
        } else {
            trains.append(SaltTrain(spec, .west, westPath, berth: wBerth, enter: wEnter, exit: wExit))
        }
    }

    func reset() {
        trains = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0
        pTop = 1; pBot = 1; overTop = 0; overBot = 0
        bridgeGreen = .east
        spawnClock = 0; nextSpawn = 1.5; paxClock = 0; nextPax = 1.4
        spawn(.east)
        objectWillChange.send()
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        let step = speed * CGFloat(dt)
        let gap = Track.carUnit * 1.15     // keep clear air between queued trains

        paxClock += dt
        if paxClock >= nextPax {
            paxClock = 0
            if Bool.random() { pTop = min(pTop + 1, platformCap) } else { pBot = min(pBot + 1, platformCap) }
            nextPax = Double.random(in: def.spawnRange)
        }
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            spawn(Bool.random() ? .east : .west)
            nextSpawn = Double.random(in: (def.spawnRange.lowerBound * 1.3)...(def.spawnRange.upperBound * 1.7))
        }

        let roster = trains
        for t in roster where !t.finished {
            var ceiling = t.path.total
            // wait at the platform until boarding is done
            if !t.boarded { ceiling = min(ceiling, t.berthDist) }
            // hold at the platform's near end while a same-direction train still stands on it,
            // so trains never queue onto the platform itself
            if t.dist < platEntryDist(t) && platformBusy(t.dir, except: t) {
                ceiling = min(ceiling, platEntryDist(t) - gap)
            }
            // wait short of the bridge unless it's granted to us
            if !t.hasBridge && t.dist < t.bridgeEnter {
                let readyToCross = t.dir == .west || t.boarded    // eastbound must board first
                if !(readyToCross && portalGreen(t.dir)) {
                    ceiling = min(ceiling, t.bridgeEnter - gap)
                }
            }
            // don't run into the nearest same-direction train ahead
            var aheadTail = CGFloat.infinity
            for o in roster where o !== t && o.dir == t.dir && !o.finished && o.dist > t.dist {
                aheadTail = min(aheadTail, o.dist - o.carLen)
            }
            if aheadTail.isFinite { ceiling = min(ceiling, aheadTail - gap) }

            let next = min(t.dist + step, ceiling)
            t.blocked = next < t.dist + step - 0.01 && next < t.path.total - 1
            t.dist = max(t.dist, next)

            // board at the platform
            if !t.boarded && t.dist >= t.berthDist - 0.5 {
                if !t.started {
                    t.started = true
                    t.dwell = dwellTime
                    t.toBoard = min(t.dir == .east ? pTop : pBot, Double(t.spec.length) * perCar)
                }
                t.dwell -= dt
                if t.toBoard > 0 {
                    let take = min(boardOffRate * dt, t.toBoard)
                    if t.dir == .east { pTop = max(0, pTop - take) } else { pBot = max(0, pBot - take) }
                    t.toBoard -= take; carried += take
                }
                if t.dwell <= 0 { t.boarded = true }
            }
            // take the bridge when at the portal, our turn, and it's clear
            if !t.hasBridge && occupant == nil && portalGreen(t.dir)
                && t.dist >= t.bridgeEnter - gap - 1 && (t.dir == .west || t.boarded) {
                t.hasBridge = true; occupant = t
            }
            // free the bridge once our tail is clear of it
            if t.hasBridge && (t.dist - t.carLen) > t.bridgeExit {
                t.hasBridge = false; if occupant === t { occupant = nil }
            }
            if t.dist >= t.path.total { t.finished = true; if occupant === t { occupant = nil } }
        }
        trains.removeAll { $0.finished }

        // Win at the goal; lose if either platform sits full too long.
        overTop = pTop >= platformCap ? overTop + dt : 0
        overBot = pBot >= platformCap ? overBot + dt : 0
        peakFill = max(peakFill, max(pTop, pBot) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = starsFor(peakFill: peakFill)
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
        } else if overTop > overflowGrace || overBot > overflowGrace {
            outcome = .lost
        }
        objectWillChange.send()
    }
}
