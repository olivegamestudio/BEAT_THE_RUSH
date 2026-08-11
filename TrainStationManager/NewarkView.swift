import SwiftUI

struct NewarkView: View {
    @StateObject private var station: NewarkStation
    let onExit: () -> Void
    init(def: StationDef, onExit: @escaping () -> Void) {
        _station = StateObject(wrappedValue: NewarkStation(def))
        self.onExit = onExit
    }
    private let tick = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    @State private var confirmExit = false
    @State private var started = false

    private let worldW: CGFloat = 1400
    private let contentMinX: CGFloat = -360
    private let contentMaxX: CGFloat = 1760
    @State private var originX: CGFloat = 0
    @State private var dragStartX: CGFloat? = nil

    private let ecmlTint = Color(red: 0.34, green: 0.62, blue: 0.92)
    private let castleTint = Color(red: 0.90, green: 0.50, blue: 0.26)
    private let railSteel = Color(red: 0.44, green: 0.48, blue: 0.56)
    private let railSheen = Color(red: 0.82, green: 0.86, blue: 0.94)
    private let railEdge = Color(red: 0.10, green: 0.11, blue: 0.15)

    private func project(_ p: CGPoint, _ sc: CGFloat, _ size: CGSize) -> CGPoint {
        let vOff = (size.height - Track.H * sc) / 2
        return CGPoint(x: (p.x - originX) * sc, y: p.y * sc + vOff)
    }
    private func clampOrigin(_ x: CGFloat) -> CGFloat { min(max(x, contentMinX), contentMaxX - worldW) }

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / worldW
            ZStack {
                Canvas { ctx, size in
                    let sc = size.width / worldW
                    func S(_ p: CGPoint) -> CGPoint { project(p, sc, size) }
                    drawScene(ctx, sc, size)
                    drawRails(ctx, sc, S)
                    drawDiamond(ctx, sc, S)
                    drawPlatform(ctx, y: station.yEcml + 30, tint: ecmlTint, sc: sc, above: false, S: S)
                    drawPlatform(ctx, y: station.yCastle - 40, tint: castleTint, sc: sc, above: true, S: S)
                    let ordered = station.trains.sorted { $0.path.sample($0.dist).p.y < $1.path.sample($1.dist).p.y }
                    for t in ordered { drawTrain(ctx, t, sc, S) }
                    drawPeople(ctx, sc, S)
                    for sp in station.sparkles {
                        drawSparkleBurst(ctx, at: S(CGPoint(x: sp.x, y: sp.y)), age: sp.age, life: sparkleLife, scale: sc)
                    }
                    drawSignals(ctx, sc, S)
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { v in
                            let start = dragStartX ?? originX
                            dragStartX = start
                            originX = clampOrigin(start - v.translation.width / scale)
                        }
                        .onEnded { _ in dragStartX = nil }
                )
                Vignette(strength: 0.4)
                controls(scale: scale, size: geo.size)

                if !started && station.outcome == .playing {
                    LevelBriefing(def: station.def, onStart: { started = true }, onClose: onExit)
                }
                if station.outcome != .playing {
                    OutcomeOverlay(won: station.outcome == .won, def: station.def,
                                   carried: Int(station.carried), goal: station.def.goal, stars: station.stars,
                                   onRetry: { station.reset() }, onExit: onExit)
                }
                if confirmExit {
                    ConfirmDialog(title: "Leave \(station.name)?", message: "You'll lose this go.",
                                  confirmTitle: "Leave", onConfirm: onExit, onCancel: { confirmExit = false })
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(tick) { _ in if started { station.tick(0.03) } }
        .statusBarHidden()
    }

    // MARK: scene — Newark-on-Trent: the castle ruin on the skyline, the Trent beyond

    private func drawScene(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize) {
        let w = size.width
        let vOff = (size.height - Track.H * sc) / 2
        func y(_ d: CGFloat) -> CGFloat { d * sc + vOff }
        func band(_ y0: CGFloat, _ y1: CGFloat, _ top: Color, _ bot: Color) {
            ctx.fill(Path(CGRect(x: 0, y: y0, width: w, height: y1 - y0)),
                     with: .linearGradient(Gradient(colors: [top, bot]),
                                           startPoint: CGPoint(x: w / 2, y: y0), endPoint: CGPoint(x: w / 2, y: y1)))
        }
        band(0, y(70), Color(red: 0.52, green: 0.62, blue: 0.78), Color(red: 0.80, green: 0.82, blue: 0.84))
        clouds(ctx, sc, w: w, topY: y(6), botY: y(58))
        castle(ctx, baseY: y(70), sc: sc, w: w)
        band(y(64), y(84), Color(red: 0.32, green: 0.42, blue: 0.31), Color(red: 0.27, green: 0.35, blue: 0.26))
        // The green — a soft top-to-bottom gradient so it isn't flat, plus a faint sheen near the tracks.
        band(y(84), size.height, Color(red: 0.31, green: 0.37, blue: 0.26), Color(red: 0.15, green: 0.19, blue: 0.13))
        ctx.fill(Path(CGRect(x: 0, y: y(84), width: w, height: 120 * sc)),
                 with: .linearGradient(Gradient(colors: [.white.opacity(0.06), .clear]),
                                       startPoint: CGPoint(x: w / 2, y: y(84)), endPoint: CGPoint(x: w / 2, y: y(84) + 120 * sc)))
    }

    /// A few soft clouds drifting slowly across the sky.
    private func clouds(_ ctx: GraphicsContext, _ sc: CGFloat, w: CGFloat, topY: CGFloat, botY: CGFloat) {
        let t = CGFloat(station.animT)
        let data: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [   // fx, fy, size, drift
            (0.18, 0.30, 1.2, 6), (0.52, 0.55, 1.7, 4), (0.83, 0.22, 1.0, 8), (0.68, 0.70, 1.35, 5)]
        let span = w + 180 * sc
        for (fx, fy, sz, spd) in data {
            var cx = (fx * w + t * spd * sc).truncatingRemainder(dividingBy: span)
            if cx < 0 { cx += span }
            cx -= 90 * sc
            let cy = topY + fy * (botY - topY)
            let s = sz * sc
            ctx.drawLayer { g in
                g.addFilter(.blur(radius: 5 * s))
                for (dx, dy, r) in [(-1.1, 0.15, 1.0), (0.0, -0.35, 1.35), (1.15, 0.12, 0.95), (0.45, 0.4, 0.8)] {
                    let rw = 30 * s * r, rh = 17 * s * r
                    g.fill(Path(ellipseIn: CGRect(x: cx + dx * 20 * s - rw, y: cy + dy * 12 * s - rh, width: rw * 2, height: rh * 2)),
                           with: .color(.white.opacity(0.5)))
                }
            }
        }
    }

    /// Newark Castle — a ruined curtain wall with a gatehouse, low on the skyline.
    private func castle(_ ctx: GraphicsContext, baseY: CGFloat, sc: CGFloat, w: CGFloat) {
        let cx = w * 0.16
        let col = Color(red: 0.34, green: 0.33, blue: 0.36)
        func merlons(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ h: CGFloat) {
            var p = Path()
            p.move(to: CGPoint(x: x, y: baseY))
            p.addLine(to: CGPoint(x: x, y: top))
            var xi = x
            let step = 8 * sc
            var up = true
            while xi < x + width { p.addLine(to: CGPoint(x: xi, y: up ? top : top + h)); xi += step; up.toggle() }
            p.addLine(to: CGPoint(x: x + width, y: baseY)); p.closeSubpath()
            ctx.fill(p, with: .color(col))
        }
        merlons(cx, baseY - 34 * sc, 150 * sc, 8 * sc)                 // curtain wall
        merlons(cx - 14 * sc, baseY - 58 * sc, 40 * sc, 9 * sc)        // gatehouse tower
        merlons(cx + 138 * sc, baseY - 52 * sc, 34 * sc, 9 * sc)       // corner tower
    }

    private func railLine(_ ctx: GraphicsContext, _ pts: [CGPoint], _ sc: CGFloat, tint: Color?, width: CGFloat = 15, _ S: (CGPoint) -> CGPoint) {
        var p = Path()
        for (i, pt) in pts.enumerated() { i == 0 ? p.move(to: S(pt)) : p.addLine(to: S(pt)) }
        ctx.stroke(p, with: .color(railEdge), style: .init(lineWidth: width * sc, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(railSteel), style: .init(lineWidth: (width - 6) * sc, lineCap: .round, lineJoin: .round))
        if let tint { ctx.stroke(p, with: .color(tint.opacity(0.5)), style: .init(lineWidth: 3 * sc, lineCap: .round, lineJoin: .round)) }
        ctx.stroke(p, with: .color(railSheen.opacity(0.35)), style: .init(lineWidth: 2 * sc, lineCap: .round, lineJoin: .round))
    }

    private func drawRails(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        // East Coast Main Line — straight through the crossing.
        railLine(ctx, [CGPoint(x: contentMinX, y: s.yEcml), CGPoint(x: contentMaxX, y: s.yEcml)], sc, tint: ecmlTint, S)
        // Castle line — a horizontal platform run, then a dive across the main line at the diamond, and away.
        let exitY = s.yEcml + (s.yEcml - s.yCastle) / (s.xD - s.platR) * (contentMaxX - s.xD)
        railLine(ctx, [CGPoint(x: contentMinX, y: s.yCastle), CGPoint(x: s.platR, y: s.yCastle),
                       CGPoint(x: s.xD, y: s.yEcml), CGPoint(x: contentMaxX, y: exitY)], sc, tint: castleTint, S)
    }

    /// The flat crossing itself — a bold diamond where the rails cross.
    private func drawDiamond(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let c = S(station.diamond)
        let r = 16 * sc
        var d = Path()
        d.move(to: CGPoint(x: c.x, y: c.y - r)); d.addLine(to: CGPoint(x: c.x + r, y: c.y))
        d.addLine(to: CGPoint(x: c.x, y: c.y + r)); d.addLine(to: CGPoint(x: c.x - r, y: c.y)); d.closeSubpath()
        ctx.fill(d, with: .color(Color(red: 0.16, green: 0.17, blue: 0.20)))
        ctx.stroke(d, with: .color(railSheen.opacity(0.5)), style: .init(lineWidth: 2 * sc))
        // a warning ring so the conflict point reads at a glance
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r * 1.5, y: c.y - r * 1.5, width: r * 3, height: r * 3)),
                   with: .color(Color(red: 0.95, green: 0.78, blue: 0.24).opacity(0.35)), style: .init(lineWidth: 2 * sc, dash: [4 * sc, 4 * sc]))
    }

    private func drawPlatform(_ ctx: GraphicsContext, y: CGFloat, tint: Color, sc: CGFloat, above: Bool, S: (CGPoint) -> CGPoint) {
        let s = station
        let depth: CGFloat = 11
        let rect = CGRect(x: S(CGPoint(x: s.platL - 30, y: 0)).x, y: S(CGPoint(x: 0, y: y)).y,
                          width: (s.platR - s.platL + 60) * sc, height: 20 * sc)
        let rr = Path(roundedRect: rect, cornerRadius: 11 * sc)
        let side = Path(roundedRect: rect.offsetBy(dx: 0, dy: depth * sc), cornerRadius: 11 * sc)
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: .black.opacity(0.5), radius: 5 * sc, x: 0, y: 6 * sc))
            l.fill(side, with: .color(Color(red: 0.18, green: 0.21, blue: 0.28)))
        }
        ctx.fill(rr, with: .color(Color(red: 0.44, green: 0.45, blue: 0.50)))
        // stripe on the track-facing edge
        let stripeY = above ? rect.maxY - 4 * sc : rect.minY
        ctx.fill(Path(CGRect(x: rect.minX, y: stripeY, width: rect.width, height: 4 * sc)), with: .color(tint))
        ctx.stroke(rr, with: .color(.white.opacity(0.22)), style: .init(lineWidth: 2 * sc))
    }

    private func drawTrain(_ ctx: GraphicsContext, _ t: NewarkTrain, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for c in 0..<t.spec.length {
            let d = t.dist - (CGFloat(c) + 0.5) * Track.carUnit
            guard d >= 0, d <= t.path.total else { continue }
            let smp = t.path.sample(d)
            drawCarriage(ctx, at: S(smp.p), angle: t.path.smoothAngle(d), tint: t.spec.tint,
                         cw: Track.carUnit - 6, ch: Track.carHeight, scale: sc, seatsFilled: Int(t.load.rounded()) - c * 3)
        }
        if t.stopped > 3.5, t.dist >= 0, t.dist <= t.path.total {
            let prog = CGFloat((t.stopped - 3.5).truncatingRemainder(dividingBy: 2.4) / 2.4)
            var g = ctx; g.opacity = Double(1 - prog)
            let head = t.path.sample(t.dist).p
            drawMood(g, "😴", at: S(CGPoint(x: head.x, y: head.y - 30 - prog * 26)), scale: sc)
        }
    }

    private func drawPeople(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        pax(ctx, count: s.pEcml, feetY: s.yEcml + 52, sc: sc, agitated: s.ecmlAgitated, t: s.animT, S: S)
        pax(ctx, count: s.pCastle, feetY: s.yCastle - 22, sc: sc, agitated: s.castleAgitated, t: s.animT, S: S)
        floatMood(ctx, s.ecmlMood, at: CGPoint(x: s.platL + 20, y: s.yEcml + 66), phase: 0.0, sc: sc, S: S)
        floatMood(ctx, s.castleMood, at: CGPoint(x: s.platL + 20, y: s.yCastle - 48), phase: 1.2, sc: sc, S: S)
    }

    private func floatMood(_ ctx: GraphicsContext, _ mood: Mood, at p: CGPoint, phase: Double, sc: CGFloat, S: (CGPoint) -> CGPoint) {
        guard mood.shows else { return }
        let prog = CGFloat((station.animT + phase).truncatingRemainder(dividingBy: 2.6) / 2.6)
        var g = ctx; g.opacity = Double(1 - prog)
        drawMood(g, mood.emoji, at: S(CGPoint(x: p.x, y: p.y - prog * 26)), scale: sc)
    }

    private func pax(_ ctx: GraphicsContext, count: Double, feetY: CGFloat, sc: CGFloat,
                     agitated: Bool, t: Double, S: (CGPoint) -> CGPoint) {
        let clothes: [Color] = [Color(red: 0.30, green: 0.55, blue: 0.85), Color(red: 0.86, green: 0.45, blue: 0.38),
                                Color(red: 0.40, green: 0.70, blue: 0.52), Color(red: 0.78, green: 0.62, blue: 0.30),
                                Color(red: 0.62, green: 0.46, blue: 0.78)]
        let skin = Color(red: 0.97, green: 0.83, blue: 0.70)
        let n = min(Int(count), 14)
        for k in 0..<max(n, 0) {
            let pace = agitated ? CGFloat(sin(t * 2.0 + Double(k) * 1.7)) * 8 : 0
            let base = S(CGPoint(x: station.platL - 6 + CGFloat(k) * 15 + pace, y: feetY))
            let px = base.x, feet = base.y
            let coat = agitated ? Color(red: 0.90, green: 0.36, blue: 0.32) : clothes[k % clothes.count]
            let bw = 11 * sc, bh = 14 * sc, top = feet - bh
            var torso = Path()
            torso.move(to: CGPoint(x: px - bw * 0.32, y: top + bw * 0.28))
            torso.addQuadCurve(to: CGPoint(x: px + bw * 0.32, y: top + bw * 0.28), control: CGPoint(x: px, y: top - bw * 0.05))
            torso.addLine(to: CGPoint(x: px + bw * 0.42, y: feet)); torso.addLine(to: CGPoint(x: px - bw * 0.42, y: feet))
            torso.closeSubpath()
            ctx.fill(torso, with: .color(coat))
            let hd = 8 * sc
            ctx.fill(Path(ellipseIn: CGRect(x: px - hd / 2, y: top - hd * 0.72, width: hd, height: hd)), with: .color(skin))
        }
    }

    private func drawSignals(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let sig = sc * 2.5
        // Two lights per line: entry (admit into the platform) and starter (send over the crossing).
        drawSignal(ctx, at: S(ecmlEntryPt()), red: !s.entryOpen(.ecml), scale: sig)
        drawSignal(ctx, at: S(ecmlStarterPt()), red: !s.starterOpen(.ecml), scale: sig)
        drawSignal(ctx, at: S(castleEntryPt()), red: !s.entryOpen(.castle), scale: sig)
        drawSignal(ctx, at: S(castleStarterPt()), red: !s.starterOpen(.castle), scale: sig)
        // A little indicator on the diamond so the crossing conflict reads: red while a train is over it.
        drawSignal(ctx, at: S(CGPoint(x: s.xD + 30, y: s.yEcml - 30)), red: s.diamondOccupied, scale: sig * 0.8)
    }

    // Entry lights sit at the platform mouth, starters at the exit end toward the crossing — lifted off the rail.
    private func ecmlEntryPt() -> CGPoint { CGPoint(x: station.platL, y: station.yEcml - 26) }
    private func ecmlStarterPt() -> CGPoint { CGPoint(x: station.platR, y: station.yEcml - 26) }
    private func castleEntryPt() -> CGPoint { CGPoint(x: station.platL, y: station.yCastle + 26) }
    private func castleStarterPt() -> CGPoint { CGPoint(x: station.platR, y: station.yCastle + 26) }

    // MARK: controls / HUD

    /// A tappable signal halo, centred on the lamp (which draws ~22px above its anchor).
    private func signalButton(_ action: @escaping () -> Void, at p: CGPoint, _ scale: CGFloat, _ size: CGSize) -> some View {
        Button(action: { action(); Sound.shared.play(.tap) }) {
            SignalHalo().frame(width: 58, height: 58).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .position(project(CGPoint(x: p.x, y: p.y - 22), scale, size))
    }

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
            // Entry admits a train into the platform; the starter sends the loaded train over the crossing.
            signalButton({ station.toggleEntry(.ecml) }, at: ecmlEntryPt(), scale, size)
            signalButton({ station.toggleStarter(.ecml) }, at: ecmlStarterPt(), scale, size)
            signalButton({ station.toggleEntry(.castle) }, at: castleEntryPt(), scale, size)
            signalButton({ station.toggleStarter(.castle) }, at: castleStarterPt(), scale, size)

            Button(action: { Sound.shared.play(.ui); confirmExit = true }) {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Color(white: 0.9))
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.82, green: 0.24, blue: 0.24).opacity(0.94), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14)))
            }
            .buttonStyle(PressStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(28)

            MuteButton().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(28)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(Int(station.carried))").font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.34, green: 0.86, blue: 0.5))
                Text("people").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.82))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 34).padding(.bottom, 26)

            VStack(alignment: .trailing, spacing: 2) {
                Text(station.name).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(station.def.county) \(station.def.flag)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.82))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 34).padding(.bottom, 26)
        }
    }
}

#Preview { NewarkView(def: allStations[3]) { } }
