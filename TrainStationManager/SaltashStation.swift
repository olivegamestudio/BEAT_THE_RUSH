import SwiftUI

/// Saltash — the first level built on **RailKit** (the shared level toolkit, see docs/DESIGN.md).
/// Its layout is declared as a track graph, its filter signals and bridge levers are typed RailKit
/// signals, and its trains are driven by the shared `RailSim` movement engine. Everything unique to
/// Saltash — boarding, the single-line bridge that the two directions take turns over, the spawn
/// balancing — plugs into the sim through hooks, so the machinery it shares with every other level
/// lives in RailKit, not here.
///
/// Two platforms with two running lines between them, feeding a single-track bridge (the Royal Albert
/// Bridge) off the east end. Trains find their own way to a platform and out; only one may be on the
/// bridge at a time, so the two directions take turns. The player's only control is the signals —
/// tap a red one to clear that direction onto the bridge.
final class SaltTrain: RailVehicle {
    let dir: SaltashStation.Dir
    let berthDist: CGFloat
    let bridgeEnter: CGFloat
    let bridgeExit: CGFloat
    var boarded = false
    var dwell = 0.0
    var load = 0.0               // people already aboard — keeps topping up until the train pulls away
    var started = false
    var hasBridge = false

    init(_ spec: Train, _ dir: SaltashStation.Dir, _ path: RoutePath,
         berth: CGFloat, enter: CGFloat, exit: CGFloat) {
        self.dir = dir; berthDist = berth; bridgeEnter = enter; bridgeExit = exit
        super.init(spec: spec, path: path, lane: dir == .east ? 0 : 1)
    }
}

@MainActor
final class SaltashStation: ObservableObject {
    enum Dir { case east, west; var key: String { self == .east ? "east" : "west" } }
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

    // MARK: RailKit composition — a graph, typed signals, and the shared movement engine

    /// The track diagram (RailKit piece 1). Saltash's two running routes are stitched from it.
    let graph: RailGraph
    /// The movement engine (RailKit piece 3) — owns the trains and drives their kinematics.
    let sim: RailSim<SaltTrain>
    /// The two bridge levers (RailKit piece 2): a radio group, so only one direction is ever cleared
    /// onto the single line at a time — the two take turns.
    let bridgeGroup: HoldGroup
    /// The automatic three-aspect filter signals down each approach (RailKit piece 2).
    private(set) var blockSignalsEast: [BlockSignal] = []
    private(set) var blockSignalsWest: [BlockSignal] = []

    // MARK: published game state

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
    let agitateAfter = 26.0                     // gentle first level — very slow to grumble
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

    // Automatic three-aspect block signals on the two approaches to the bridge: green/amber/red as
    // the queue builds. A train eases to caution speed at an amber; the queue itself (trains stopping
    // behind each other) is what turns them red.
    let blockXsEast: [CGFloat] = [40, 200, 460]      // top line (eastbound), the western approach
    let blockXsWest: [CGFloat] = [1340, 1160, 1060]  // bottom line (westbound), the eastern approach
    private let blockLen: CGFloat = 200

    /// The live trains, from the sim — the view reads this each frame.
    var trains: [SaltTrain] { sim.vehicles }

