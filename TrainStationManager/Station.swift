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

// MARK: - Constants shared by every station (geometry that never varies)

enum Track {
    static let W: CGFloat = 960
    static let H: CGFloat = 452
    static let carUnit: CGFloat = 50
    static let carHeight: CGFloat = 34
    static let platLeft: CGFloat = 385
    static let rightExit: CGFloat = 1030          // off the right edge, so trains slide away, not pop
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
    let def: StationDef
    let layout: Layout
    var name: String { def.name }
    var platCars: [Int] { def.platCars }
    var speed: CGFloat { def.speed }
    var dwellTime: Double { def.dwellTime }

    @Published var trains: [ActiveTrain] = []
    @Published var dispatched = 0
    @Published var carried = 0.0        // total passengers carried away — the score
    /// Each point's state: `true` = thrown to divert into its platform, `false` = straight on.
    @Published var divert: [Bool]
    /// Passengers gathered on each platform, growing until a train collects them.
    @Published var passengers: [Double]

    let perCar = 3.0             // passengers a single carriage can carry away
    let boardOffRate = 6.0       // passengers boarding a berthed train, per second
    let platformCap = 14.0       // most a platform holds before it's full

    private var spawnClock = 0.0
    private var nextSpawn = 1.5

    init(_ def: StationDef) {
        self.def = def
        self.layout = Layout(platformCount: def.platformCount)
        self.divert = Array(repeating: false, count: def.platformCount)
        self.passengers = Array(repeating: 0, count: def.platformCount)
        spawn()
    }

    private func makeTrain() -> Train {
        Train(length: def.trainLengths.randomElement() ?? 4,
              tint: trainPalette.randomElement() ?? .blue, name: "")
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
        let farDist = t.path.distanceTo(vertex: 2) + (platformFarX(i) - layout.junction(i).x)
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
        for i in layout.ladderOrder where divert[i] { return i }
        return layout.ladderOrder.last ?? 0
    }

    /// Distance from the entry to platform `i`'s point, measured along the throat ladder —
    /// the same scale as a train's `dist`, since every route shares that ladder.
    private func junctionLadderDist(_ i: Int) -> CGFloat {
        layout.entry.dist(layout.ladderBottom) + layout.ladderBottom.dist(layout.junction(i))
    }

    /// Where the points send a train right now, considering only the junctions it has not
    /// yet passed — so a switch thrown ahead of the train is always honoured, and one
    /// thrown too late (for a junction already behind it) is not.
    private func liveTarget(_ t: ActiveTrain) -> Int {
        let margin = Track.carUnit * 0.3
        for i in layout.ladderOrder where t.dist <= junctionLadderDist(i) - margin {
            if divert[i] { return i }
        }
        return layout.ladderOrder.last ?? 0
    }

    // MARK: Actions — the points ARE the controls

    func toggle(_ i: Int) {
        divert[i].toggle()
        objectWillChange.send()
    }

    // MARK: Spawning

    private func spawn() {
        let spec = makeTrain()
        let t = ActiveTrain(spec: spec, path: buildPath(spec, to: predicted), dist: 0)
        t.target = predicted
        trains.append(t)
    }

    private func buildPath(_ spec: Train, to i: Int) -> RoutePath {
        let headX = Track.platLeft + spec.carLength
        return RoutePath([layout.entry, layout.ladderBottom, layout.junction(i),
                          CGPoint(x: headX, y: layout.lineY[i]),
                          CGPoint(x: Track.rightExit, y: layout.lineY[i])])
    }

    // MARK: Simulation — trains keep moving unless the road ahead is blocked

    func tick(_ dt: Double) {
        let step = speed * CGFloat(dt)
        let gap = Track.carUnit * 0.55

        // Passengers arrive one at a time, popping onto a random platform now and then.
        spawnClock += dt
        if spawnClock >= nextSpawn {
            spawnClock = 0
            let p = Int.random(in: 0..<def.platformCount)
            if passengers[p] < platformCap { passengers[p] += 1 }
            nextSpawn = Double.random(in: def.spawnRange)
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

                // Hold short of the point until the platform is completely empty — far enough
                // back that the train stays re-routable.
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
