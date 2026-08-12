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
    var lineOverride: CGFloat? = nil   // the running line a train berths on, when it differs from the slab (the single line)
    var through: Bool { kind == .through }
    var sLeft: CGFloat { slabL ?? xL }
    var sRight: CGFloat { slabR ?? xR }
    var lineY: CGFloat { lineOverride ?? y }   // where a train actually stands — the slab is just alongside it
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
    var turnoutDist: CGFloat = 0    // distance to the entry turnout, where a red platform signal holds it
    var homeStop: CGFloat = 0       // path distance at which the nose reaches the home signal
    var railAspect = 0
    var finished = false
    var isBay = false               // a terminating bay service: it reverses back out the way it came in
    var owningReverse = false       // holds the top-throat reservation while it backs out
    enum Phase { case arriving, berthed, departing, reversing }
    var phase: Phase = .arriving
    var carLen: CGFloat { spec.carLength }
    init(_ spec: Train, target: Int, _ path: RoutePath) { self.spec = spec; self.target = target; self.path = path }
}

/// A fly-through express — it runs the full length of one of the two fast lines and never stops. It shares
/// no track with the platform traffic, so it just streaks across the middle at speed.
final class CreweExpress: Identifiable {
    let id = UUID()
    var spec: Train
    let line: CGFloat
    var path: RoutePath
    var dist: CGFloat = 0
    var finished = false
    var carLen: CGFloat { spec.carLength }
    init(_ spec: Train, line: CGFloat, _ path: RoutePath) { self.spec = spec; self.line = line; self.path = path }
}

@MainActor
final class CreweStation: ObservableObject {
    let def: StationDef
    var name: String { def.name }

    // Platform / track geometry (design space; wide and pannable). West = small x, East = large x.
    let plats: [CrewePlat]
    let fastY: [CGFloat] = [262, 316]     // the two express lines between P5 and P6 — kept clear for fly-throughs
    let slowY: [CGFloat] = [200, 380]     // the throat slow lines the platforms gather onto, flanking the expresses
    let singleY: CGFloat = 606            // the single line, faced by P11 (above) and P12 (below)
    let throatY: CGFloat = 289            // where the running lines bunch together in the throats
    let xSL: CGFloat = 300, xSR: CGFloat = 1300      // platform west / east ends
    let xW: CGFloat = -760, xE: CGFloat = 2360       // spawn / exit — long throats so the staggers feed in gently
    // West throat: 4 tracks gather over a long, gentle staircase.
    let xWMouth: CGFloat = -120                      // where the 4 tracks bunch together
    // East throat: 7 tracks (5 + 2 fast) fan over a staircase.
    let xEMouth: CGFloat = 1740
    let throughIds = [1, 5, 6, 7, 8, 11]             // the through roads — trains run right across them (11 = the single line)
    let bayIds = [2, 3, 4]                            // east-facing terminating bays — trains reverse back out
    /// The roads trains route onto and that carry signals. Faces that share a road (9, 10, 12) aren't routed to
    /// directly — their people board the train standing on the shared line.
    var servedIds: Set<Int> { Set(throughIds + bayIds) }
    var homeSignalX: CGFloat { xSR + 470 }            // the east home signal — trains hold here when it's red

    @Published var trains: [CreweTrain] = []
    @Published var expresses: [CreweExpress] = []
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
    let expressSpeed: CGFloat = 220          // fly-throughs streak across far faster than the stoppers
    private var expressClock = 0.0, nextExpress = 3.0
    private var expressOnTop = true          // alternate the two fast lines — up and down fasts
    let dwellTime = 2.4
    let perCar = 3.0
    let boardOffRate = 6.5
    let platformCap = 16.0
    let overflowGrace = 9.0

