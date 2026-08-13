import SwiftUI

// MARK: - RailKit · piece 1 — the track graph
//
// RailKit is the shared level toolkit (see docs/DESIGN.md → "a shared level toolkit"). Instead of
// each bespoke station reimplementing its own geometry, this describes a level's lines as data: named
// polyline `RailEdge`s joined at named `RailNode`s. A level names the sequence of nodes a train runs
// through and the graph stitches it into the `RoutePath` the train follows — so layout becomes a small
// diagram of names, not a wall of hand-placed coordinates and a bespoke `drawRails`.

/// A named point in a level's track diagram — a junction, a platform end, a bridge portal — in the
/// station's design space.
struct RailNode {
    let id: String
    let p: CGPoint
    init(_ id: String, _ p: CGPoint) { self.id = id; self.p = p }
    init(_ id: String, x: CGFloat, y: CGFloat) { self.id = id; self.p = CGPoint(x: x, y: y) }
}

/// A named length of track joining two nodes. Straight when it's just the two ends; curved when
/// `via` waypoints shape it (a throat easing onto a bridge, say). Undirected — a route may traverse
/// it either way, and the ends are matched by node id, so one shared edge (e.g. a single-line bridge)
/// can serve trains running in both directions.
struct RailEdge {
    let id: String
    let a: String            // node id of one end
    let b: String            // node id of the other end
    let via: [CGPoint]       // intermediate shaping points, listed in a→b order (often empty)
    init(_ id: String, _ a: String, _ b: String, via: [CGPoint] = []) {
        self.id = id; self.a = a; self.b = b; self.via = via
    }
}

/// The track diagram: named nodes joined by named edges. Build one per level, then `route(_:)`
/// stitches a chosen sequence of node ids into a single `RoutePath`. The edges are also the natural
/// thing to draw the rails from (piece 4, `drawGraph`).
struct RailGraph {
    private(set) var nodes: [String: RailNode] = [:]
    private(set) var edges: [RailEdge] = []

    init(_ nodes: [RailNode] = [], _ edges: [RailEdge] = []) {
        for n in nodes { self.nodes[n.id] = n }
        self.edges = edges
    }

    mutating func add(_ n: RailNode) { nodes[n.id] = n }
    mutating func add(_ e: RailEdge) { edges.append(e) }

    /// The design-space point of a node (`.zero` for an unknown id — a route full of `.zero`s is the
    /// obvious symptom of a mistyped node name).
    func point(_ id: String) -> CGPoint { nodes[id]?.p ?? .zero }

    /// The edge joining two nodes in either orientation, if one is declared.
    func edge(_ x: String, _ y: String) -> RailEdge? {
        edges.first { ($0.a == x && $0.b == y) || ($0.a == y && $0.b == x) }
    }

    /// The points of one edge, ordered from node `from` to its far end — waypoints included (reversed
    /// when we traverse the edge b→a) and the far node's point appended. The `from` node's own point
    /// is *not* included, so consecutive edges concatenate without repeating the shared node.
    private func span(_ e: RailEdge, from: String) -> [CGPoint] {
        let forward = e.a == from
        let mids = forward ? e.via : Array(e.via.reversed())
        let end = forward ? e.b : e.a
        return mids + [point(end)]
    }

    /// Stitch a sequence of node ids into a `RoutePath`, following the declared edge between each
    /// consecutive pair (a straight join where none is declared). This is the `Router`: it turns
    /// "run in from the west, call at the top platform, over the bridge, out east" into arc-length.
    func route(_ ids: [String]) -> RoutePath {
        guard let first = ids.first else { return RoutePath([]) }
        var pts: [CGPoint] = [point(first)]
        guard ids.count > 1 else { return RoutePath(pts) }
        for i in 1..<ids.count {
            let from = ids[i - 1], to = ids[i]
            if let e = edge(from, to) {
                pts += span(e, from: from)
            } else {
                pts.append(point(to))            // no declared edge — join the two nodes straight
            }
        }
        return RoutePath(pts)
    }
}
