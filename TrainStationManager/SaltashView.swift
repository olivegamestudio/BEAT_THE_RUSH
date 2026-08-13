import SwiftUI

struct SaltashView: View {
    @StateObject private var station: SaltashStation
    let onExit: () -> Void
    init(def: StationDef, onExit: @escaping () -> Void) {
        _station = StateObject(wrappedValue: SaltashStation(def))
        self.onExit = onExit
    }
    private let tick = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    private let railSteel = Color(red: 0.44, green: 0.48, blue: 0.56)
    private let railSheen = Color(red: 0.82, green: 0.86, blue: 0.94)
    private let railEdge = Color(red: 0.10, green: 0.11, blue: 0.15)
    private let inkLight = Color(white: 0.82)

    // The run is wider than the screen, so we frame a zoomed window on the middle — bridge and
    // platforms — and let the player pan a little to see the east and west ends.
    private let contentMinX: CGFloat = -100
    private let contentMaxX: CGFloat = 1240
    private let designW: CGFloat = 980
    @State private var originX: CGFloat = 150     // design x shown at the screen's left edge
    @State private var dragStart: CGFloat? = nil
    @State private var confirmExit = false
    @State private var started = false
    @State private var paused = false

    /// The design x at the left edge right now (updated live as you drag).
    private func origin(_ sc: CGFloat) -> CGFloat { originX }
    private func clampOrigin(_ x: CGFloat) -> CGFloat { min(max(x, contentMinX), contentMaxX - designW) }