    init(_ def: StationDef) {
        self.def = def

        // --- RailKit piece 1: the track graph. Declare Saltash's lines as named nodes + edges, then
        // let the graph stitch the two running routes. The bridge edge (brW—brE) is *shared*:
        // eastbound runs it west→east, westbound east→west, so the single line falls straight out of
        // one shared edge rather than being coordinated by hand.
        var g = RailGraph()
        for n in [RailNode("eIn",   x: exitW,    y: yTop),
                  RailNode("topP",  x: platR,    y: yTop),
                  RailNode("wThrT", x: xMerge,   y: yTop),
                  RailNode("brW",   x: xBridgeW, y: yBridge),
                  RailNode("brE",   x: xBridgeE, y: yBridge),
                  RailNode("eThrT", x: xMergeE,  y: yTop),
                  RailNode("eOut",  x: exitE,    y: yTop),
                  RailNode("wIn",   x: entryE,   y: yBot),
                  RailNode("eThrB", x: xMergeE,  y: yBot),
                  RailNode("wThrB", x: xMerge,   y: yBot),
                  RailNode("botP",  x: platL,    y: yBot),
                  RailNode("wOut",  x: exitW,    y: yBot)] { g.add(n) }
        for e in [RailEdge("e0", "eIn", "topP"),  RailEdge("e1", "topP", "wThrT"),
                  RailEdge("e2", "wThrT", "brW"),  RailEdge("bridge", "brW", "brE"),
                  RailEdge("e3", "brE", "eThrT"),  RailEdge("e4", "eThrT", "eOut"),
                  RailEdge("w0", "wIn", "eThrB"),  RailEdge("w1", "eThrB", "brE"),
                  RailEdge("w2", "brW", "wThrB"),  RailEdge("w3", "wThrB", "botP"),
                  RailEdge("w4", "botP", "wOut")] { g.add(e) }
        graph = g

        // Eastbound: in from the west → top platform → west throat → bridge → east throat → out east.
        eastPath = g.route(["eIn", "topP", "wThrT", "brW", "brE", "eThrT", "eOut"])
        // Westbound: in from the east → east throat → bridge → west throat → bottom platform → out.
        westPath = g.route(["wIn", "eThrB", "brE", "brW", "wThrB", "botP", "wOut"])
        eBerth = eastPath.distanceTo(vertex: 1)
        eEnter = eastPath.distanceTo(vertex: 3)
        eExit  = eastPath.distanceTo(vertex: 4)
        wEnter = westPath.distanceTo(vertex: 2)
        wExit  = westPath.distanceTo(vertex: 3)
        wBerth = westPath.distanceTo(vertex: 5)

        // --- RailKit piece 2: the signals. Two player levers (the bridge portals) as a radio group,
        // and a chain of automatic filter signals down each approach.
        bridgeGroup = HoldGroup([HoldSignal("east", at: CGPoint(x: xMerge + 6, y: yTop)),
                                 HoldSignal("west", at: CGPoint(x: xMergeE - 6, y: yBot))])
        let eSigs = blockXsEast.map {
            BlockSignal("bE\($0)", at: CGPoint(x: $0, y: yTop - 26), axis: $0, forward: 1, blockLen: blockLen)
        }
        let wSigs = blockXsWest.map {
            BlockSignal("bW\($0)", at: CGPoint(x: $0, y: yBot + 26), axis: $0, forward: -1, blockLen: blockLen)
        }
        if eSigs.count > 1 { for i in 0..<eSigs.count - 1 { eSigs[i].next = eSigs[i + 1] } }
        if wSigs.count > 1 { for i in 0..<wSigs.count - 1 { wSigs[i].next = wSigs[i + 1] } }
        blockSignalsEast = eSigs
        blockSignalsWest = wSigs

        // --- RailKit piece 3: the movement engine.
        sim = RailSim(kin: RailKinematics(speedCap: speed))

        // Everything above is stored; self is now fully initialised, so the hooks that reference it
        // can be wired and the first train spawned.
        bridgeGroup.grant("east")
        configureSim()
        spawn(.east)
    }

