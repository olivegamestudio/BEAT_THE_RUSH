import SwiftUI

struct DawlishView: View {
    @StateObject private var station: DawlishStation
    let onExit: () -> Void
    init(def: StationDef, onExit: @escaping () -> Void) {
        _station = StateObject(wrappedValue: DawlishStation(def))
        self.onExit = onExit
    }
    private let tick = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    @State private var confirmExit = false
    @State private var started = false

    private let designW: CGFloat = 1200
    // The viewport shows a window a little wider than the 1200-unit layout; the content runs well past
    // both ends so you can drag to watch the trains stack up on the approaches.
    private let worldW: CGFloat = 1500          // viewport width, in world units
    private let contentMinX: CGFloat = -440     // leftmost world x (westbound approach / eastbound exit)
    private let contentMaxX: CGFloat = 1640     // rightmost world x
    @State private var originX: CGFloat = -150   // world x drawn at the screen's left edge
    @State private var dragStartX: CGFloat? = nil
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
                    drawScene(ctx, sc, size, S)
                    drawTanker(ctx, sc, size)        // a distant ship out on the estuary
                    drawGull(ctx, sc, size)          // a seagull in the sky
                    drawBoat(ctx, sc, size)          // a speed boat on the estuary
                    drawRails(ctx, sc, S)
                    // Depth by screen height: the up platform sits behind its trains, the down platform in
                    // front of its trains, and the trains themselves draw back-to-front (lower = nearer).
                    drawPlatform(ctx, y: 176, occupied: station.pUp > 0, sc: sc, S: S)
                    let ordered = station.trains.sorted { $0.path.sample($0.dist).p.y < $1.path.sample($1.dist).p.y }
                    for t in ordered { drawTrain(ctx, t, sc, S) }
                    drawPlatform(ctx, y: 384, occupied: station.pDown > 0, sc: sc, S: S)
                    drawPeople(ctx, sc, S)
                    for sp in station.sparkles {
                        drawSparkleBurst(ctx, at: S(CGPoint(x: sp.x, y: sp.y)), age: sp.age, life: sparkleLife, scale: sc, toward: CGPoint(x: size.width * 0.07, y: size.height * 0.90))
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
                Vignette(strength: 0.45)
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
        .onReceive(tick) { _ in
            if started { station.tick(0.03) }
        }
        .statusBarHidden()
    }

    // MARK: the coast

    private func band(_ ctx: GraphicsContext, _ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat,
                      _ top: Color, _ bot: Color) {
        let r = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        ctx.fill(Path(r), with: .linearGradient(Gradient(colors: [top, bot]),
                                                startPoint: CGPoint(x: r.midX, y: r.minY),
                                                endPoint: CGPoint(x: r.midX, y: r.maxY)))
    }

    private func drawScene(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize, _ S: (CGPoint) -> CGPoint) {
        let w = size.width
        let vOff = (size.height - Track.H * sc) / 2
        func y(_ d: CGFloat) -> CGFloat { d * sc + vOff }
        // A sandy spit at the mouth of the Exe: estuary behind, beach and sea in front.
        band(ctx, 0, w, 0, y(100), Color(red: 0.27, green: 0.38, blue: 0.53), Color(red: 0.36, green: 0.47, blue: 0.60))     // sky
        // a low sun out over the estuary — drifts a touch with the pan, but it's so distant it barely parallaxes
        let sunC = CGPoint(x: w * 0.24 - originX * 0.1 * sc, y: y(38))
        ctx.drawLayer { g in
            g.addFilter(.blur(radius: 18 * sc))
            g.fill(Path(ellipseIn: CGRect(x: sunC.x - 40 * sc, y: sunC.y - 40 * sc, width: 80 * sc, height: 80 * sc)),
                   with: .color(Color(red: 1.0, green: 0.86, blue: 0.55).opacity(0.4)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: sunC.x - 20 * sc, y: sunC.y - 20 * sc, width: 40 * sc, height: 40 * sc)),
                 with: .color(Color(red: 1.0, green: 0.90, blue: 0.66)))
        band(ctx, 0, w, y(88), y(106), Color(red: 0.21, green: 0.28, blue: 0.25), Color(red: 0.17, green: 0.24, blue: 0.22)) // far shore
        band(ctx, 0, w, y(100), y(136), Color(red: 0.16, green: 0.28, blue: 0.33), Color(red: 0.12, green: 0.23, blue: 0.28)) // Exe estuary
        band(ctx, 0, w, y(136), y(182), Color(red: 0.44, green: 0.38, blue: 0.27), Color(red: 0.36, green: 0.31, blue: 0.22)) // sand dunes
        band(ctx, 0, w, y(182), y(386), Color(red: 0.42, green: 0.38, blue: 0.29), Color(red: 0.37, green: 0.33, blue: 0.26)) // sandy ground
        band(ctx, 0, w, y(386), y(420), Color(red: 0.46, green: 0.40, blue: 0.29), Color(red: 0.40, green: 0.35, blue: 0.26)) // beach
        band(ctx, 0, w, y(420), size.height, Color(red: 0.08, green: 0.22, blue: 0.31), Color(red: 0.05, green: 0.15, blue: 0.24)) // sea
        marram(ctx, y0: y(146), sc: sc, size: size)            // grass on the dunes (parallax-scrolled)
        for k in 0..<3 {                                        // waves
            let wy = y(430 + CGFloat(k) * 9)
            var wave = Path(); wave.move(to: CGPoint(x: 20, y: wy)); wave.addLine(to: CGPoint(x: w - 20, y: wy))
            ctx.stroke(wave, with: .color(.white.opacity(0.09)), style: .init(lineWidth: 2 * sc, lineCap: .round))
        }
        var rip = Path(); rip.move(to: CGPoint(x: 20, y: y(122))); rip.addLine(to: CGPoint(x: w - 20, y: y(122)))
        ctx.stroke(rip, with: .color(.white.opacity(0.08)), style: .init(lineWidth: 2 * sc, lineCap: .round))
    }

