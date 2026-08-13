import SwiftUI

/// The split-flap (Solari) board system: a departure board that riffles each character through the
/// alphabet and settles, used for the menu title and the station-select screen. Drawn in `Canvas`,
/// driven by a `TimelineView(.animation)` while revealing, then frozen — so it costs nothing at rest.
///
/// Each cell's displayed glyph is a *pure function of elapsed time* (start blank, step through the
/// character set to the target at a fixed rate, staggered per column), so there's no mutable flip
/// state to manage — the board just reads the clock.
enum Flap {
    static let charset = Array(" ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.:-'&/")
    static let stepDur: Double = 0.05      // seconds per single flip
    static let cellStagger: Double = 0.04  // extra delay per column, so a word ripples in
    static let tileStagger: Double = 0.09  // extra delay per board on the select screen

    static func index(_ c: Character) -> Int {
        charset.firstIndex(of: Character(String(c).uppercased())) ?? 0
    }

    // Palette — a warm Solari off-white on dark charcoal leaves, tied to the game's night palette.
    static let ink = Color(red: 0.95, green: 0.92, blue: 0.84)
    static let inkDim = Color(red: 0.60, green: 0.64, blue: 0.71)
    static let topCol = Color(red: 0.125, green: 0.145, blue: 0.175)
    static let botCol = Color(red: 0.090, green: 0.105, blue: 0.130)
    static let seam = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let go = Color(red: 0.29, green: 0.82, blue: 0.48)
    static let amber = Color(red: 0.957, green: 0.718, blue: 0.251)

    /// (leaving glyph, arriving glyph, progress 0…1) for one cell revealing from blank to `target`.
    static func cell(target: Character, delay: Double, elapsed: Double) -> (Character, Character, Double) {
        let ti = index(target)
        let local = elapsed - delay
        if ti == 0 || local <= 0 { return (" ", " ", 0) }   // a blank target, or not started yet — stay blank
        let stepsF = local / stepDur
        let done = Int(floor(stepsF))
        if done >= ti { return (target, target, 0) }              // settled
        return (charset[done], charset[done + 1], min(max(stepsF - Double(done), 0), 1))
    }

    /// How long a line of `len` characters takes to fully settle (worst case), for freezing the anim.
    static func revealDuration(_ len: Int) -> Double {
        Double(len) * cellStagger + Double(charset.count) * stepDur + 0.4
    }
}

