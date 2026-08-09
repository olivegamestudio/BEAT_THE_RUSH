import SwiftUI

// MARK: - Geometry helpers

extension CGPoint {
    func dist(_ o: CGPoint) -> CGFloat { hypot(o.x - x, o.y - y) }
    func lerp(_ o: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: x + (o.x - x) * t, y: y + (o.y - y) * t)
    }
}

struct RoutePath {
    let pts: [CGPoint]
    let cum: [CGFloat]
    var total: CGFloat { cum.last ?? 0 }

    init(_ pts: [CGPoint]) {
        self.pts = pts
        var c: [CGFloat] = [0]
        for i in 1..<max(pts.count, 1) { c.append(c[i - 1] + pts[i - 1].dist(pts[i])) }
        cum = c
    }

    func distanceTo(vertex i: Int) -> CGFloat { cum[min(i, cum.count - 1)] }

    func sample(_ d: CGFloat) -> (p: CGPoint, angle: CGFloat) {
        guard pts.count > 1 else { return (pts.first ?? .zero, 0) }
        let dd = min(max(d, 0), total)
        var i = 1
        while i < cum.count - 1 && cum[i] < dd { i += 1 }
        let seg = cum[i] - cum[i - 1]
        let t = seg > 0 ? (dd - cum[i - 1]) / seg : 0
        let p = pts[i - 1].lerp(pts[i], t)
        let a = atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x)
        return (p, a)
    }
}

// MARK: - Track diagram (landscape, trains run left → right through the platforms)

enum Track {
    static let W: CGFloat = 960
    static let H: CGFloat = 452
    static let carUnit: CGFloat = 50
    static let carHeight: CGFloat = 34

    /// Four running lines, one platform each, drawn as a signalling schematic.
    static let lineY: [CGFloat] = [64, 166, 268, 370]    // wide lanes: big gap between each platform
    static let platLeft: CGFloat = 385
    static let rightExit: CGFloat = 1030          // off the right edge, so trains slide away, not pop

    static let entry = CGPoint(x: -70, y: 370)    // off the left edge, so trains slide in
    static let ladderBottom = CGPoint(x: 195, y: 370)
    static let ladderTop = CGPoint(x: 345, y: 64)

    /// The point (switch) where the throat ladder meets running line `i`.
    static func junction(_ i: Int) -> CGPoint {
        let y = lineY[i]
        let t = (y - ladderBottom.y) / (ladderTop.y - ladderBottom.y)
        return CGPoint(x: ladderBottom.x + (ladderTop.x - ladderBottom.x) * t, y: y)
    }

    /// Order the ladder presents its points, nearest the entry first.
    static let ladderOrder = [3, 2, 1, 0]
}

// MARK: - Model

struct Train: Identifiable {
    let id = UUID()
    var length: Int
    var tint: Color
    var name: String
    var carLength: CGFloat { CGFloat(length) * Track.carUnit }
}

final class ActiveTrain: Identifiable {
    let id = UUID()
    var spec: Train
    var target: Int = -1        // platform the train is routed to
    var path: RoutePath
    var dist: CGFloat           // head distance along the path
    var berthDist: CGFloat = 0
    var committed = false       // past the throat — its route can no longer change
    var blocked = false         // held short of an occupied platform
    var spawnedNext = false
    var finished = false        // reached the exit; removed after the tick loop
    var toBoard = 0.0           // passengers still to board while berthed (capped by length)
    enum Phase { case arriving, berthed, departing }
    var phase: Phase = .arriving
    var dwell: Double = 0

    init(spec: Train, path: RoutePath, dist: CGFloat) {
        self.spec = spec; self.path = path; self.dist = dist
    }
}

@MainActor
final class Station: ObservableObject {
    @Published var name = "Exeter St Davids"
    @Published var trains: [ActiveTrain] = []
    @Published var dispatched = 0
    @Published var carried = 0.0        // total passengers carried away — the score
    /// Each point's state: `true` = thrown to divert into its platform, `false` = straight on.
    @Published var divert: [Bool] = [false, false, false, false]
    /// Passengers gathered on each platform, growing until a train collects them.
    @Published var passengers: [Double] = [2, 0, 1, 0]