    /// A big tanker inching across the far estuary — a hazy low silhouette, world-anchored at a slow
    /// parallax so it drifts with the pan but far slower than the foreground (it reads as distant).
    private func drawTanker(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize) {
        guard station.tankerActive else { return }
        let s = sc
        let vOff = (size.height - Track.H * sc) / 2
        let ty = CGFloat(station.tankerY) * sc + vOff
        let dir = CGFloat(station.tankerDir)
        let prog = CGFloat(station.tankerProgress)
        let lo = contentMinX - 300, hi = contentMaxX + 300
        let worldX = dir > 0 ? lo + prog * (hi - lo) : hi - prog * (hi - lo)
        let x = (worldX - originX * 0.4) * sc            // low parallax factor → distant
        let haze = Color(red: 0.32, green: 0.39, blue: 0.47)      // washed-out by distance / haze
        let L = 28.0 * s                                          // half-length — small, it's far off on the horizon
        ctx.drawLayer { g in
            g.addFilter(.blur(radius: 0.5 * s))
            var hull = Path()                                    // a long, low hull
            hull.move(to: CGPoint(x: x - dir * L, y: ty - 1.5 * s))
            hull.addLine(to: CGPoint(x: x + dir * L * 0.86, y: ty - 2 * s))
            hull.addQuadCurve(to: CGPoint(x: x + dir * L, y: ty + 1.5 * s), control: CGPoint(x: x + dir * L * 1.02, y: ty))
            hull.addLine(to: CGPoint(x: x - dir * L, y: ty + 2.5 * s))
            hull.closeSubpath()
            g.fill(hull, with: .color(haze))
            // a few tiny cranes/masts along the deck
            for m in 0..<4 {
                let mx = x - dir * L * 0.5 + dir * CGFloat(m) * L * 0.26
                g.fill(Path(CGRect(x: mx - 0.7 * s, y: ty - 5 * s, width: 1.4 * s, height: 4 * s)), with: .color(haze))
            }
            // superstructure block + funnel at the stern
            let sx = x - dir * L * 0.72
            g.fill(Path(roundedRect: CGRect(x: sx - 4.5 * s, y: ty - 8 * s, width: 9 * s, height: 7 * s), cornerRadius: 1 * s),
                   with: .color(haze))
            g.fill(Path(roundedRect: CGRect(x: sx - 1.5 * s, y: ty - 11 * s, width: 3.5 * s, height: 4 * s), cornerRadius: 0.8 * s),
                   with: .color(Color(red: 0.25, green: 0.30, blue: 0.37)))
        }
    }

