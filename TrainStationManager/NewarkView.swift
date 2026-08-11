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
    @State private var tutStep = 0
    @State private var tutClock = 0.0
    private let tutSteps = [
        "Newark — the East Coast Main Line crosses the Castle line flat. Only one train fits the crossing at a time.",
        "Tap a signal to grant the crossing — the blue main line, or the orange Castle line. Let them take turns.",
        "Load both platforms before their trains reach the diamond, and don't let either fill up.",
        "Carry 45 people to clear the crossing."
    ]
    private func advanceTut(sound: Bool) { if sound { Sound.shared.play(.ui) }; tutStep += 1; tutClock = 0 }

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

                if tutStep >= 0 && tutStep < tutSteps.count && station.outcome == .playing {
                    TutorialCard(text: tutSteps[tutStep], isLast: tutStep == tutSteps.count - 1) { advanceTut(sound: true) }
                }
                if station.outcome != .playing {
                    OutcomeOverlay(won: station.outcome == .won,
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
        .onReceive(tick) { _ in
            station.tick(0.03)
            if tutStep >= 0 && tutStep < tutSteps.count { tutClock += 0.03; if tutClock > 6 { advanceTut(sound: false) } }
        }
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
        band(0, y(70), Color(red: 0.52, green: 0.62, blue: 0.78), Color(red: 0.78, green: 0.80, blue: 0.82))
        castle(ctx, baseY: y(70), sc: sc, w: w)
        band(y(64), y(84), Color(red: 0.30, green: 0.40, blue: 0.30), Color(red: 0.26, green: 0.34, blue: 0.26))
        band(y(84), size.height, Color(red: 0.26, green: 0.31, blue: 0.22), Color(red: 0.17, green: 0.21, blue: 0.15))
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
                         cw: Track.carUnit - 6, ch: Track.carHeight, scale: sc)
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
        // A signal on each line protecting the crossing — green shows which line the diamond is granted to.
        drawSignal(ctx, at: S(ecmlControlPoint()), red: s.grant != .ecml, scale: sig)
        drawSignal(ctx, at: S(castleSignalPoint()), red: s.grant != .castle, scale: sig)
    }

    // Where the Castle-line signal sits — on the dive to the diamond, lifted off the rail.
    private func castleSignalPoint() -> CGPoint {
        let s = station
        let t: CGFloat = 0.62
        let x = s.platR + (s.xD - s.platR) * t
        let y = s.yCastle + (s.yEcml - s.yCastle) * t
        return CGPoint(x: x - 8, y: y - 26)
    }
    private func ecmlControlPoint() -> CGPoint { CGPoint(x: station.xD - 66, y: station.yEcml - 26) }

    // MARK: controls / HUD

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
            // Grant the crossing to one line at a time.
            Button(action: { station.setGrant(.ecml); Sound.shared.play(.tap) }) {
                SignalHalo().frame(width: 62, height: 62).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .position(project(ecmlControlPoint(), scale, size))
            Button(action: { station.setGrant(.castle); Sound.shared.play(.tap) }) {
                SignalHalo().frame(width: 62, height: 62).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .position(project(castleSignalPoint(), scale, size))

            Button(action: { Sound.shared.play(.ui); confirmExit = true }) {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Color(white: 0.9))
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.16, green: 0.19, blue: 0.25).opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14)))
            }
            .buttonStyle(PressStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)

            MuteButton().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(16)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(Int(station.carried))").font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.34, green: 0.86, blue: 0.5))
                Text("people").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.82))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 22).padding(.bottom, 14)

            VStack(alignment: .trailing, spacing: 2) {
                Text(station.name).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(station.def.county) \(station.def.flag)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.82))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 22).padding(.bottom, 16)
        }
    }
}

#Preview { NewarkView(def: allStations[3]) { } }