    private var spawnClock = 0.0, nextSpawn = 1.0
    private var paxClock = 0.0, nextPax = 1.0
    private var overflowClock: [Double]
    private var peakFill = 0.0
    private var routeCursor = 0                        // rotates platform choice so arrivals fan out
    private var platEntryLen: [CGFloat] = []          // east-spawn → platform-east-end distance, per platform
    private var platTurnoutLen: [CGFloat] = []         // east-spawn → entry-turnout (point light) distance, per platform
    /// A bay reversing out runs the top slow line against the arriving flow. While it does, the top throat is
    /// signalled against — its point lights go red and no arrival is routed onto it — so the line is its own.
    @Published private(set) var reverseActive = false

    /// The through-platform indices (0-based) actually served this pass.
    private var throughIdx: [Int] { plats.indices.filter { throughIds.contains(plats[$0].id) } }
    private var bayIdx: [Int] { plats.indices.filter { bayIds.contains(plats[$0].id) } }
    var servedIdx: [Int] { plats.indices.filter { servedIds.contains(plats[$0].id) } }
    /// Platforms that share the top slow line (the bays and the through platforms above the expresses).
    private func isTopSlow(_ i: Int) -> Bool { plats[i].kind == .bayEast || slowLineFor(plats[i].lineY) == slowY[0] }
    /// Every platform face standing along the same running line — a berthed train boards them all.
    func facesOnLine(_ i: Int) -> [Int] { plats.indices.filter { plats[$0].lineY == plats[i].lineY } }
    /// The top slow line is clear to reverse onto once no other train is still arriving across it.
    private func topSlowClear(except t: CreweTrain) -> Bool {
        !trains.contains { $0 !== t && !$0.finished && $0.phase == .arriving && isTopSlow($0.target) }
    }

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
            CrewePlat(id: 11, y: 566, xL: L,    xR: R,    kind: .through, slabAbove: true,  ownsLine: false, lineOverride: 606),   // top face of the single line (606)
            CrewePlat(id: 12, y: 652, xL: L,    xR: R,    kind: .through, slabAbove: false, ownsLine: false, lineOverride: 606),  // bottom face of the single line
        ]
        passengers = Array(repeating: 0, count: 12)
        platformHeld = Array(repeating: false, count: 12)
        waitClock = Array(repeating: 0, count: 12)
        overflowClock = Array(repeating: 0, count: 12)
        platEntryLen = plats.indices.map { entryLenOf(routeInto($0), $0) }
        platTurnoutLen = plats.indices.map { turnoutLenOf(routeInto($0), $0) }
        spawn()
    }

    /// The path-distance to a platform's west end — a train has cleared the platform once its tail passes here.
    private func platWestDist(_ i: Int) -> CGFloat { platEntryLen[i] + (xSR - plats[i].xL) }

    // MARK: geometry — the staircase throats

    /// Which slow line a platform gathers onto — upper platforms onto the top slow line, lower onto the
    /// bottom one. The two express lines run clear between them, so no platform road ever touches them.
    func slowLineFor(_ y: CGFloat) -> CGFloat { y < throatY ? slowY[0] : slowY[1] }
    func throatOrder(_ y: CGFloat) -> Int { min(9, Int((abs(y - slowLineFor(y)) / 34).rounded())) }

    /// The east top group cascades onto the top slow line: 1 and 2 merge, then into 3, then 4 — each merge
    /// staggered further out than the last, so the points step in one at a time.
    private func topCascade(from y: CGFloat) -> [CGPoint] {
        let ys = [plats[0].y, plats[1].y, plats[2].y, plats[3].y, slowY[0]]
        let r = ys.firstIndex(where: { abs($0 - y) < 6 }) ?? 0
        var pts = [CGPoint(x: xSR, y: y)]
        for m in (r + 1)...4 {
            let xm = xSR + 150 + CGFloat(m - 1) * 190     // each successive merge is further east
            pts.append(CGPoint(x: xm - 95, y: ys[m - 1])) // run along the current line
            pts.append(CGPoint(x: xm, y: ys[m]))          // then merge onto the next
        }
        pts.append(CGPoint(x: xE, y: slowY[0]))
        return pts
    }

    /// Throat geometry at one end. A platform road holds its height to a staggered turnout, then steps onto
    /// its slow line and runs out to the mouth — the further a platform sits from its slow line, the earlier
    /// it peels away, so the points open one at a time. The express pair between them is left untouched.
    private func throatPoints(_ y: CGFloat, east: Bool) -> [CGPoint] {
        if east && y < plats[4].y - 20 { return topCascade(from: y) }   // 1→2→3→4→slow on the east
        let edge: CGFloat = east ? xSR : xSL
        let dir: CGFloat = east ? 1 : -1
        let far: CGFloat = east ? xE : xW
        let ord = CGFloat(min(6, throatOrder(y)))
        var pts: [CGPoint]
        if y < plats[4].y - 20 {                 // top group (P1 on the west): gather onto the top slow line
            let gy: CGFloat = 150
            pts = [CGPoint(x: edge, y: y), CGPoint(x: edge + dir * (80 + ord * 82), y: gy),
                   CGPoint(x: edge + dir * 660, y: gy), CGPoint(x: edge + dir * 830, y: slowY[0]), CGPoint(x: far, y: slowY[0])]
        } else if y > plats[5].y + 20 {          // bottom group: gather along one line, then onto the bottom slow line
            let gy: CGFloat = 486
            pts = [CGPoint(x: edge, y: y), CGPoint(x: edge + dir * (80 + ord * 82), y: gy),
                   CGPoint(x: edge + dir * 660, y: gy), CGPoint(x: edge + dir * 830, y: slowY[1]), CGPoint(x: far, y: slowY[1])]
        } else {                                  // P5 / P6: step straight onto their slow line
            let mergeX = edge + dir * (40 + ord * 120)
            pts = [CGPoint(x: edge, y: y), CGPoint(x: mergeX, y: slowLineFor(y)), CGPoint(x: far, y: slowLineFor(y))]
        }
        return east ? pts : pts.reversed()        // west runs far → platform
    }
    private func westThroatPoints(_ y: CGFloat) -> [CGPoint] { throatPoints(y, east: false) }
    private func eastThroatPoints(_ y: CGFloat) -> [CGPoint] { throatPoints(y, east: true) }

    /// Through-platform route — trains arrive **from the east**: in down the east throat, along the platform,
    /// out down the west throat.
    private func buildPath(to i: Int) -> RoutePath {
        let y = plats[i].lineY
        let pts = Array(eastThroatPoints(y).reversed()) + Array(westThroatPoints(y).reversed())
        return RoutePath(pts)
    }
    /// Bay route — in from the east down the throat to the bay's east end, then along the bay to a stand
    /// short of the buffer. There is no west exit: the train reverses back out along this same road.
    private func buildBayPath(to i: Int) -> RoutePath {
        let pl = plats[i]
        let pts = Array(eastThroatPoints(pl.lineY).reversed()) + [CGPoint(x: pl.xL + 180, y: pl.lineY)]
        return RoutePath(pts)
    }
    /// The road a train takes into platform `i` — a through route, or a terminating bay route.
    private func routeInto(_ i: Int) -> RoutePath {
        plats[i].kind == .bayEast ? buildBayPath(to: i) : buildPath(to: i)
    }
    /// The east spawn → platform-east-end distance for platform `i`.
    private func entryLenOf(_ p: RoutePath, _ i: Int) -> CGFloat {
        p.distanceTo(vertex: eastThroatPoints(plats[i].lineY).count - 1)
    }
    /// The east spawn → entry-turnout distance for platform `i` — where its point light sits. A train held
    /// by a red platform signal stops here rather than running on to the occupied platform.
    private func turnoutLenOf(_ p: RoutePath, _ i: Int) -> CGFloat {
        p.distanceTo(vertex: max(1, eastThroatPoints(plats[i].lineY).count - 2))
    }

    // MARK: routing

    /// A platform is taken until the train on it has run its whole length clear of the platform's west end.
    /// A bay stays taken for its whole occupant's visit — arrival, dwell and the reverse back out.
    private func platformTaken(_ i: Int, except t: CreweTrain? = nil) -> Bool {
        if plats[i].kind == .bayEast {
            return trains.contains { $0 !== t && !$0.finished && $0.target == i }
        }
        return trains.contains { o in
            guard o !== t, !o.finished, o.target == i else { return false }
            return (o.dist - o.spec.carLength) < platWestDist(i)
        }
    }
    /// Pick a road for an arriving train. A clear platform first (the fullest, so passengers keep moving);
    /// if every road is taken it heads for the one that will clear soonest, so the queue never backs a train
    /// onto a road that stays blocked while another frees.
    /// Would `t`'s nose at distance `d` come within a car's clearance of a train that's ahead of it?
    /// Ahead = further along its own road (ties broken by id), so two trains meeting at a merge always
    /// have one clear winner and never freeze each other. Bodies are compared as real positions, so the
    /// rule holds across different roads — exactly where the throat's merges and splits are.
    private func blockedAhead(_ t: CreweTrain, at d: CGFloat, roster: [CreweTrain]) -> Bool {
        let nose = t.path.sample(d).p
        let clear = Track.carUnit * 0.8
        for o in roster where o !== t && !o.finished {
            let oAhead = o.dist > t.dist || (o.dist == t.dist && o.id.hashValue > t.id.hashValue)
            guard oAhead else { continue }
            if bodyNear(o, nose, within: clear) { return true }
        }
        return false
    }

    /// True if any point along train `o`'s body (nose back to tail) lies within `r` of `p`.
    private func bodyNear(_ o: CreweTrain, _ p: CGPoint, within r: CGFloat) -> Bool {
        var d = o.dist
        let tail = o.dist - o.carLen
        while d >= tail {
            let q = o.path.sample(d).p
            if hypot(q.x - p.x, q.y - p.y) < r { return true }
            d -= 18
        }
        return false
    }

    /// Pick a road for an arriving train by rotating round-robin to the next clear platform, so arrivals
    /// fan evenly across the whole station. (Chasing the fullest platform instead feeds back on itself under
    /// load — the busiest road can't clear fast enough, so it stays busiest and swallows every train.)
    /// Passengers arrive evenly across the platforms, so even service keeps them all moving. If every road
    /// is taken, head for the one that will clear soonest.
    private func pickPlatform(except t: CreweTrain? = nil) -> Int {
        // While a bay is reversing, keep new arrivals off the top slow line it needs.
        let pool = reverseActive ? throughIdx.filter { !isTopSlow($0) } : throughIdx
        let n = pool.count
        guard n > 0 else { return throughIdx.first ?? 0 }
        for k in 1...n {
            let i = pool[(routeCursor + k) % n]
            if !platformTaken(i, except: t) { routeCursor = (routeCursor + k) % n; return i }
        }
        // Every road is taken — still step to the next one so queued trains spread across the station
        // rather than all stacking behind the same platform.
        routeCursor = (routeCursor + 1) % n
        return pool[routeCursor]
    }

    func reset() {
        trains = []; expresses = []; carried = 0; outcome = .playing; stars = 0; peakFill = 0
        passengers = Array(repeating: 0, count: 12)
        waitClock = Array(repeating: 0, count: 12)
        overflowClock = Array(repeating: 0, count: 12)
        entranceOpen = true; platformHeld = Array(repeating: false, count: 12); sparkles = []; animT = 0
        spawnClock = 0; nextSpawn = 1; paxClock = 0; nextPax = 1; routeCursor = 0
        expressClock = 0; nextExpress = 3; expressOnTop = true; reverseActive = false
        spawn()
        objectWillChange.send()
    }

    func toggleEntrance() { entranceOpen.toggle(); objectWillChange.send() }
    func toggleStarter(_ i: Int) { platformHeld[i].toggle(); objectWillChange.send() }

    /// The top throat is signalled against (point lights red) while a bay reverses out over its slow line.
    func topReserved(_ i: Int) -> Bool { reverseActive && isTopSlow(i) }

    /// A platform is occupied (its entry signal red) while a train is berthing, berthed, or backing out.
    func platformOccupied(_ i: Int) -> Bool {
        trains.contains { !$0.finished && $0.target == i &&
            ($0.phase == .berthed || $0.phase == .reversing || ($0.phase == .arriving && $0.dist >= $0.entryLen)) }
    }

    private func spawn() {
        // Occasionally send a terminating service into a bay — but only one bay at a time (they share the
        // cascade and a reverse holds the top throat), and never while a reverse is already under way.
        let anyBayBusy = trains.contains { !$0.finished && plats[$0.target].kind == .bayEast }
        let bays = (reverseActive || anyBayBusy) ? [] : bayIdx.filter { !platformTaken($0) }
        let target = (Double.random(in: 0..<1) < 0.30 ? bays.randomElement() : nil) ?? pickPlatform()
        let pl = plats[target]
        let isBay = pl.kind == .bayEast
        let len = def.trainLengths.randomElement() ?? 4
        let spec = Train(length: len, tint: trainPalette.randomElement() ?? .blue, name: "")
        let path = routeInto(target)
        let t = CreweTrain(spec, target: target, path)
        t.isBay = isBay
        t.entryLen = platEntryLen[target]
        t.turnoutDist = platTurnoutLen[target]
        // A through train pulls in along the platform; a bay runs right up to its buffer stand (path end).
        t.berthDist = isBay ? path.total : t.entryLen + (xSR - (pl.xL + 180))
        t.homeStop = homeStopDist(path)
        t.committed = true
        trains.append(t)
    }

    /// Send a fly-through express down one of the fast lines — the top line runs east→west, the bottom
    /// west→east, so they read as the up and down fasts. A power car sits at each end of a long rake.
    private func spawnExpress() {
        let onTop = expressOnTop; expressOnTop.toggle()
        let line = onTop ? fastY[0] : fastY[1]
        let pts = onTop ? [CGPoint(x: xE, y: line), CGPoint(x: xW, y: line)]
                        : [CGPoint(x: xW, y: line), CGPoint(x: xE, y: line)]
        let spec = Train(length: Int.random(in: 6...8), tint: Color(red: 0.84, green: 0.86, blue: 0.92), name: "")
        expresses.append(CreweExpress(spec, line: line, RoutePath(pts)))
    }

    /// The distance along an arriving path at which the nose first reaches the home signal, coming from the
    /// east. Trains hold here — at the signal the player actually sees — when the entrance is red.
    private func homeStopDist(_ p: RoutePath) -> CGFloat {
        var d: CGFloat = 0
        while d <= p.total {
            if p.sample(d).p.x <= homeSignalX { return d }
            d += 12
        }
        return 0
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
            if let p = plats.indices.randomElement(), passengers[p] < platformCap { passengers[p] += 1 }   // people wait on every platform
            nextPax = Double.random(in: def.spawnRange)
        }
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            if trains.count < 10 { spawn() }   // spawn() self-limits to a clear platform; this is just a backstop
            nextSpawn = Double.random(in: def.spawnRange.lowerBound...(def.spawnRange.upperBound * 1.3))
        }
        // Fly-through expresses on the fast lines — they share no track with the stoppers, so just run them
        // full length and clear them off the far end.
        expressClock += dt
        if expressClock >= nextExpress {
            expressClock = 0
            spawnExpress()
            nextExpress = Double.random(in: 4.0...9.0)
        }
        let expStep = expressSpeed * CGFloat(dt)
        for e in expresses where !e.finished {
            e.dist += expStep
            if e.dist >= e.path.total + e.carLen { e.finished = true }
        }
        if expresses.contains(where: { $0.finished }) { expresses.removeAll { $0.finished } }

        let roster = trains
        var spawnCount = 0
        for idx in roster.indices {
            let t = roster[idx]
            guard !t.finished else { continue }
            switch t.phase {
            case .arriving:
                var ceiling = t.berthDist
                // Held at the east home signal when it's red — every train that hasn't yet passed it, so a
                // train following another still stops at the light instead of chasing its leader through.
                if !entranceOpen && t.dist < t.homeStop {
                    ceiling = min(ceiling, t.homeStop - gap)
                }
                // Obey the platform's own signal: if its road is occupied, hold at the red point light out
                // at the entry turnout instead of running on past it onto the platform.
                if t.dist < t.turnoutDist && platformOccupied(t.target) {
                    ceiling = min(ceiling, t.turnoutDist - gap)
                }
                // Hold clear of any train physically ahead — wherever its body crosses our path, whatever
                // its target. "Ahead" is decided by progress so a merge always has a clear winner (never a
                // stand-off), and the check is on real positions so a train peeling off to its platform can't
                // be overrun by the one behind it.
                if blockedAhead(t, at: min(t.dist + step, ceiling), roster: roster) {
                    ceiling = min(ceiling, t.dist)
                }
                let next = min(t.dist + step, ceiling)
                t.stopped = next < t.dist + step - 0.01 && ceiling < t.berthDist ? t.stopped + dt : 0
                t.dist = max(t.dist, next)
                t.railAspect = railAspect(headroom: ceiling - t.dist, clearToEnd: ceiling >= t.berthDist - 1)
                if !t.spawnedNext && t.dist >= t.entryLen { t.spawnedNext = true; spawnCount += 1 }
                if t.dist >= t.berthDist {
                    t.dist = t.berthDist; t.phase = .berthed; t.stopped = 0
                    for f in facesOnLine(t.target) { waitClock[f] = 0 }; t.dwell = dwellTime
                    Sound.shared.play(.board)
                }
            case .berthed:
                if t.dwell > 0 { t.dwell -= dt }
                let cap = Double(t.spec.length) * perCar
                // Board from whichever face of this line has the most waiting — an island platform draws from
                // both its faces, so the passengers standing on the far face clear too.
                let faces = facesOnLine(t.target)
                if t.load < cap, let face = faces.max(by: { passengers[$0] < passengers[$1] }), passengers[face] > 0 {
                    let take = min(boardOffRate * dt, min(cap - t.load, passengers[face]))
                    let before = passengers[face]
                    passengers[face] = max(0, passengers[face] - take)
                    if Int(before) != Int(passengers[face]) {
                        let k = Int(passengers[face])
                        sparkles.append(Sparkle(x: plats[face].xL + 120 + CGFloat(k) * 15, y: plats[face].y + 24))
                    }
                    t.load += take; carried += take
                }
                t.railAspect = platformHeld[t.target] ? 2 : 0     // starter red holds it; green sends it away
                if t.dwell <= 0 && !platformHeld[t.target] {
                    if t.isBay {
                        // Claim the top throat, then reverse once the line ahead is clear — the point lights
                        // hold the arriving trains off while it backs out.
                        if !reverseActive { reverseActive = true; t.owningReverse = true }
                        if t.owningReverse && topSlowClear(except: t) { t.phase = .reversing; Sound.shared.play(.depart) }
                    } else {
                        t.phase = .departing; Sound.shared.play(.depart)
                    }
                }
            case .departing:
                var ceiling = t.path.total + t.spec.carLength
                for o in roster where o !== t && !o.finished && o.target == t.target && o.dist > t.dist {
                    ceiling = min(ceiling, o.dist - o.spec.carLength - gap)
                }
                t.dist = max(t.dist, min(t.dist + step, ceiling))
                t.railAspect = railAspect(headroom: ceiling - t.dist, clearToEnd: ceiling >= t.path.total - 1)
                if t.dist >= t.path.total + t.spec.carLength { t.finished = true }
            case .reversing:
                // Back out east, the way it came, down to the spawn. The reservation keeps the road its own,
                // so run it out briskly to give the throat back.
                t.dist = max(0, t.dist - step * 1.35)
                t.railAspect = 0
                if t.dist <= 0 {
                    t.finished = true
                    if t.owningReverse { reverseActive = false; t.owningReverse = false }
                }
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