/// Draw one flap cell: two charcoal leaves with a seam, and — while flipping — the folding leaf that
/// squashes about the hinge (a 2-D fake of the physical fold), with the new glyph revealed behind.
func drawFlapCell(_ ctx: GraphicsContext, _ r: CGRect, _ a: Character, _ b: Character, _ p: Double, ink: Color) {
    let corner = r.width * 0.14
    let topRect = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2)
    let botRect = CGRect(x: r.minX, y: r.midY, width: r.width, height: r.height - r.height / 2)
    ctx.fill(Path(roundedRect: r, cornerRadius: corner), with: .color(Flap.topCol))
    ctx.fill(Path(botRect), with: .color(Flap.botCol))
    let font = Font.system(size: r.height * 0.60, weight: .heavy, design: .monospaced)
    func glyph(_ g: Character, _ clip: CGRect) {
        if g == " " { return }
        ctx.drawLayer { l in
            l.clip(to: Path(clip))
            l.draw(Text(String(g)).font(font).foregroundStyle(ink), at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
        }
    }
    if a == b && p == 0 {
        glyph(a, r)                                  // settled — one draw
    } else {
        glyph(b, topRect)                            // the new top, revealed behind the falling leaf
        glyph(a, botRect)                            // the old bottom, until the leaf lands
        if p < 0.5 {
            let s = CGFloat(1 - p / 0.5)             // top leaf folds down to edge-on
            ctx.drawLayer { l in
                l.clip(to: Path(topRect))
                l.translateBy(x: 0, y: r.midY); l.scaleBy(x: 1, y: s); l.translateBy(x: 0, y: -r.midY)
                l.fill(Path(topRect), with: .color(Flap.topCol))
                l.draw(Text(String(a)).font(font).foregroundStyle(ink), at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
            }
        } else {
            let s = CGFloat((p - 0.5) / 0.5)         // bottom leaf rises into place, with a small slap
            ctx.drawLayer { l in
                l.clip(to: Path(botRect))
                l.translateBy(x: 0, y: r.midY); l.scaleBy(x: 1, y: s); l.translateBy(x: 0, y: -r.midY)
                l.fill(Path(botRect), with: .color(Flap.botCol))
                l.draw(Text(String(b)).font(font).foregroundStyle(ink), at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
            }
        }
    }
    // A hairline seam — kept thin and semi-transparent so it reads as the gap between the leaves
    // without cutting through the letter (the two-tone leaves already imply the fold).
    var line = Path(); line.move(to: CGPoint(x: r.minX + 1, y: r.midY)); line.addLine(to: CGPoint(x: r.maxX - 1, y: r.midY))
    ctx.stroke(line, with: .color(Flap.seam.opacity(0.45)), lineWidth: max(0.5, r.height * 0.014))
}

/// Draw a fixed-width flap line of `text`, left-aligned at `origin`, riffling in over `elapsed`.
func drawFlapLine(_ ctx: GraphicsContext, _ text: String, width: Int, origin: CGPoint,
                  cell: CGSize, gap: CGFloat, elapsed: Double, baseDelay: Double, ink: Color) {
    let chars = Array(text.uppercased())
    for i in 0..<width {
        let target: Character = i < chars.count ? chars[i] : " "
        let (a, b, p) = Flap.cell(target: target, delay: baseDelay + Double(i) * Flap.cellStagger, elapsed: elapsed)
        let r = CGRect(x: origin.x + CGFloat(i) * (cell.width + gap), y: origin.y, width: cell.width, height: cell.height)
        drawFlapCell(ctx, r, a, b, p, ink: ink)
    }
}

/// The menu title as a row of flaps that reveals on appear.
struct FlapHeadline: View {
    let text: String
    var cellW: CGFloat = 24
    var gap: CGFloat = 3
    @State private var start = Date()
    @State private var animating = true
    // Every so often the board clears and flaps itself in again, so the menu keeps breathing.
    private let pulse = Timer.publish(every: 22, on: .main, in: .common).autoconnect()

    private func reveal() {
        start = Date(); animating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Flap.revealDuration(text.count)) { animating = false }
    }

    var body: some View {
        let cell = CGSize(width: cellW, height: cellW * 1.5)
        let w = CGFloat(text.count) * (cellW + gap)
        board(cell)
            .frame(width: w, height: cell.height)
            .onAppear { reveal() }
            .onReceive(pulse) { _ in reveal() }
    }

    @ViewBuilder private func board(_ cell: CGSize) -> some View {
        if animating {
            TimelineView(.animation) { tl in
                canvas(cell, elapsed: tl.date.timeIntervalSince(start))
            }
        } else {
            canvas(cell, elapsed: 9999)
        }
    }
    private func canvas(_ cell: CGSize, elapsed: Double) -> some View {
        Canvas { ctx, _ in
            drawFlapLine(ctx, text, width: text.count, origin: .zero, cell: cell, gap: gap,
                         elapsed: elapsed, baseDelay: 0, ink: Flap.ink)
        }
    }
}

extension StationDef {
    /// A concise board label — the town, dropping a long suffix so it fits the flaps.
    var boardName: String {
        let up = name.uppercased()
        return up.count <= 15 ? up : String(up.split(separator: " ").first ?? Substring(up))
    }
}

/// One station as a mini departure board. Unlocked stations flap in their name/region/status; a
/// locked station stays blank — "not in service" — until the level before it is cleared.
struct StationBoardTile: View {
    let def: StationDef
    let unlocked: Bool
    let stars: Int
    let index: Int
    let revealStart: Date
    let animating: Bool
    let onPick: () -> Void

    private var name: String { unlocked ? def.boardName : "" }
    private var region: String { unlocked ? def.county.uppercased() : "" }
    private var status: String { unlocked ? (stars > 0 ? "CLEARED" : "ON TIME") : "" }
    private var statusColor: Color { stars > 0 ? Flap.amber : Flap.go }
    private var baseDelay: Double { Double(index) * Flap.tileStagger }

    var body: some View {
        Button(action: { if unlocked { Sound.shared.play(.ui); onPick() } }) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(unlocked ? Flap.go : Color(white: 0.24))
                            .frame(width: 7, height: 7)
                            .shadow(color: unlocked ? Flap.go.opacity(0.8) : .clear, radius: 4)
                        Text("PLATFORM \(def.id)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(2).foregroundStyle(Flap.inkDim)
                    }
                    Spacer()
                    if unlocked {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { i in
                                Image(systemName: stars > i ? "star.fill" : "star")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(stars > i ? Flap.amber : Color(white: 0.3))
                            }
                        }
                    } else {
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.34))
                    }
                }
                boardCanvas
                    .frame(width: 300, height: 50)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.06, green: 0.075, blue: 0.10),
                                                Color(red: 0.045, green: 0.055, blue: 0.075)],
                                       startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13)
                .stroke(unlocked ? Color.white.opacity(0.10) : Color.white.opacity(0.05), lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .disabled(!unlocked)
    }

    @ViewBuilder private var boardCanvas: some View {
        if animating && unlocked {
            TimelineView(.animation) { tl in
                canvas(elapsed: tl.date.timeIntervalSince(revealStart))
            }
        } else {
            canvas(elapsed: unlocked ? 9999 : 0)
        }
    }
    private func canvas(elapsed: Double) -> some View {
        Canvas { ctx, _ in
            let nameCell = CGSize(width: 18, height: 28)
            drawFlapLine(ctx, name, width: 15, origin: .zero, cell: nameCell, gap: 2,
                         elapsed: elapsed, baseDelay: baseDelay, ink: Flap.ink)
            let subCell = CGSize(width: 10, height: 15)
            let subY: CGFloat = 28 + 7
            drawFlapLine(ctx, region, width: 15, origin: CGPoint(x: 0, y: subY), cell: subCell, gap: 2,
                         elapsed: elapsed, baseDelay: baseDelay + 0.25, ink: Flap.inkDim)
            drawFlapLine(ctx, status, width: 8, origin: CGPoint(x: 192, y: subY), cell: subCell, gap: 2,
                         elapsed: elapsed, baseDelay: baseDelay + 0.4, ink: statusColor)
        }
    }
}
