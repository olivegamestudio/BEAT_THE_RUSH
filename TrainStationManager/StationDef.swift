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
        // Big termini (7+ platforms) spread across a taller band so the lines don't crowd.
        let bandTop: CGFloat = n >= 7 ? 40 : 64
        let bandBottom: CGFloat = n >= 7 ? 410 : 388
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

enum StationKind { case ladder, saltash, dawlish }   // ladder = generic throat; others are bespoke

struct StationDef: Identifiable {
    let id: Int
    let name: String
    let county: String                   // shown under the name — real, for the fanatics
    let flag: String                     // home-nation flag emoji
    let platformCount: Int
    let platCars: [Int]                  // platform lengths, in cars (== platformCount long)
    let spawnRange: ClosedRange<Double>  // seconds between passenger arrivals
    let speed: CGFloat                   // train speed
    let dwellTime: Double
    let trainLengths: [Int]              // pool of arriving train lengths
    let goal: Int                        // passengers to carry to clear (used from Phase B)
    let expressChance: Double            // hook for the through-express mechanic (Phase B)
    var kind: StationKind = .ladder

    var tier: Int {                      // 1…5, drives the difficulty colour
        switch platformCount { case 2: return 1; case 3: return 2; case 4: return 3
        case 5: return 4; default: return 5 }
    }
}

/// The colour palette arriving trains are painted from.
let trainPalette: [Color] = [.indigo, .green, .orange, .blue, .pink, .red, .teal, .purple, .mint]

let flagEngland = "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
let flagScotland = "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"

private func caps(_ n: Int) -> [Int] { (0..<n).map { $0 % 2 == 0 ? 7 : 6 } }

private func def(_ id: Int, _ name: String, _ county: String, platforms n: Int,
                 spawn: ClosedRange<Double>, speed: CGFloat, trains: [Int],
                 goal: Int, express: Double = 0, flag: String = flagEngland,
                 kind: StationKind = .ladder) -> StationDef {
    StationDef(id: id, name: name, county: county, flag: flag, platformCount: n,
               platCars: caps(n), spawnRange: spawn, speed: speed, dwellTime: 3.2,
               trainLengths: trains, goal: goal, expressChance: express, kind: kind)
}

/// The 20-station ladder, simplest → hardest.
let allStations: [StationDef] = [
    // Tier 1 · 2 platforms · gentle
    def(1,  "Saltash",               "Cornwall",         platforms: 2, spawn: 2.8...4.8, speed: 64, trains: [2, 3],       goal: 24, kind: .saltash),
    def(2,  "Dawlish Warren",        "Devon",            platforms: 2, spawn: 2.6...4.6, speed: 66, trains: [2, 3],       goal: 30, kind: .dawlish),
    def(3,  "Windermere",            "Cumbria",          platforms: 2, spawn: 2.2...4.0, speed: 68, trains: [2, 3, 4],    goal: 50),
    def(4,  "Whitby",                "North Yorkshire",  platforms: 2, spawn: 2.0...3.8, speed: 70, trains: [2, 3, 4],    goal: 55),
    // Tier 2 · 3 platforms
    def(5,  "Scarborough",           "North Yorkshire",  platforms: 3, spawn: 1.9...3.6, speed: 74, trains: [2, 3, 4],    goal: 70),
    def(6,  "Hereford",              "Herefordshire",    platforms: 3, spawn: 1.8...3.4, speed: 76, trains: [3, 4],       goal: 78),
    def(7,  "Lincoln",               "Lincolnshire",     platforms: 3, spawn: 1.7...3.2, speed: 78, trains: [3, 4, 5],    goal: 85),
    def(8,  "Carlisle",              "Cumbria",          platforms: 3, spawn: 1.6...3.0, speed: 80, trains: [3, 4, 5],    goal: 92),
    // Tier 3 · 4 platforms
    def(9,  "Exeter St Davids",      "Devon",            platforms: 4, spawn: 1.5...3.0, speed: 80, trains: [3, 4, 5],    goal: 100),
    def(10, "Norwich",              "Norfolk",          platforms: 4, spawn: 1.4...2.8, speed: 84, trains: [3, 4, 5],    goal: 110),
    def(11, "Nottingham",           "Nottinghamshire",  platforms: 4, spawn: 1.3...2.6, speed: 86, trains: [3, 4, 5, 6], goal: 120),
    def(12, "Chester",              "Cheshire",         platforms: 4, spawn: 1.2...2.5, speed: 88, trains: [4, 5, 6],    goal: 130),
    // Tier 4 · 5 platforms · fast through-lines
    def(13, "Bristol Temple Meads", "Bristol",          platforms: 5, spawn: 1.1...2.3, speed: 94, trains: [3, 4, 5, 6], goal: 150, express: 0.22),
    def(14, "Newcastle",            "Tyne and Wear",    platforms: 5, spawn: 1.0...2.1, speed: 98, trains: [4, 5, 6],    goal: 165, express: 0.24),
    def(15, "Manchester Piccadilly","Greater Manchester", platforms: 5, spawn: 0.9...2.0, speed: 102, trains: [4, 5, 6], goal: 180, express: 0.26),
    def(16, "Glasgow Central",      "Glasgow",          platforms: 5, spawn: 0.9...1.9, speed: 104, trains: [4, 5, 6],   goal: 195, express: 0.28, flag: flagScotland),
    // Tier 5 · biggest termini · brutal
    def(17, "Edinburgh Waverley",   "Edinburgh",        platforms: 6, spawn: 0.8...1.7, speed: 108, trains: [4, 5, 6],   goal: 220, express: 0.32, flag: flagScotland),
    def(18, "Leeds",                "West Yorkshire",   platforms: 7, spawn: 0.75...1.6, speed: 112, trains: [4, 5, 6, 7], goal: 240, express: 0.34),
    def(19, "Birmingham New Street","West Midlands",    platforms: 7, spawn: 0.7...1.5, speed: 116, trains: [5, 6, 7],   goal: 265, express: 0.36),
    def(20, "London Paddington",    "Greater London",   platforms: 8, spawn: 0.65...1.4, speed: 120, trains: [5, 6, 7],  goal: 300, express: 0.40),
]