    /// Visual platform lengths, in cars — flavour only; routing no longer gates on fit.
    let platCars = [7, 6, 7, 6]
    let speed: CGFloat = 78
    let dwellTime = 3.5
    let perCar = 3.0             // passengers a single carriage can carry away
    let boardOffRate = 6.0       // passengers boarding a berthed train, per second
    let spawnRange = 1.1...2.6   // seconds between single-passenger arrivals

    private var spawnClock = 0.0
    private var nextSpawn = 1.5

    private var queue: [Train] = []

    init() { queue = Station.freshQueue(); spawn() }

    static func freshQueue() -> [Train] {
        let d: [(String, Color, Int)] = [
            ("Penzance", .indigo, 6), ("Paignton", .green, 3),
            ("Bristol", .orange, 5), ("Plymouth", .blue, 4),
            ("Exmouth", .pink, 4), ("London", .red, 6),
        ]
        return d.map { Train(length: $0.2, tint: $0.1, name: $0.0) }
    }

    // MARK: Derived

    func occupied(_ i: Int, except t: ActiveTrain? = nil) -> Bool {
        trains.contains { $0 !== t && $0.target == i && $0.phase != .arriving && !$0.finished
            && !cleared($0, of: i) }
    }

    private func platformFarX(_ i: Int) -> CGFloat {
        Track.platLeft + CGFloat(platCars[i]) * Track.carUnit + Track.carUnit * 0.6
    }

    /// Has this train's tail moved past the far end of platform `i`? Only then is the
    /// platform truly empty and free for the next arrival to enter.
    private func cleared(_ t: ActiveTrain, of i: Int) -> Bool {
        let farDist = t.path.distanceTo(vertex: 2) + (platformFarX(i) - Track.junction(i).x)
        return (t.dist - t.spec.carLength) > farDist
    }

    /// The platform is free to enter only if no other train still occupies any part of it.
    func platformClear(_ i: Int, except t: ActiveTrain) -> Bool {
        !trains.contains { $0 !== t && $0.target == i && $0.phase != .arriving
            && !$0.finished && !cleared($0, of: i) }
    }


    /// Where the points would send a train arriving now — drives the switch blades
    /// and the platform highlight.
    var predicted: Int {
        for i in Track.ladderOrder where divert[i] { return i }
        return Track.ladderOrder.last ?? 0
    }

    /// Distance from the entry to platform `i`'s point, measured along the throat ladder —
    /// the same scale as a train's `dist`, since every route shares that ladder.
    private func junctionLadderDist(_ i: Int) -> CGFloat {
        Track.entry.dist(Track.ladderBottom) + Track.ladderBottom.dist(Track.junction(i))
    }

    /// Where the points send a train right now, considering only the junctions it has not
    /// yet passed — so a switch thrown ahead of the train is always honoured, and one
    /// thrown too late (for a junction already behind it) is not.
    private func liveTarget(_ t: ActiveTrain) -> Int {
        let margin = Track.carUnit * 0.3
        for i in Track.ladderOrder where t.dist <= junctionLadderDist(i) - margin {
            if divert[i] { return i }
        }
        return Track.ladderOrder.last ?? 0
    }

    // MARK: Actions — the points ARE the controls

    func toggle(_ i: Int) {
        divert[i].toggle()
        objectWillChange.send()
    }

    // MARK: Spawning

    private func spawn() {
        if queue.isEmpty { queue = Station.freshQueue() }
        let spec = queue.removeFirst()
        let t = ActiveTrain(spec: spec, path: buildPath(spec, to: predicted), dist: 0)
        t.target = predicted
        trains.append(t)
    }