    /// An occasional speed boat skimming across the estuary, throwing a bow splash and a spreading wake.
    private func drawBoat(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize) {
        guard station.boatActive else { return }
        let s = sc
        let vOff = (size.height - Track.H * sc) / 2
        let by = CGFloat(station.boatY) * sc + vOff
        let dir = CGFloat(station.boatDir)
        // World-anchored so the boat pans with the scene: it crosses the whole content, projected like the track.
        let prog = CGFloat(station.boatProgress)
        let lo = contentMinX - 120, hi = contentMaxX + 120
        let worldX = dir > 0 ? lo + prog * (hi - lo) : hi - prog * (hi - lo)
        let x = (worldX - originX) * sc
        let sternX = x - dir * 28 * s
        // Wake: a train of chevron ripples that spread wider and fade as they fall behind the stern.
        for k in 0..<4 {
            let ph = CGFloat((station.animT * 1.15 + Double(k) * 0.25).truncatingRemainder(dividingBy: 1))
            let cx = sternX - dir * (6 * s + ph * 80 * s)
            let spread = (4 + ph * 17) * s
            let a = Double(1 - ph) * 0.5
            var rip = Path()
            rip.move(to: CGPoint(x: cx + dir * spread * 0.5, y: by - spread))
            rip.addQuadCurve(to: CGPoint(x: cx + dir * spread * 0.5, y: by + spread),
                             control: CGPoint(x: cx - dir * 5 * s, y: by))
            ctx.stroke(rip, with: .color(.white.opacity(a)), style: .init(lineWidth: 2 * s, lineCap: .round))
        }
        let f = dir                                             // +1 = bow to the right
        var hull = Path()                                       // a side-on speedboat: flat deck, raked bow, transom stern
        hull.move(to: CGPoint(x: x - f * 26 * s, y: by - 6 * s))    // stern top
        hull.addLine(to: CGPoint(x: x + f * 22 * s, y: by - 7 * s)) // deck to the bow
        hull.addQuadCurve(to: CGPoint(x: x + f * 15 * s, y: by + 7 * s),   // bow curves down into the water
                          control: CGPoint(x: x + f * 33 * s, y: by + 2 * s))
        hull.addLine(to: CGPoint(x: x - f * 22 * s, y: by + 7 * s)) // flat bottom back to the stern
        hull.closeSubpath()                                        // transom
        ctx.fill(hull, with: .color(Color(red: 0.94, green: 0.96, blue: 0.99)))
        var stripe = Path()                                     // red boot-stripe along the waterline
        stripe.move(to: CGPoint(x: x - f * 24 * s, y: by + 2 * s)); stripe.addLine(to: CGPoint(x: x + f * 20 * s, y: by + 2 * s))
        ctx.stroke(stripe, with: .color(Color(red: 0.86, green: 0.26, blue: 0.24)), style: .init(lineWidth: 3 * s, lineCap: .round))
        ctx.stroke(hull, with: .color(.black.opacity(0.28)), style: .init(lineWidth: 1 * s))
        var cabin = Path()                                      // a raked windscreen on the deck
        cabin.move(to: CGPoint(x: x - f * 1 * s, y: by - 7 * s))
        cabin.addLine(to: CGPoint(x: x + f * 10 * s, y: by - 7 * s))
        cabin.addLine(to: CGPoint(x: x + f * 5 * s, y: by - 15 * s))
        cabin.closeSubpath()
        ctx.fill(cabin, with: .color(Color(red: 0.30, green: 0.46, blue: 0.64)))
        ctx.drawLayer { g in                                    // bow splash
            g.addFilter(.blur(radius: 1.6 * s))
            g.fill(Path(ellipseIn: CGRect(x: x + dir * 24 * s - 7 * s, y: by - 5 * s, width: 16 * s, height: 11 * s)),
                   with: .color(.white.opacity(0.72)))
        }
    }

    /// An occasional seagull gliding across the sky, wings flapping in a slow beat.
    private func drawGull(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize) {
        guard station.gullActive else { return }
        let w = size.width, s = sc
        let vOff = (size.height - Track.H * sc) / 2
        let gy = CGFloat(station.gullY) * sc + vOff
        let prog = CGFloat(station.gullProgress), span = w + 120 * s
        let x = station.gullDir > 0 ? (-60 * s + prog * span) : (w + 60 * s - prog * span)
        let flap = CGFloat(sin(station.animT * 7))               // −1…1 full wing beat
        let wing = 12 * s
        let tipUp = (5 + flap * 13) * s                          // wing tips sweep high on the up-beat, drop on the down
        let bodyY = gy - flap * 3 * s                            // the bird bobs a little with each stroke
        let tipY = bodyY - tipUp
        var g = Path()
        g.move(to: CGPoint(x: x - wing * 2, y: tipY))
        g.addQuadCurve(to: CGPoint(x: x, y: bodyY), control: CGPoint(x: x - wing, y: bodyY - tipUp * 0.35))
        g.addQuadCurve(to: CGPoint(x: x + wing * 2, y: tipY), control: CGPoint(x: x + wing, y: bodyY - tipUp * 0.35))
        ctx.stroke(g, with: .color(Color(white: 0.9).opacity(0.92)), style: .init(lineWidth: 2.6 * s, lineCap: .round))
        // a small body where the wings meet
        ctx.fill(Path(ellipseIn: CGRect(x: x - 2 * s, y: bodyY - 2 * s, width: 4 * s, height: 5 * s)),
                 with: .color(Color(white: 0.85)))
    }

