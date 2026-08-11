import SwiftUI

struct WorcesterView: View {
    @StateObject private var station: WorcesterStation
    let onExit: () -> Void
    init(def: StationDef, onExit: @escaping () -> Void) {
        _station = StateObject(wrappedValue: WorcesterStation(def))
        self.onExit = onExit
    }
    private let tick = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    @State private var confirmExit = false
    @State private var started = false

    private let worldW: CGFloat = 1520
    private let contentMinX: CGFloat = -340
    private let contentMaxX: CGFloat = 1840
    @State private var originX: CGFloat = 40
    @State private var dragStartX: CGFloat? = nil
    private let dcross: CGFloat = 40

    private let orange = WorcesterStation.wmrOrange
    private let lime = WorcesterStation.gwrGreen
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
                    drawPlatform(ctx, y: station.yP2 - 40, tint: orange, sc: sc, S: S)
                    drawPlatform(ctx, y: station.yP1 + 26, tint: lime, sc: sc, S: S)
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

    // MARK: scene — the Faithful City on the Severn, Malverns on the western skyline, moon over the hills

    private func drawScene(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize) {
        let w = size.width
        let vOff = (size.height - Track.H * sc) / 2
        func y(_ d: CGFloat) -> CGFloat { d * sc + vOff }
        func band(_ y0: CGFloat, _ y1: CGFloat, _ top: Color, _ bot: Color) {
            let r = CGRect(x: 0, y: y0, width: w, height: y1 - y0)
            ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [top, bot]),
                                                    startPoint: CGPoint(x: r.midX, y: r.minY),
                                                    endPoint: CGPoint(x: r.midX, y: r.maxY)))
        }
        band(0, y(122), Color(red: 0.24, green: 0.28, blue: 0.40), Color(red: 0.42, green: 0.40, blue: 0.46))
        let moonC = CGPoint(x: w * 0.70, y: y(46))
        ctx.drawLayer { g in
            g.addFilter(.blur(radius: 11 * sc))
            g.fill(Path(ellipseIn: CGRect(x: moonC.x - 28 * sc, y: moonC.y - 28 * sc, width: 56 * sc, height: 56 * sc)),
                   with: .color(.white.opacity(0.22)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: moonC.x - 15 * sc, y: moonC.y - 15 * sc, width: 30 * sc, height: 30 * sc)),
                 with: .color(Color(red: 0.95, green: 0.95, blue: 0.90)))
        malverns(ctx, horizonY: y(122), sc: sc, w: w, dy: 2, colour: Color(red: 0.30, green: 0.32, blue: 0.44), amp: 0.7)
        malverns(ctx, horizonY: y(124), sc: sc, w: w, dy: 5, colour: Color(red: 0.20, green: 0.23, blue: 0.33), amp: 1.0)
        band(y(116), y(146), Color(red: 0.18, green: 0.21, blue: 0.24), Color(red: 0.15, green: 0.18, blue: 0.20))
        band(y(146), size.height, Color(red: 0.22, green: 0.27, blue: 0.20), Color(red: 0.15, green: 0.18, blue: 0.14))
    }

    private func malverns(_ ctx: GraphicsContext, horizonY: CGFloat, sc: CGFloat, w: CGFloat, dy: CGFloat, colour: Color, amp: CGFloat) {
        let pk: [(CGFloat, CGFloat)] = [(0, -6), (0.10, -34), (0.18, -58), (0.26, -40), (0.34, -74),
                                        (0.44, -52), (0.52, -88), (0.60, -60), (0.68, -70), (0.78, -40),
                                        (0.87, -52), (0.94, -26), (1, -12)]
        var ridge = Path()
        ridge.move(to: CGPoint(x: 0, y: horizonY + dy * sc))
        for (fx, h) in pk { ridge.addLine(to: CGPoint(x: fx * w, y: horizonY + (dy + h * amp) * sc)) }
        ridge.addLine(to: CGPoint(x: w, y: horizonY + 40 * sc))
        ridge.addLine(to: CGPoint(x: 0, y: horizonY + 40 * sc)); ridge.closeSubpath()
        ctx.fill(ridge, with: .color(colour))
    }

    private func drawPlatform(_ ctx: GraphicsContext, y: CGFloat, tint: Color, sc: CGFloat, S: (CGPoint) -> CGPoint) {
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
        let stripeY = y < s.yP2 ? rect.maxY - 4 * sc : rect.minY
        ctx.fill(Path(CGRect(x: rect.minX, y: stripeY, width: rect.width, height: 4 * sc)), with: .color(tint))
        ctx.stroke(rr, with: .color(.white.opacity(0.22)), style: .init(lineWidth: 2 * sc))
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
        let d = dcross
        // Platform 2 (orange): in from Malvern, crossing down to the single line at the east throat
        railLine(ctx, [CGPoint(x: contentMinX, y: s.yP2), CGPoint(x: s.xEJ, y: s.yP2), CGPoint(x: s.xEJ + d, y: s.ySingle)], sc, tint: orange, S)
        // Platform 1 (lime): out west to Malvern, crossing up from the single line
        railLine(ctx, [CGPoint(x: contentMinX, y: s.yP1), CGPoint(x: s.xEJ, y: s.yP1), CGPoint(x: s.xEJ + d, y: s.ySingle)], sc, tint: lime, S)
        // the single Shrub Hill line — the shared bottleneck, running east to the last junction, drawn a touch heavier
        railLine(ctx, [CGPoint(x: s.xEJ + d, y: s.ySingle), CGPoint(x: s.eastmostBranchX, y: s.ySingle)], sc, tint: nil, width: 17, S)
        // each line peels off the single line at its own staggered junction, gradually (in / out / in / out)
        for y in s.branchYs {
            let bx = s.branchX(y)
            let out = (y == s.yDroitwich || y == s.yBirmingham)
            railLine(ctx, [CGPoint(x: bx, y: s.ySingle), CGPoint(x: bx + s.branchFan, y: y), CGPoint(x: contentMaxX, y: y)], sc, tint: out ? orange : lime, S)
        }
    }

    private func drawTrain(_ ctx: GraphicsContext, _ t: WorcTrain, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
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
        pax(ctx, count: s.pP2, feetY: s.yP2 - 32, sc: sc, agitated: s.p2Agitated, t: s.animT, S: S)
        pax(ctx, count: s.pP1, feetY: s.yP1 + 36, sc: sc, agitated: s.p1Agitated, t: s.animT, S: S)
        floatMood(ctx, s.p2Mood, at: CGPoint(x: s.platL + 20, y: s.yP2 - 46), phase: 0.0, sc: sc, S: S)
        floatMood(ctx, s.p1Mood, at: CGPoint(x: s.platL + 20, y: s.yP1 + 62), phase: 1.2, sc: sc, S: S)
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
        // Single-line signals: green shows what the single track is granted for right now.
        drawSignal(ctx, at: S(CGPoint(x: s.platR + 44, y: s.yP2 - 24)), red: s.grant != .east, scale: sig)   // Platform 2 starter, out east
        drawSignal(ctx, at: S(CGPoint(x: s.xSH + 34, y: s.yLondon)), red: s.grant != .london, scale: sig)          // admit from London
        drawSignal(ctx, at: S(CGPoint(x: s.xSH + 34, y: s.yBristol)), red: s.grant != .bristol, scale: sig)        // admit from Bristol
        let esig = sig * 0.9
        // Queue signals down the inbound-left (eastbound) approach — three-aspect: red / amber / green as blocks fill.
        for x in s.p2QueueXs {
            drawBlockSignal(ctx, at: S(CGPoint(x: x, y: s.yP2 - 24)), aspect: s.p2QueueAspect(x), scale: esig * 0.92)
        }
        // A light on each eastern junction, lifted off the single line toward its own road — green when the line
        // is set that way, amber when a train waits on it, red otherwise.
        for y in s.branchYs {
            let off: CGFloat = y < s.ySingle ? -28 : 28
            drawBlockSignal(ctx, at: S(CGPoint(x: s.branchX(y) + 8, y: s.ySingle + off)), aspect: s.branchAspect(y), scale: esig * 0.85)
        }
        // Platform 1 (bottom) starting signal — at its west end, where it berths and departs to Malvern.
        drawSignal(ctx, at: S(CGPoint(x: s.platL - 40, y: s.yP1)), red: s.p1Busy, scale: esig)
    }

    // MARK: controls / HUD

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
            // Grant the single line: send a Platform 2 train out east, or admit an inbound train from London or
            // Bristol. One movement at a time — you sequence them.
            Button(action: { station.setGrant(.east); Sound.shared.play(.tap) }) {
                SignalHalo().frame(width: 64, height: 64).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .position(project(CGPoint(x: station.platR + 44, y: station.yP2 - 46), scale, size))
            Button(action: { station.setGrant(.london); Sound.shared.play(.tap) }) {
                SignalHalo().frame(width: 60, height: 60).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .position(project(CGPoint(x: station.xSH + 34, y: station.yLondon - 22), scale, size))
            Button(action: { station.setGrant(.bristol); Sound.shared.play(.tap) }) {
                SignalHalo().frame(width: 60, height: 60).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .position(project(CGPoint(x: station.xSH + 34, y: station.yBristol - 22), scale, size))

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

#Preview { WorcesterView(def: allStations[2]) { } }