    private func buildPath(_ spec: Train, to i: Int) -> RoutePath {
        let headX = Track.platLeft + spec.carLength
        return RoutePath([Track.entry, Track.ladderBottom, Track.junction(i),
                          CGPoint(x: headX, y: Track.lineY[i]),
                          CGPoint(x: Track.rightExit, y: Track.lineY[i])])
    }

    // MARK: Simulation — trains keep moving unless the road ahead is blocked

    func tick(_ dt: Double) {
        let step = speed * CGFloat(dt)
        let gap = Track.carUnit * 0.55

        // Passengers arrive one at a time, popping onto a random platform now and then.
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            let p = Int.random(in: 0..<4)
            if passengers[p] < 14 { passengers[p] += 1 }
            nextSpawn = Double.random(in: spawnRange)
        }

        // Iterate a stable snapshot; never add to or remove from `trains` inside the loop.
        let roster = trains
        var spawnCount = 0
        for idx in roster.indices {
            let t = roster[idx]
            switch t.phase {
            case .arriving:
                // Follow the points live: the train can still be re-routed to any platform
                // whose point it has not yet reached. The route only locks in once the train
                // arrives at its chosen junction.
                if !t.committed {
                    if t.dist >= junctionLadderDist(t.target) - Track.carUnit * 0.3 {
                        t.committed = true        // turning onto the platform — lock the route in
                    } else {
                        let tgt = liveTarget(t)   // still short of it — the points may re-route us
                        if tgt != t.target {
                            t.target = tgt
                            t.path = buildPath(t.spec, to: tgt)
                            t.berthDist = t.path.distanceTo(vertex: 3)
                        }
                    }
                }
                if t.berthDist == 0 { t.berthDist = t.path.distanceTo(vertex: 3) }

                let junctionDist = t.path.distanceTo(vertex: 2)
                var ceiling = t.berthDist

                // Hold *short* of the point until the platform is completely empty — far
                // enough back that the train stays re-routable: change the points to a free
                // platform and a waiting train will take it instead of waiting on the original.
                if !platformClear(t.target, except: t) {
                    ceiling = min(ceiling, junctionDist - Track.carUnit * 0.6)
                }

                // Don't run into the train ahead. On the shared throat that's any leader;
                // once past the throat only a leader bound for the same platform matters.
                if idx > 0 {
                    let a = roster[idx - 1]
                    let aTail = a.dist - a.spec.carLength
                    let aStillInThroat = aTail < a.path.distanceTo(vertex: 2)
                    if a.target == t.target || aStillInThroat {
                        ceiling = min(ceiling, aTail - gap)
                    }
                }

                let next = min(t.dist + step, ceiling)
                t.blocked = next < t.dist + step - 0.01 && ceiling < t.berthDist
                t.dist = max(t.dist, next)

                // Keep the flow going: once this train clears the throat, the next arrives.
                if !t.spawnedNext && t.dist >= junctionDist { t.spawnedNext = true; spawnCount += 1 }

                if t.dist >= t.berthDist {
                    t.dist = t.berthDist
                    t.phase = .berthed
                    t.dwell = dwellTime
                    // Capacity scales with length: a longer train carries more away.
                    t.toBoard = min(passengers[t.target], Double(t.spec.length) * perCar)
                }
            case .berthed:
                t.dwell -= dt
                // Board up to the train's capacity; anyone left over keeps waiting.
                if t.toBoard > 0 {
                    let take = min(boardOffRate * dt, t.toBoard)
                    passengers[t.target] = max(0, passengers[t.target] - take)
                    t.toBoard -= take
                    carried += take
                }
                if t.dwell <= 0 { t.phase = .departing }
            case .departing:
                t.dist += step
                if t.dist >= t.path.total { t.finished = true; dispatched += 1 }
            }
        }

        // Apply the deferred structural changes now that iteration is done.
        if roster.contains(where: { $0.finished }) { trains.removeAll { $0.finished } }
        for _ in 0..<spawnCount { spawn() }
        objectWillChange.send()
    }
}