    /// A row of little marram-grass tufts along the dune top. The tufts are anchored in world space and
    /// projected at a **parallax** fraction of the camera pan, so the dunes drift with the scene but slower
    /// than the tracks — giving depth behind the railway.
    private func marram(_ ctx: GraphicsContext, y0: CGFloat, sc: CGFloat, size: CGSize) {
        let g = Color(red: 0.42, green: 0.52, blue: 0.28)
        let parallax: CGFloat = 0.55                          // <1 → the dunes scroll slower than the foreground
        let pOrigin = originX * parallax
        var wx = contentMinX
        var seed = 3
        while wx < contentMaxX {
            seed = (seed * 7 + 13) % 1000        // bounded pseudo-random, never overflows
            let x = (wx - pOrigin) * sc                       // parallax-projected screen x
            if x > -12 && x < size.width + 12 {
                let h = (10 + CGFloat(seed % 5) * 2) * sc
                var tuft = Path()
                for b in -2...2 {
                    tuft.move(to: CGPoint(x: x, y: y0))
                    tuft.addLine(to: CGPoint(x: x + CGFloat(b) * 2.4 * sc, y: y0 - h))
                }
                ctx.stroke(tuft, with: .color(g.opacity(0.8)), style: .init(lineWidth: 1.4 * sc, lineCap: .round))
            }
            wx += 30 + CGFloat(seed % 4) * 10                 // world-space spacing between tufts
        }
    }

    private func drawPlatforms(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        drawPlatform(ctx, y: 176, occupied: s.pUp > 0, sc: sc, S: S)     // up platform, set back from the up loop
        drawPlatform(ctx, y: 384, occupied: s.pDown > 0, sc: sc, S: S)   // down platform, set back from the down loop
    }

    private func drawPlatform(_ ctx: GraphicsContext, y: CGFloat, occupied: Bool, sc: CGFloat, S: (CGPoint) -> CGPoint) {
        let s = station
        let depth: CGFloat = 11
        let rect = CGRect(x: S(CGPoint(x: s.platL - 30, y: 0)).x, y: S(CGPoint(x: 0, y: y)).y,
                          width: (s.platR - s.platL + 60) * sc, height: 22 * sc)
        let rr = Path(roundedRect: rect, cornerRadius: 12 * sc)
        let side = Path(roundedRect: rect.offsetBy(dx: 0, dy: depth * sc), cornerRadius: 12 * sc)
        ctx.drawLayer { l in                                   // extruded side + drop shadow → a 3D slab
            l.addFilter(.shadow(color: .black.opacity(0.5), radius: 5 * sc, x: 0, y: 6 * sc))
            l.fill(side, with: .color(Color(red: 0.18, green: 0.21, blue: 0.28)))
        }
        ctx.fill(rr, with: .color(Color(red: 0.44, green: 0.45, blue: 0.50)))
        ctx.stroke(rr, with: .color(.white.opacity(0.22)), style: .init(lineWidth: 2 * sc))
    }

