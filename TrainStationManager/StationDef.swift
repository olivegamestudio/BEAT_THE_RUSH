import SwiftUI

// MARK: - Layout — the diagram geometry, generated from the platform count

/// Everything spatial about a station derives from how many platforms it has, so a new
/// station is just a row of numbers. Lines are spread down a fixed band and centred; the
/// throat ladder and its points fall out of where those lines sit.
struct Layout {
    let n: Int
    let lineY: [CGFloat]
    let entry: CGPoint
    let ladderBottom: CGPoint
    let ladderTop: CGPoint
    /// Platforms in the order a train meets them climbing the ladder (nearest the entry first).
    let ladderOrder: [Int]

    init(platformCount n: Int) {
        self.n = n
        let bandTop: CGFloat = 64, bandBottom: CGFloat = 388
        let centre = (bandTop + bandBottom) / 2
        let spacing = min(102, (bandBottom - bandTop) / CGFloat(max(n - 1, 1)))
        let span = spacing * CGFloat(max(n - 1, 0))
        let start = centre - span / 2
        lineY = (0..<n).map { start + spacing * CGFloat($0) }
        let topY = lineY.first ?? bandTop
        let botY = lineY.last ?? bandBottom
        entry = CGPoint(x: -70, y: botY)          // off the left edge, on the bottom line
        ladderBottom = CGPoint(x: 195, y: botY)
        ladderTop = CGPoint(x: 345, y: topY)
        ladderOrder = Array((0..<n).reversed())   // bottom line (nearest entry) first, top line last
    }

    /// Where the throat ladder meets running line `i`.
    func junction(_ i: Int) -> CGPoint {
        let y = lineY[i]
        let denom = ladderTop.y - ladderBottom.y
        let t = denom != 0 ? (y - ladderBottom.y) / denom : 0
        return CGPoint(x: ladderBottom.x + (ladderTop.x - ladderBottom.x) * t, y: y)
    }
}

// MARK: - Station definition — one row of numbers per station

struct StationDef: Identifiable {
    let id: Int
    let name: String
    let platformCount: Int
    let platCars: [Int]                  // platform lengths, in cars (== platformCount long)
    let spawnRange: ClosedRange<Double>  // seconds between passenger arrivals
    let speed: CGFloat                   // train speed
    let dwellTime: Double
    let trainLengths: [Int]              // pool of arriving train lengths
    let goal: Int                        // passengers to carry to clear (used from Phase B)
    let expressChance: Double            // hook for the through-express mechanic (Phase B)

    var tier: Int {                      // 1…5, drives the difficulty colour
        switch platformCount { case 2: return 1; case 3: return 2; case 4: return 3
        case 5: return 4; default: return 5 }
    }
}

/// The colour palette arriving trains are painted from.
let trainPalette: [Color] = [.indigo, .green, .orange, .blue, .pink, .red, .teal, .purple, .mint]

private func caps(_ n: Int) -> [Int] { (0..<n).map { $0 % 2 == 0 ? 7 : 6 } }

private func def(_ id: Int, _ name: String, platforms n: Int,
                 spawn: ClosedRange<Double>, speed: CGFloat, trains: [Int],
                 goal: Int, express: Double = 0) -> StationDef {
    StationDef(id: id, name: name, platformCount: n, platCars: caps(n), spawnRange: spawn,
               speed: speed, dwellTime: 3.2, trainLengths: trains, goal: goal, expressChance: express)
}

/// The 20-station ladder, simplest → hardest.
let allStations: [StationDef] = [
    // Tier 1 · 2 platforms · gentle
    def(1,  "Saltash",               platforms: 2, spawn: 2.4...4.4, speed: 64, trains: [2, 3],       goal: 40),
    def(2,  "Dawlish",               platforms: 2, spawn: 2.2...4.2, speed: 70, trains: [2, 3],       goal: 45, express: 0.30),
    def(3,  "Windermere",            platforms: 2, spawn: 2.2...4.0, speed: 68, trains: [2, 3, 4],    goal: 50),
    def(4,  "Whitby",                platforms: 2, spawn: 2.0...3.8, speed: 70, trains: [2, 3, 4],    goal: 55),
    // Tier 2 · 3 platforms
    def(5,  "Scarborough",           platforms: 3, spawn: 1.9...3.6, speed: 74, trains: [2, 3, 4],    goal: 70),
    def(6,  "Hereford",              platforms: 3, spawn: 1.8...3.4, speed: 76, trains: [3, 4],       goal: 78),
    def(7,  "Lincoln",               platforms: 3, spawn: 1.7...3.2, speed: 78, trains: [3, 4, 5],    goal: 85),
    def(8,  "Carlisle",              platforms: 3, spawn: 1.6...3.0, speed: 80, trains: [3, 4, 5],    goal: 92),
    // Tier 3 · 4 platforms
    def(9,  "Exeter St Davids",      platforms: 4, spawn: 1.5...3.0, speed: 80, trains: [3, 4, 5],    goal: 100),
    def(10, "Norwich",              platforms: 4, spawn: 1.4...2.8, speed: 84, trains: [3, 4, 5],    goal: 110),
    def(11, "Nottingham",           platforms: 4, spawn: 1.3...2.6, speed: 86, trains: [3, 4, 5, 6], goal: 120),
    def(12, "Chester",              platforms: 4, spawn: 1.2...2.5, speed: 88, trains: [4, 5, 6],    goal: 130),
    // Tier 4 · 5 platforms · fast through-lines
    def(13, "Bristol Temple Meads", platforms: 5, spawn: 1.1...2.3, speed: 94, trains: [3, 4, 5, 6], goal: 150, express: 0.22),
    def(14, "Newcastle",            platforms: 5, spawn: 1.0...2.1, speed: 98, trains: [4, 5, 6],    goal: 165, express: 0.24),
    def(15, "Manchester Piccadilly",platforms: 5, spawn: 0.9...2.0, speed: 102, trains: [4, 5, 6],   goal: 180, express: 0.26),
    def(16, "Glasgow Central",      platforms: 5, spawn: 0.9...1.9, speed: 104, trains: [4, 5, 6],   goal: 195, express: 0.28),
    // Tier 5 · 6 platforms · brutal
    def(17, "Edinburgh Waverley",   platforms: 6, spawn: 0.8...1.7, speed: 108, trains: [4, 5, 6],   goal: 220, express: 0.32),
    def(18, "Leeds",                platforms: 6, spawn: 0.75...1.6, speed: 112, trains: [4, 5, 6, 7], goal: 240, express: 0.34),
    def(19, "Birmingham New Street",platforms: 6, spawn: 0.7...1.5, speed: 116, trains: [5, 6, 7],   goal: 265, express: 0.36),
    def(20, "London Paddington",    platforms: 6, spawn: 0.65...1.4, speed: 120, trains: [5, 6, 7],  goal: 300, express: 0.40),
]