    /// Maps a design point into screen space: the panned window across the width, and the (shorter)
    /// content band centred vertically so it isn't stuck to the top.
    private func project(_ p: CGPoint, scale sc: CGFloat, size: CGSize) -> CGPoint {
        let vOff = (size.height - Track.H * sc) / 2
        return CGPoint(x: (p.x - origin(sc)) * sc, y: p.y * sc + vOff)
    }


    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / designW
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.15, blue: 0.21),
                                        Color(red: 0.06, green: 0.08, blue: 0.12)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                Canvas { ctx, size in
                    let sc = size.width / designW
                    func S(_ p: CGPoint) -> CGPoint { project(p, scale: sc, size: size) }
                    drawRelief(ctx, sc, size)
                    drawContours(ctx, sc, size)
                    drawWaterShimmer(ctx, sc, size, S)
                    drawReflections(ctx, sc, size, S)
                    drawRails(ctx, sc, S)
                    drawRouteLights(ctx, sc, S)                     // green/amber/red road ahead of each train
                    drawPlatforms(ctx, sc, S)                       // slabs sit behind the trains
                    for t in station.trains { drawTrain(ctx, t, sc, S) }
                    drawBridge(ctx, sc, S)                          // the bridge deck passes over the trains
                    drawPlatformPax(ctx, sc, S)                     // waiting people stand in front
                    for sp in station.sparkles {
                        drawSparkleBurst(ctx, at: S(CGPoint(x: sp.x, y: sp.y)), age: sp.age, life: sparkleLife, scale: sc, toward: CGPoint(x: size.width * 0.07, y: size.height * 0.90))
                    }
                    drawSignals(ctx, sc, S)
                }
                .ignoresSafeArea()
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            let base = dragStart ?? originX
                            if dragStart == nil { dragStart = base }
                            originX = clampOrigin(base - v.translation.width / scale)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                Vignette(strength: 0.5)
                controls(scale: scale, size: geo.size)

                if !started && station.outcome == .playing {
                    LevelBriefing(def: station.def, onStart: { started = true }, onClose: onExit)
                }

                if station.outcome != .playing {
                    OutcomeOverlay(won: station.outcome == .won, def: station.def,
                                   carried: Int(station.carried), goal: station.def.goal,
                                   stars: station.stars,
                                   onRetry: { station.reset() }, onExit: onExit)
                }

                if confirmExit {
                    ConfirmDialog(title: "Leave Saltash?", message: "You'll lose this go.",
                                  confirmTitle: "Leave", onConfirm: onExit,
                                  onCancel: { confirmExit = false })
                }
            }
        }
        .ignoresSafeArea()      // measure the full screen so the tap targets match the drawn board
        .onReceive(tick) { _ in if started && !paused { station.tick(0.03) } }
        .overlay { if paused { PausedOverlay { paused = false } } }
        .statusBarHidden()
    }

    // MARK: rails

    private func rail(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        var p = Path(); p.move(to: S(a)); p.addLine(to: S(b))
        ctx.stroke(p, with: .color(railEdge), style: .init(lineWidth: 18 * sc, lineCap: .round))
        ctx.stroke(p, with: .color(railSteel), style: .init(lineWidth: 12 * sc, lineCap: .round))
        ctx.stroke(p, with: .color(railSheen.opacity(0.5)), style: .init(lineWidth: 3 * sc, lineCap: .round))
    }

    /// The coloured relief map — the valley the station sits in, drawn behind everything.
    private func drawRelief(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize) {
        let vOff = (size.height - Track.H * sc) / 2
        let r = SaltashStation.reliefRect
        let screen = CGRect(x: (r.minX - origin(sc)) * sc, y: r.minY * sc + vOff,
                            width: r.width * sc, height: r.height * sc)
        ctx.draw(Image(decorative: SaltashStation.relief, scale: 1), in: screen)
    }

    /// Topographic contour lines over the relief. Built once in design space, then scaled to frame.
    private func drawContours(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize) {
        let vOff = (size.height - Track.H * sc) / 2
        let t = CGAffineTransform(a: sc, b: 0, c: 0, d: sc, tx: -origin(sc) * sc, ty: vOff)
        ctx.stroke(SaltashStation.contour.applying(t),
                   with: .color(.white.opacity(0.06)), style: .init(lineWidth: 1.3 * sc, lineCap: .round))
    }

    private func drawRails(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        // west side — the two platform lines and the throat converging to the bridge
        rail(ctx, CGPoint(x: s.exitW, y: s.yBot), CGPoint(x: s.xMerge, y: s.yBot), sc, S)   // eastbound line
        rail(ctx, CGPoint(x: s.exitW, y: s.yTop), CGPoint(x: s.xMerge, y: s.yTop), sc, S)    // westbound line
        rail(ctx, CGPoint(x: s.xMerge, y: s.yBot), CGPoint(x: s.xBridgeW, y: s.yBridge), sc, S)
        rail(ctx, CGPoint(x: s.xMerge, y: s.yTop), CGPoint(x: s.xBridgeW, y: s.yBridge), sc, S)
        // the bridge — a single line
        rail(ctx, CGPoint(x: s.xBridgeW, y: s.yBridge), CGPoint(x: s.xBridgeE, y: s.yBridge), sc, S)
        // east side — the bridge splits back to two lines through the east throat
        rail(ctx, CGPoint(x: s.xBridgeE, y: s.yBridge), CGPoint(x: s.xMergeE, y: s.yBot), sc, S)
        rail(ctx, CGPoint(x: s.xBridgeE, y: s.yBridge), CGPoint(x: s.xMergeE, y: s.yTop), sc, S)
        rail(ctx, CGPoint(x: s.xMergeE, y: s.yTop), CGPoint(x: s.exitE, y: s.yTop), sc, S)    // eastbound out (top)
        rail(ctx, CGPoint(x: s.xMergeE, y: s.yBot), CGPoint(x: s.entryE, y: s.yBot), sc, S)   // westbound in (bottom)
    }

    // MARK: the River Tamar — reflections and a soft drifting shimmer, clipped to the water band

    /// A gentle sheen on the Tamar: a few soft, blurred highlights that drift slowly down the water —
    /// replaces the old hard ripple lines with something that reads as moving water.
    private func drawWaterShimmer(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let x0 = S(CGPoint(x: s.riverL, y: 0)).x, x1 = S(CGPoint(x: s.riverR, y: 0)).x
        let band = CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)
        ctx.drawLayer { g in
            g.clip(to: Path(band))
            g.addFilter(.blur(radius: 8 * sc))
            let t = CGFloat(station.animT), span = size.height + 140
            for k in 0..<5 {
                var yy = (t * (7 + CGFloat(k) * 2.5) + CGFloat(k) * 130).truncatingRemainder(dividingBy: span)
                yy -= 70
                let h = (16 + CGFloat(k % 3) * 9) * sc
                g.fill(Path(ellipseIn: CGRect(x: x0 - 12, y: yy, width: (x1 - x0) + 24, height: h)),
                       with: .color(.white.opacity(0.05)))
            }
        }
    }

    /// The bridge and any trains over the water, mirrored down into the Tamar — flipped about the deck
    /// line, blurred and faded, and clipped to the water band so it only shows on the river.
    private func drawReflections(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let x0 = S(CGPoint(x: s.riverL, y: 0)).x, x1 = S(CGPoint(x: s.riverR, y: 0)).x
        let deckY = S(CGPoint(x: 0, y: s.yBridge)).y
        ctx.drawLayer { g in
            g.clip(to: Path(CGRect(x: x0, y: deckY, width: x1 - x0, height: size.height - deckY)))
            g.opacity = 0.13
            g.addFilter(.blur(radius: 3.2 * sc))
            g.translateBy(x: 0, y: deckY); g.scaleBy(x: 1, y: -1); g.translateBy(x: 0, y: -deckY)  // flip about the deck
            drawBridge(g, sc, S)
            for t in station.trains { drawTrain(g, t, sc, S) }
        }
    }

    // MARK: the River Tamar — a vertical band the bridge crosses


    // MARK: the Royal Albert Bridge — twin bowstring arches over the single line

    private func drawBridge(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let y = s.yBridge
        let arches = 3
        let span = s.xBridgeE - s.xBridgeW
        let bounds = (0...arches).map { s.xBridgeW + span * CGFloat($0) / CGFloat(arches) }
        let dark = Color(red: 0.34, green: 0.13, blue: 0.13)
        let red = Color(red: 0.68, green: 0.26, blue: 0.24)
        let redHi = Color(red: 0.88, green: 0.44, blue: 0.40)
        // piers down toward the water, one at each arch join
        for px in bounds {
            var pier = Path(); pier.move(to: S(CGPoint(x: px, y: y + 4))); pier.addLine(to: S(CGPoint(x: px, y: y + 40)))
            ctx.stroke(pier, with: .color(Color(white: 0.32)), style: .init(lineWidth: 6 * sc, lineCap: .round))
        }
        for i in 0..<arches {
            let x0 = bounds[i], x1 = bounds[i + 1]
            let c = (x0 + x1) / 2
            func archY(_ f: CGFloat) -> CGFloat { y - 4 - 152 * (1 - f) * f }   // peak ≈ y-42
            // vertical hangers from the arch to the deck
            for f in stride(from: 0.2, through: 0.8, by: 0.2) {
                let hx = x0 + (x1 - x0) * f
                var h = Path(); h.move(to: S(CGPoint(x: hx, y: archY(f)))); h.addLine(to: S(CGPoint(x: hx, y: y - 4)))
                ctx.stroke(h, with: .color(red.opacity(0.85)), style: .init(lineWidth: 2.4 * sc, lineCap: .round))
            }
            // the top-chord tube (dark base + red + highlight, like a rail)
            var arch = Path(); arch.move(to: S(CGPoint(x: x0, y: y - 4)))
            arch.addQuadCurve(to: S(CGPoint(x: x1, y: y - 4)), control: S(CGPoint(x: c, y: y - 80)))
            ctx.stroke(arch, with: .color(dark), style: .init(lineWidth: 9 * sc, lineCap: .round))
            ctx.stroke(arch, with: .color(red), style: .init(lineWidth: 6 * sc, lineCap: .round))
            ctx.stroke(arch, with: .color(redHi.opacity(0.7)), style: .init(lineWidth: 2 * sc, lineCap: .round))
        }
    }

    // MARK: platforms + passengers

    /// The platform slab rectangle. The slab is held clear of the carriage that berths on the
    /// line — the carriage's isometric side face hangs below its roof, so the bottom platform
    /// (which meets that face) needs more room than the top one (which only meets the roof).
    private func platformRect(top: Bool, y: CGFloat, sc: CGFloat, S: (CGPoint) -> CGPoint) -> CGRect {
        let s = station
        let h: CGFloat = 24
        let clear: CGFloat = top ? 22 : 38
        let slabY = top ? y - clear - h : y + clear
        return CGRect(x: S(CGPoint(x: s.platL, y: 0)).x, y: S(CGPoint(x: 0, y: slabY)).y,
                      width: (s.platR - s.platL) * sc, height: h * sc)
    }

    private func drawPlatforms(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        drawPlatform(ctx, top: true, y: s.yTop, sc: sc, S: S)
        drawPlatform(ctx, top: false, y: s.yBot, sc: sc, S: S)
    }

    private func drawPlatform(_ ctx: GraphicsContext, top: Bool, y: CGFloat,
                              sc: CGFloat, S: (CGPoint) -> CGPoint) {
        let depth: CGFloat = 11
        let rect = platformRect(top: top, y: y, sc: sc, S: S)
        let rr = Path(roundedRect: rect, cornerRadius: 14 * sc)
        let side = Path(roundedRect: rect.offsetBy(dx: 0, dy: depth * sc), cornerRadius: 14 * sc)
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: .black.opacity(0.5), radius: 5 * sc, x: 0, y: 6 * sc))
            l.fill(side, with: .color(Color(red: 0.18, green: 0.21, blue: 0.28)))
        }
        ctx.fill(rr, with: .color(Color(red: 0.34, green: 0.39, blue: 0.47)))
        ctx.stroke(rr, with: .color(.white.opacity(0.22)), style: .init(lineWidth: 2 * sc))
    }

    /// Waiting passengers, drawn after the trains so a berthed carriage never hides the queue.
    private func drawPlatformPax(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let topRect = platformRect(top: true, y: s.yTop, sc: sc, S: S)
        drawPax(ctx, count: s.pTop, x0: topRect.minX + 16 * sc, feetY: topRect.maxY - 4 * sc,
                sc: sc, agitated: s.topAgitated, t: s.animT)
        let botRect = platformRect(top: false, y: s.yBot, sc: sc, S: S)
        drawPax(ctx, count: s.pBot, x0: botRect.minX + 16 * sc, feetY: botRect.minY + 4 * sc,
                sc: sc, agitated: s.botAgitated, t: s.animT)
        if s.topMood.shows {
            drawMood(ctx, s.topMood.emoji, at: CGPoint(x: topRect.minX + 42 * sc, y: topRect.maxY - 40 * sc), scale: sc)
        }
        if s.botMood.shows {
            drawMood(ctx, s.botMood.emoji, at: CGPoint(x: botRect.minX + 42 * sc, y: botRect.minY - 30 * sc), scale: sc)
        }
    }

    private func drawPax(_ ctx: GraphicsContext, count: Double, x0: CGFloat, feetY: CGFloat,
                         sc: CGFloat, agitated: Bool, t: Double) {
        let clothes: [Color] = [Color(red: 0.30, green: 0.55, blue: 0.85), Color(red: 0.86, green: 0.45, blue: 0.38),
                                Color(red: 0.40, green: 0.70, blue: 0.52), Color(red: 0.78, green: 0.62, blue: 0.30),
                                Color(red: 0.62, green: 0.46, blue: 0.78)]
        let skin = Color(red: 0.97, green: 0.83, blue: 0.70)
        let n = min(Int(count), 12)
        for k in 0..<max(n, 0) {
            // agitated people shuffle on the spot, each at their own phase
            let pace = agitated ? CGFloat(sin(t * 2.0 + Double(k) * 1.7)) * 8 * sc : 0
            let px = x0 + CGFloat(k) * 15 * sc + pace
            let coat = agitated ? Color(red: 0.90, green: 0.36, blue: 0.32) : clothes[k % clothes.count]
            let bw = 11 * sc, bh = 14 * sc, top = feetY - bh
            var torso = Path()
            torso.move(to: CGPoint(x: px - bw * 0.32, y: top + bw * 0.28))
            torso.addQuadCurve(to: CGPoint(x: px + bw * 0.32, y: top + bw * 0.28), control: CGPoint(x: px, y: top - bw * 0.05))
            torso.addLine(to: CGPoint(x: px + bw * 0.42, y: feetY)); torso.addLine(to: CGPoint(x: px - bw * 0.42, y: feetY))
            torso.closeSubpath()
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.5), radius: 2 * sc, x: 0, y: 2 * sc))
                l.fill(torso, with: .color(coat))
            }
            let hd = 8 * sc
            ctx.fill(Path(ellipseIn: CGRect(x: px - hd / 2, y: top - hd * 0.72, width: hd, height: hd)), with: .color(skin))
        }
    }

    // MARK: signals — the bridge portals

    private func drawSignals(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        // Each direction stacks behind its own signal, on its own line at the throat: eastbound
        // on the top line at the west throat, westbound on the bottom line at the east throat.
        // The light shows what the player set — green for the cleared direction — so a crossing
        // train is never under its own red. (Bridge-occupied is an internal check, not shown.)
        let sig = sc * 2.5
        drawSignal(ctx, at: S(CGPoint(x: s.xMerge + 6, y: s.yTop)), red: s.bridgeGreen != .east, scale: sig)
        drawSignal(ctx, at: S(CGPoint(x: s.xMergeE - 6, y: s.yBot)), red: s.bridgeGreen != .west, scale: sig)
        // Automatic platform signals — red while a train stands on the platform, so the next one
        // waits at the platform end rather than queuing onto it. (Eastbound enters the top platform
        // from the west, westbound enters the bottom platform from the east.)
        drawSignal(ctx, at: S(CGPoint(x: s.platL - 10, y: s.yTop)), red: s.topBusy, scale: sc * 1.7)
        drawSignal(ctx, at: S(CGPoint(x: s.platR + 10, y: s.yBot)), red: s.botBusy, scale: sc * 1.7)
        // Automatic three-aspect block signals along each approach — green/amber/red as the queue builds.
        for bx in s.blockXsEast {
            drawBlockSignal(ctx, at: S(CGPoint(x: bx, y: s.yTop - 26)), aspect: s.blockAspect(bx, .east), scale: sc * 1.7)
        }
        for bx in s.blockXsWest {
            drawBlockSignal(ctx, at: S(CGPoint(x: bx, y: s.yBot + 26)), aspect: s.blockAspect(bx, .west), scale: sc * 1.7)
        }
    }

    private func drawRouteLights(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for t in station.trains where !t.finished {
            let start = max(0, t.dist)
            let end = min(t.path.total, t.dist + Track.carUnit * 6)
            if end <= start + 1 { continue }
            var pts: [CGPoint] = []
            var d = start
            while d <= end { pts.append(S(t.path.sample(d).p)); d += 9 }
            drawRouteAhead(ctx, pts, aspect: t.railAspect, scale: sc)
        }
    }

    private func drawTrain(_ ctx: GraphicsContext, _ t: SaltTrain, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for c in 0..<t.spec.length {
            let d = t.dist - (CGFloat(c) + 0.5) * Track.carUnit
            guard d >= 0 else { continue }        // don't draw carriages that haven't entered yet
            let s = t.path.sample(d)
            drawCarriage(ctx, at: S(s.p), angle: t.path.smoothAngle(d), tint: t.spec.tint,
                         cw: Track.carUnit - 6, ch: Track.carHeight, scale: sc, fill: min(1, t.load / (Double(t.spec.length) * 3)), seed: t.id.hashValue &+ c)
        }
        // A train sat at a red for a while shows a waiting bubble that floats up and fades, over and over.
        if t.stopped > 3.5, t.dist >= 0, t.dist <= t.path.total {
            let prog = CGFloat((t.stopped - 3.5).truncatingRemainder(dividingBy: 2.4) / 2.4)
            var g = ctx; g.opacity = Double(1 - prog)
            let head = t.path.sample(t.dist).p
            drawMood(g, "😴", at: S(CGPoint(x: head.x, y: head.y - 28 - prog * 26)), scale: sc)
        }
    }

    // MARK: controls / HUD

    /// A tap target over a drawn signal — the light itself shows red/green; a faint ring hints
    /// that it's the control. `foot` is the signal's foot on the track in design space.
    private func signalButton(_ dir: SaltashStation.Dir, foot: CGPoint,
                              scale: CGFloat, size: CGSize) -> some View {
        Button(action: { station.clear(dir); Sound.shared.play(.tap) }) { SignalHalo() }
            .buttonStyle(PressStyle())
            .position(project(CGPoint(x: foot.x, y: foot.y - 42), scale: scale, size: size))
    }

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
            // The signals are the control: tap the eastbound one (west throat, top line) or the
            // westbound one (east throat, bottom line) to clear that direction onto the bridge.
            signalButton(.east, foot: CGPoint(x: station.xMerge + 6, y: station.yTop),
                         scale: scale, size: size)
            signalButton(.west, foot: CGPoint(x: station.xMergeE - 6, y: station.yBot),
                         scale: scale, size: size)

            // back — top left
            Button(action: { Sound.shared.play(.ui); confirmExit = true }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Color(white: 0.85))
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.82, green: 0.24, blue: 0.24).opacity(0.94), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14)))
            }
            .buttonStyle(PressStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(28)

            // mute — top right
            HStack(spacing: 10) { PauseButton(paused: $paused); HapticsButton(); MuteButton() }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(28)

            // score bottom-left — a rolling ticker with a little crowd above it
            ScoreTicker(count: Int(station.carried), goal: station.def.goal)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 34).padding(.bottom, 26)

            // name + county bottom-right
            VStack(alignment: .trailing, spacing: 2) {
                Text(station.name)
                    .font(.system(size: 27, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(station.def.county) \(station.def.flag)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.72))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 34).padding(.bottom, 26)
        }
    }
}

#Preview { SaltashView(def: allStations[0]) { } }
