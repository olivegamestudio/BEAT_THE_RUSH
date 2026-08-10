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
    let exitW: CGFloat = -300    // west lines run well off-screen, past the pannable area
    let exitE: CGFloat = 1440    // eastbound leaves east — well off-screen, past the pannable area
    let entryE: CGFloat = 1440   // westbound arrives from the east — spawns off-screen, forms first
    let riverL: CGFloat = 628    // the Tamar — a vertical band the bridge crosses
    let riverR: CGFloat = 912

    // MARK: terrain — Saltash climbs steeply out of the Tamar, drawn as a coloured relief map

    static let reliefRect = CGRect(x: -120, y: -140, width: 1460, height: 760)

    /// Land height at a point. The Tamar is a low channel (negative = water); either side the land
    /// climbs, steeply right at the water's edge — that's the sharp rise up to Saltash's platforms
    /// on the Cornwall (west) bank — then eases as it reaches the town above.
    private static func elev(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let rL: CGFloat = 628, rR: CGFloat = 912
        if x >= rL && x <= rR { return -26 - 6 * sin(y / 44) }        // the river
        let d = x < rL ? (rL - x) : (x - rR)                          // distance onto the bank
        let steep: CGFloat = x < rL ? 1.0 : 0.72                      // west bank is the steep one
        var h = steep * 13 * pow(d, 0.62)                            // steep at the water, easing up
        h += 16 * sin(x / 160 + 0.5) * cos(y / 120)
        h += 10 * sin(y / 70)
        return h
    }

    /// Height → colour: deep/shallow water, then a crisp shoreline into green, olive, tan and high
    /// ground — muted to sit under the gameplay.
    private static func reliefColor(_ h: CGFloat) -> (UInt8, UInt8, UInt8) {
        // dark and muted so the tracks and trains clearly dominate
        let stops: [(CGFloat, (CGFloat, CGFloat, CGFloat))] = [
            (-140, (7, 13, 23)), (-2, (10, 24, 38)),
            (2, (15, 27, 20)), (70, (20, 33, 22)),
            (170, (34, 36, 24)), (300, (44, 40, 29)), (500, (54, 49, 40)),
        ]
        if h <= stops[0].0 { let c = stops[0].1; return (UInt8(c.0), UInt8(c.1), UInt8(c.2)) }
        if h >= stops.last!.0 { let c = stops.last!.1; return (UInt8(c.0), UInt8(c.1), UInt8(c.2)) }
        var lo = stops[0], hi = stops[1]
        for i in 0..<stops.count - 1 where h >= stops[i].0 && h <= stops[i + 1].0 {
            lo = stops[i]; hi = stops[i + 1]; break
        }
        let t = (h - lo.0) / (hi.0 - lo.0)
        return (UInt8(lo.1.0 + (hi.1.0 - lo.1.0) * t),
                UInt8(lo.1.1 + (hi.1.1 - lo.1.1) * t),
                UInt8(lo.1.2 + (hi.1.2 - lo.1.2) * t))
    }

    /// The coloured relief, rasterised once at low resolution (scaled up smooth when drawn).
    static let relief: CGImage = {
        let W = 292, H = 152
        var buf = [UInt8](repeating: 0, count: W * H * 4)
        for py in 0..<H {
            for px in 0..<W {
                let dx = reliefRect.minX + reliefRect.width * (CGFloat(px) + 0.5) / CGFloat(W)
                let dy = reliefRect.minY + reliefRect.height * (CGFloat(py) + 0.5) / CGFloat(H)
                let (r, g, b) = reliefColor(elev(dx, dy))
                let i = (py * W + px) * 4
                buf[i] = r; buf[i + 1] = g; buf[i + 2] = b; buf[i + 3] = 255
            }
        }
        let ctx = CGContext(data: &buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }()

    /// Contour lines over the land, in design space, built once via marching squares.
    static let contour: Path = {
        var lines = Path()
        let step: CGFloat = 26, level: CGFloat = 48
        var gx: CGFloat = -80
        while gx < 1300 {
            var gy: CGFloat = -120
            while gy < 580 {
                let tl = elev(gx, gy), tr = elev(gx + step, gy)
                let br = elev(gx + step, gy + step), bl = elev(gx, gy + step)
                var lv = (floor(min(min(tl, tr), min(br, bl)) / level) + 1) * level
                let hi = max(max(tl, tr), max(br, bl))
                while lv <= hi {
                    func lerp(_ p1: CGPoint, _ v1: CGFloat, _ p2: CGPoint, _ v2: CGFloat) -> CGPoint {
                        let t = (lv - v1) / (v2 - v1)
                        return CGPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t)
                    }
                    let TL = CGPoint(x: gx, y: gy), TR = CGPoint(x: gx + step, y: gy)
                    let BR = CGPoint(x: gx + step, y: gy + step), BL = CGPoint(x: gx, y: gy + step)
                    var p: [CGPoint] = []
                    if (tl < lv) != (tr < lv) { p.append(lerp(TL, tl, TR, tr)) }
                    if (tr < lv) != (br < lv) { p.append(lerp(TR, tr, BR, br)) }
                    if (br < lv) != (bl < lv) { p.append(lerp(BR, br, BL, bl)) }
                    if (bl < lv) != (tl < lv) { p.append(lerp(BL, bl, TL, tl)) }
                    if p.count >= 2 { lines.move(to: p[0]); lines.addLine(to: p[1]) }
                    if p.count == 4 { lines.move(to: p[2]); lines.addLine(to: p[3]) }
                    lv += level
                }
                gy += step
            }
            gx += step
        }
        return lines
    }()

    @Published var trains: [SaltTrain] = []
    @Published var bridgeGreen: Dir? = .east   // direction currently cleared onto the bridge; nil = both held
    @Published var carried = 0.0
    @Published var pTop = 1.0    // passengers on the top (eastbound) platform
    @Published var pBot = 1.0    // passengers on the bottom (westbound) platform
    @Published var sparkles: [Sparkle] = []
    @Published var outcome: GameOutcome = .playing
    @Published var stars = 0
    private var overTop = 0.0, overBot = 0.0   // seconds each platform has sat full
    private var peakFill = 0.0
    let overflowGrace = 18.0     // very forgiving on the first level

    var animT = 0.0                            // running clock, drives the agitation wiggle
    private var topWait = 0.0, botWait = 0.0   // seconds since a train last called at each platform
    let agitateAfter = 13.0                     // gentle first level — slow to grumble
    var topAgitated: Bool { pTop >= 1 && topWait > agitateAfter }
    var botAgitated: Bool { pBot >= 1 && botWait > agitateAfter }
    private func moodFor(_ wait: Double, _ p: Double) -> Mood {
        if p < 1 { return .happy }
        if wait > agitateAfter { return .cross }
        if wait > agitateAfter * 0.55 { return .waiting }
        return .happy
    }
    var topMood: Mood { moodFor(topWait, pTop) }
    var botMood: Mood { moodFor(botWait, pBot) }

    let speed: CGFloat = 66
    let dwellTime = 2.6
    let perCar = 3.0
    let boardOffRate = 6.0
    let platformCap = 16.0       // roomy — Saltash is the gentle first level, hard to overwhelm

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
        trains = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0; sparkles = []
        pTop = 1; pBot = 1; overTop = 0; overBot = 0; topWait = 0; botWait = 0
        bridgeGreen = .east
        spawnClock = 0; nextSpawn = 1.5; paxClock = 0; nextPax = 1.4
        spawn(.east)
        objectWillChange.send()
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }
        let step = speed * CGFloat(dt)
        let gap = Track.carUnit * 1.15     // keep clear air between queued trains

        animT += dt
        topWait = pTop >= 1 ? topWait + dt : 0
        botWait = pBot >= 1 ? botWait + dt : 0

        paxClock += dt
        if paxClock >= nextPax {
            paxClock = 0
            if Bool.random() { pTop = min(pTop + 1, platformCap) } else { pBot = min(pBot + 1, platformCap) }
            nextPax = Double.random(in: def.spawnRange)
        }
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            if trains.count < 7 { spawn(Bool.random() ? .east : .west) }   // don't let the queue run away
            nextSpawn = Double.random(in: (def.spawnRange.lowerBound * 1.7)...(def.spawnRange.upperBound * 2.2))
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
                    if t.dir == .east { topWait = 0 } else { botWait = 0 }   // a train's here, calm down
                    Sound.shared.play(.board)
                    sparkles.append(Sparkle(x: (platL + platR) / 2, y: t.dir == .east ? yTop : yBot))
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
                Sound.shared.play(.ding)        // the level-crossing bell as a train takes the bridge
            }
            // free the bridge once our tail is clear of it
            if t.hasBridge && (t.dist - t.carLen) > t.bridgeExit {
                t.hasBridge = false; if occupant === t { occupant = nil }
            }
            if t.dist >= t.path.total {
                t.finished = true; if occupant === t { occupant = nil }
                Sound.shared.play(.depart)
            }
        }
        trains.removeAll { $0.finished }
        for i in sparkles.indices { sparkles[i].age += dt }
        sparkles.removeAll { $0.age > sparkleLife }

        // Win at the goal; lose if either platform sits full too long.
        overTop = pTop >= platformCap ? overTop + dt : 0
        overBot = pBot >= platformCap ? overBot + dt : 0
        peakFill = max(peakFill, max(pTop, pBot) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = starsFor(peakFill: peakFill)
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
            Sound.shared.play(.win)
        } else if overTop > overflowGrace || overBot > overflowGrace {
            outcome = .lost
            Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }
}