    /// Wire the level's rules into the shared engine: what holds a train, when it eases to caution,
    /// what happens as it advances, and what to do when it clears the level.
    private func configureSim() {
        // Extra movement authority: the berth (board before moving on), the platform's near end (don't
        // queue onto a busy platform), and the bridge (hold short unless it's our turn and it's clear).
        sim.ceiling = { [weak self] t, _ in
            guard let self else { return .infinity }
            let gap = self.sim.kin.followGap
            var c = CGFloat.infinity
            if !t.boarded { c = min(c, t.berthDist) }
            if t.dist < self.platEntryDist(t) && self.platformBusy(t.dir, except: t) {
                c = min(c, self.platEntryDist(t) - gap)
            }
            if !t.hasBridge && t.dist < t.bridgeEnter {
                let ready = t.dir == .west || t.boarded          // eastbound must board before crossing
                if !(ready && self.portalGreen(t.dir)) { c = min(c, t.bridgeEnter - gap) }
            }
            return c
        }
        // Ease to caution speed while running up to an amber filter signal ahead.
        sim.speedLimit = { [weak self] t in
            guard let self else { return .infinity }
            let fx = t.path.sample(t.dist).p.x
            let xs = t.dir == .east ? self.blockXsEast : self.blockXsWest
            for sx in xs where (t.dir == .east ? sx > fx : sx < fx) && self.blockAspect(sx, t.dir) == 1 {
                return self.speed * 0.5
            }
            return .infinity
        }
        // After each advance: board at the platform, then take/free the single-line bridge.
        sim.onAdvance = { [weak self] t, dt in
            guard let self else { return }
            self.serveBoarding(t, dt)
            self.serveBridge(t)
        }
        // Off the far end: free the bridge if it was still ours, and sound the departure.
        sim.onFinish = { [weak self] t in
            guard let self else { return }
            if self.occupant === t { self.occupant = nil }
            Sound.shared.play(.depart)
        }
    }

    /// Tap a signal: clear that direction (green), or hold both (red) if it was already cleared.
    /// Only one direction is ever cleared — the single line makes the two take turns.
    func clear(_ dir: Dir) { bridgeGroup.toggle(dir.key); objectWillChange.send() }

    /// The direction currently cleared onto the bridge (nil = both held) — for the view's signals.
    var bridgeGreen: Dir? {
        switch bridgeGroup.granted { case "east": return .east; case "west": return .west; default: return nil }
    }

    /// Green portal (a direction may enter the bridge): it's cleared and the bridge is empty.
    func portalGreen(_ dir: Dir) -> Bool { bridgeGroup.isCleared(dir.key) && occupant == nil }

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

    /// Refresh every filter signal from the live train positions in its direction.
    private func updateBlockSignals() {
        for s in blockSignalsEast {
            s.update { r in self.trains.contains { !$0.finished && $0.dir == .east && $0.xExtent.overlaps(r) } }
        }
        for s in blockSignalsWest {
            s.update { r in self.trains.contains { !$0.finished && $0.dir == .west && $0.xExtent.overlaps(r) } }
        }
    }
    /// A signal's aspect at approach position `x`: 2 = red, 1 = amber, 0 = green.
    func blockAspect(_ x: CGFloat, _ dir: Dir) -> Int {
        let arr = dir == .east ? blockSignalsEast : blockSignalsWest
        return arr.first { abs($0.axis - x) < 0.5 }?.aspect ?? 0
    }

    /// Board while standing at the platform. It keeps topping up from newly-arrived passengers (up to
    /// its capacity) until it pulls away — once it's moved off the berth, no more can board.
    private func serveBoarding(_ t: SaltTrain, _ dt: Double) {
        guard t.dist >= t.berthDist - 0.5 && t.dist <= t.berthDist + Track.carUnit * 0.3 else { return }
        if !t.started {
            t.started = true
            t.dwell = dwellTime
            if t.dir == .east { topWait = 0 } else { botWait = 0 }   // a train's here, calm down
            Sound.shared.play(.board)
        }
        t.dwell -= dt
        let cap = Double(t.spec.length) * perCar
        let plat = t.dir == .east ? pTop : pBot
        if t.load < cap && plat > 0 {
            let take = min(boardOffRate * dt, min(cap - t.load, plat))
            let before = plat
            if t.dir == .east { pTop = max(0, pTop - take) } else { pBot = max(0, pBot - take) }
            let after = t.dir == .east ? pTop : pBot
            if Int(before) != Int(after) {        // a whole person boarded — sparkle where they stood
                let k = Int(after)
                sparkles.append(Sparkle(x: platL + 16 + CGFloat(k) * 15,
                                        y: t.dir == .east ? yTop - 28 : yBot + 38))
            }
            t.load += take; carried += take
        }
        if t.dwell <= 0 { t.boarded = true }
    }