    private func railLine(_ ctx: GraphicsContext, _ pts: [CGPoint], _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        var p = Path()
        for (i, pt) in pts.enumerated() { i == 0 ? p.move(to: S(pt)) : p.addLine(to: S(pt)) }
        ctx.stroke(p, with: .color(railEdge), style: .init(lineWidth: 15 * sc, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(railSteel), style: .init(lineWidth: 9 * sc, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(railSheen.opacity(0.5)), style: .init(lineWidth: 2.5 * sc, lineCap: .round, lineJoin: .round))
    }

    private func drawRails(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let d: CGFloat = 60
        // two through mains, running the full width of the pannable content
        railLine(ctx, [CGPoint(x: contentMinX, y: s.upMainY), CGPoint(x: contentMaxX, y: s.upMainY)], sc, S)
        railLine(ctx, [CGPoint(x: contentMinX, y: s.downMainY), CGPoint(x: contentMaxX, y: s.downMainY)], sc, S)
        // platform loops — points off the main and back
        railLine(ctx, [CGPoint(x: s.xW, y: s.upMainY), CGPoint(x: s.xW + d, y: s.upLoopY),
                       CGPoint(x: s.xE - d, y: s.upLoopY), CGPoint(x: s.xE, y: s.upMainY)], sc, S)
        railLine(ctx, [CGPoint(x: s.xW, y: s.downMainY), CGPoint(x: s.xW + d, y: s.downLoopY),
                       CGPoint(x: s.xE - d, y: s.downLoopY), CGPoint(x: s.xE, y: s.downMainY)], sc, S)
    }

    private func drawTrain(_ ctx: GraphicsContext, _ t: DawTrain, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for c in 0..<t.spec.length {
            let d = t.dist - (CGFloat(c) + 0.5) * Track.carUnit
            guard d >= 0, d <= t.path.total else { continue }   // a car off the end has exited — don't draw it
            let smp = t.path.sample(d)
            // The steam special leads with its engine (car 0), coaches behind; smoke streams off the chimney.
            if t.steam && c == 0 {
                // The engine is longer and taller than a coach — it reaches forward past the nose and back
                // to meet the first carriage, so it reads as a proper locomotive rather than a stubby box.
                let locoCW = Track.carUnit * 1.16, locoCH = Track.carHeight * 1.05
                let phase = t.dist / (0.19 * locoCH)         // wheels roll with distance travelled
                drawSteamLoco(ctx, at: S(smp.p), angle: t.path.smoothAngle(d),
                              cw: locoCW, ch: locoCH, scale: sc, phase: phase)
                let fwd: CGFloat = t.dir == .east ? 1 : -1
                let base = S(smp.p)
                let chim = CGPoint(x: base.x + fwd * 0.30 * locoCW * sc,
                                   y: base.y - 0.50 * locoCH * sc)
                drawSteamPlume(ctx, at: chim, back: -fwd, t: station.animT, scale: sc, rate: t.smokeRate)
                continue
            }
            // An express is a power car at each end — rounded, no windows — with coaches between.
            let endCap = t.express && (c == 0 || c == t.spec.length - 1)
            // Heritage coaches keep the standard length (so they don't leave gaps in the rake) but are drawn
            // squarer, in brown; modern stock stays as-is.
            drawCarriage(ctx, at: S(smp.p), angle: t.path.smoothAngle(d), tint: t.spec.tint,
                         cw: Track.carUnit - 6, ch: Track.carHeight, scale: sc, endCap: endCap,
                         fill: min(1, t.load / (Double(t.spec.length) * 3)), seed: t.id.hashValue &+ c,
                         cornerRadius: t.steam ? 3 : nil)
        }
        // A train sat at a red for a while shows a waiting bubble that floats up and fades, over and over.
        if t.stopped > 3.5, t.dist >= 0, t.dist <= t.path.total {
            let prog = CGFloat((t.stopped - 3.5).truncatingRemainder(dividingBy: 2.4) / 2.4)
            var g = ctx; g.opacity = Double(1 - prog)
            let head = t.path.sample(t.dist).p
            drawMood(g, "😴", at: S(CGPoint(x: head.x, y: head.y - 30 - prog * 26)), scale: sc)
        }
    }

    private func drawPeople(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        pax(ctx, count: s.pUp, x0: s.platL - 6, feetY: 198, sc: sc, agitated: s.upAgitated, t: s.animT, S: S)
        pax(ctx, count: s.pDown, x0: s.platL - 6, feetY: 388, sc: sc, agitated: s.downAgitated, t: s.animT, S: S)
        if s.upMood.shows { drawMood(ctx, s.upMood.emoji, at: S(CGPoint(x: s.platL + 20, y: 164)), scale: sc) }
        if s.downMood.shows { drawMood(ctx, s.downMood.emoji, at: S(CGPoint(x: s.platL + 20, y: 374)), scale: sc) }
    }

    private func pax(_ ctx: GraphicsContext, count: Double, x0: CGFloat, feetY: CGFloat, sc: CGFloat,
                     agitated: Bool, t: Double, S: (CGPoint) -> CGPoint) {
        let clothes: [Color] = [Color(red: 0.30, green: 0.55, blue: 0.85), Color(red: 0.86, green: 0.45, blue: 0.38),
                                Color(red: 0.40, green: 0.70, blue: 0.52), Color(red: 0.78, green: 0.62, blue: 0.30),
                                Color(red: 0.62, green: 0.46, blue: 0.78)]
        let skin = Color(red: 0.97, green: 0.83, blue: 0.70)
        let n = min(Int(count), 14)
        for k in 0..<max(n, 0) {
            let pace = agitated ? CGFloat(sin(t * 2.0 + Double(k) * 1.7)) * 8 : 0
            let base = S(CGPoint(x: x0 + CGFloat(k) * 15 + pace, y: feetY))
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
        let sig = sc * 2.5                         // same size as the Saltash signals
        // Platform starters at the exit end of each loop — tap to hold (red) or clear (green) the boarded train.
        drawSignal(ctx, at: S(CGPoint(x: s.platR + 34, y: s.upLoopY - 18)), red: s.upHold, scale: sig)     // top: lifted off the track
        drawSignal(ctx, at: S(CGPoint(x: s.platL - 44, y: s.downLoopY + 40)), red: s.downHold, scale: sig)  // bottom: down & left, beside the platform
        // Main point signal at each entry — red only while the interlock shuts it (you've cleared the platform
        // and a local is pulling out onto the main).
        drawSignal(ctx, at: S(CGPoint(x: s.xW - 20, y: s.upMainY - 18)), red: s.upMainBlocked, scale: sig)  // top-left point: up & left, off the track
        drawSignal(ctx, at: S(CGPoint(x: s.xE + 20, y: s.downMainY + 40)), red: s.downMainBlocked, scale: sig)  // bottom-right point: down & right, off the track
        // Automatic three-aspect block signals down each main — green/amber/red on their own as blocks fill.
        // A through train stops at a red, eases off at an amber, so a fast train stays spaced back from a local.
        for bx in s.blockXs {
            drawBlockSignal(ctx, at: S(CGPoint(x: bx, y: s.upMainY - 30)), aspect: s.blockAspect(bx, .east), scale: sig * 0.68)
            drawBlockSignal(ctx, at: S(CGPoint(x: bx, y: s.downMainY + 30)), aspect: s.blockAspect(bx, .west), scale: sig * 0.68)
        }
    }

    // MARK: controls / HUD

    /// A warning pill on the very track a fast train is bearing down, arrow pointing the way it's heading —
    /// clear that line before it arrives.
    private func expressWarning(eastbound: Bool, special: Bool = false) -> some View {
        HStack(spacing: 5) {
            if !eastbound { Image(systemName: "arrowtriangle.left.fill").font(.system(size: 11, weight: .black)) }
            Image(systemName: special ? "sparkles" : "bolt.fill").font(.system(size: 12, weight: .black))
            Text(special ? "Special" : "Fast train").font(.system(size: 13, weight: .heavy, design: .rounded))
            if eastbound { Image(systemName: "arrowtriangle.right.fill").font(.system(size: 11, weight: .black)) }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Color(red: 1.0, green: 0.82, blue: 0.24), in: Capsule())
        .overlay(Capsule().stroke(.black.opacity(0.35), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.5), radius: 5)
    }

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
            Button(action: { station.toggleStarter(.east); Sound.shared.play(.tap) }) {
                SignalHalo().frame(width: 60, height: 60).contentShape(Rectangle())
            }
                .buttonStyle(PressStyle())
                .position(project(CGPoint(x: station.platR + 34, y: station.upLoopY - 40), scale, size))
            Button(action: { station.toggleStarter(.west); Sound.shared.play(.tap) }) {
                SignalHalo().frame(width: 60, height: 60).contentShape(Rectangle())
            }
                .buttonStyle(PressStyle())
                .position(project(CGPoint(x: station.platL - 44, y: station.downLoopY + 18), scale, size))

            // Warnings pinned to the screen edges (so they stay visible while panning), on the correct main:
            // eastbound trains arrive from the left on the up main; westbound from the right on the down main.
            if station.expressNearUp {
                expressWarning(eastbound: true, special: station.steamNearUp)
                    .position(x: 112, y: project(CGPoint(x: 0, y: station.upMainY), scale, size).y - 36)
            }
            if station.expressNearDown {
                expressWarning(eastbound: false, special: station.steamNearDown)
                    .position(x: size.width - 112, y: project(CGPoint(x: 0, y: station.downMainY), scale, size).y + 36)
            }

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
                Text(station.name).font(.system(size: 27, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(station.def.county) \(station.def.flag)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.82))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 34).padding(.bottom, 26)
        }
    }
}

#Preview { DawlishView(def: allStations[1]) { } }
