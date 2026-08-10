import SwiftUI

/// Saltash: two platforms with two running lines between them, feeding a single-track
/// bridge (the Royal Albert Bridge) off the east end. Eastbound trains call at the
/// bottom platform then cross the bridge; westbound trains cross the bridge then call at
/// the top platform. Only one train may be on the bridge at a time, so the two directions
/// take turns — the player gives the bridge to a direction by tapping it.
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
    let yTop: CGFloat = 196      // top running line (westbound, west of the bridge)
    let yBot: CGFloat = 256      // bottom running line (eastbound)
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
    @Published var bridgeDir: Dir = .east
    @Published var carried = 0.0
    @Published var pTop = 1.0    // passengers on the top (westbound) platform
    @Published var pBot = 1.0    // passengers on the bottom (eastbound) platform

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
        // Eastbound: in from the west on the bottom line → bottom platform → west throat →
        // bridge → east throat back to the bottom line → out east.
        eastPath = RoutePath([CGPoint(x: exitW, y: yBot), CGPoint(x: platR, y: yBot),
                              CGPoint(x: xMerge, y: yBot), CGPoint(x: xBridgeW, y: yBridge),
                              CGPoint(x: xBridgeE, y: yBridge), CGPoint(x: xMergeE, y: yBot),
                              CGPoint(x: exitE, y: yBot)])
        eBerth = eastPath.distanceTo(vertex: 1)
        eEnter = eastPath.distanceTo(vertex: 3)
        eExit  = eastPath.distanceTo(vertex: 4)
        // Westbound: in from the east on the top line → east throat → bridge → west throat →
        // top platform → out west. Its own track each side, so it never shares with eastbound.
        westPath = RoutePath([CGPoint(x: entryE, y: yTop), CGPoint(x: xMergeE, y: yTop),
                              CGPoint(x: xBridgeE, y: yBridge), CGPoint(x: xBridgeW, y: yBridge),
                              CGPoint(x: xMerge, y: yTop), CGPoint(x: platL, y: yTop),
                              CGPoint(x: exitW, y: yTop)])
        wEnter = westPath.distanceTo(vertex: 2)
        wExit  = westPath.distanceTo(vertex: 3)
        wBerth = westPath.distanceTo(vertex: 5)
        spawn(.east)
    }

    func toggleBridge() { bridgeDir = bridgeDir == .east ? .west : .east; objectWillChange.send() }

    /// Green portal (a direction may enter the bridge): its turn and the bridge is clear.
    func portalGreen(_ dir: Dir) -> Bool { bridgeDir == dir && occupant == nil }

    private func spawn(_ dir: Dir) {
        let spec = Train(length: def.trainLengths.randomElement() ?? 3,
                         tint: trainPalette.randomElement() ?? .blue, name: "")
        if dir == .east {
            trains.append(SaltTrain(spec, .east, eastPath, berth: eBerth, enter: eEnter, exit: eExit))
        } else {
            trains.append(SaltTrain(spec, .west, westPath, berth: wBerth, enter: wEnter, exit: wExit))
        }
    }

    func tick(_ dt: Double) {
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
                    t.toBoard = min(t.dir == .east ? pBot : pTop, Double(t.spec.length) * perCar)
                }
                t.dwell -= dt
                if t.toBoard > 0 {
                    let take = min(boardOffRate * dt, t.toBoard)
                    if t.dir == .east { pBot = max(0, pBot - take) } else { pTop = max(0, pTop - take) }
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
        objectWillChange.send()
    }
}