    /// Take the bridge when at the portal, our turn, and it's clear; free it once our tail is off it.
    private func serveBridge(_ t: SaltTrain) {
        if !t.hasBridge && occupant == nil && portalGreen(t.dir)
            && t.dist >= t.bridgeEnter - sim.kin.followGap - 1 && (t.dir == .west || t.boarded) {
            t.hasBridge = true; occupant = t
            Sound.shared.play(.ding)        // the level-crossing bell as a train takes the bridge
        }
        if t.hasBridge && (t.dist - t.carLen) > t.bridgeExit {
            t.hasBridge = false; if occupant === t { occupant = nil }
        }
    }

    private func spawn(_ dir: Dir) {
        // Small locals are green; the occasional longer express is a red or a green operator.
        let express = Double.random(in: 0...1) < def.expressChance
        let len = express ? Int.random(in: 5...6) : (def.trainLengths.randomElement() ?? 3)
        let green = Color(red: 0.16, green: 0.62, blue: 0.32), red = Color(red: 0.85, green: 0.18, blue: 0.22)
        let tint = express ? (Bool.random() ? red : green) : green
        let spec = Train(length: len, tint: tint, name: "")
        if dir == .east {
            sim.vehicles.append(SaltTrain(spec, .east, eastPath, berth: eBerth, enter: eEnter, exit: eExit))
        } else {
            sim.vehicles.append(SaltTrain(spec, .west, westPath, berth: wBerth, enter: wEnter, exit: wExit))
        }
    }

    func reset() {
        sim.vehicles = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0; sparkles = []
        pTop = 1; pBot = 1; overTop = 0; overBot = 0; topWait = 0; botWait = 0
        occupant = nil
        bridgeGroup.grant("east")
        spawnClock = 0; nextSpawn = 1.5; paxClock = 0; nextPax = 1.4
        spawn(.east)
        objectWillChange.send()
    }

    func tick(_ dt: Double) {
        guard outcome == .playing else { return }

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
            if trains.count < 7 {
                // Balance the two approaches — eastbounds must board before the bridge, so they clear
                // the west side more slowly and would otherwise pile up. Feed whichever side has fewer.
                let east = trains.filter { $0.dir == .east && !$0.finished }.count
                let west = trains.filter { $0.dir == .west && !$0.finished }.count
                let dir: Dir = east > west + 1 ? .west : (west > east + 1 ? .east : (Bool.random() ? .east : .west))
                spawn(dir)
            }
            nextSpawn = Double.random(in: (def.spawnRange.lowerBound * 1.7)...(def.spawnRange.upperBound * 2.2))
        }

        // Refresh the filter signals, then let the shared engine advance every train.
        updateBlockSignals()
        sim.step(dt)

        for i in sparkles.indices { sparkles[i].age += dt }
        sparkles.removeAll { $0.age > sparkleLife }

        // Win at the goal; lose if either platform sits full too long.
        overTop = pTop >= platformCap ? overTop + dt : 0
        overBot = pBot >= platformCap ? overBot + dt : 0
        peakFill = max(peakFill, max(pTop, pBot) / platformCap)
        if carried >= Double(def.goal) {
            outcome = .won
            stars = levelStars(def, carried: Int(carried))
            Progress.record(stars: stars, at: def.id)
            Progress.clear(def.id)
            Sound.shared.play(.win)
        } else if overTop > overflowGrace || overBot > overflowGrace {
            outcome = .lost
            stars = levelStars(def, carried: Int(carried))
            Sound.shared.play(.lose)
        }
        objectWillChange.send()
    }
}
