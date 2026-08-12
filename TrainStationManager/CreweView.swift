import SwiftUI

struct CreweView: View {
    @StateObject private var station: CreweStation
    let onExit: () -> Void
    init(def: StationDef, onExit: @escaping () -> Void) {
        _station = StateObject(wrappedValue: CreweStation(def))
        self.onExit = onExit
    }
    private let tick = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    @State private var confirmExit = false
    @State private var started = false

    private let worldW: CGFloat = 1050
    private let contentMinX: CGFloat = -760
    private let contentMaxX: CGFloat = 2360
    private let contentMinY: CGFloat = -84
    private let contentMaxY: CGFloat = 704
    @State private var originX: CGFloat = 300
    @State private var originY: CGFloat = 310
    @State private var dragStartX: CGFloat? = nil
    @State private var dragStartY: CGFloat? = nil
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat? = nil
    private let zoomMin: CGFloat = 0.55, zoomMax: CGFloat = 2.2
    private let railSteel = Color(red: 0.44, green: 0.48, blue: 0.56)
    private let railSheen = Color(red: 0.82, green: 0.86, blue: 0.94)
    private let railEdge = Color(red: 0.10, green: 0.11, blue: 0.15)
    private let fastCol = Color(red: 0.78, green: 0.40, blue: 0.36)
    private let singleCol = Color(red: 0.85, green: 0.66, blue: 0.24)

    private func project(_ p: CGPoint, _ sc: CGFloat, _ size: CGSize) -> CGPoint {
        return CGPoint(x: (p.x - originX) * sc, y: (p.y - originY) * sc + size.height / 2)
    }
    private func clampOrigin(_ x: CGFloat, _ visibleW: CGFloat) -> CGFloat {
        let hi = contentMaxX - visibleW
        if hi <= contentMinX { return (contentMinX + contentMaxX - visibleW) / 2 }   // world narrower than view — centre
        return min(max(x, contentMinX), hi)
    }
    private func clampOriginY(_ y: CGFloat, _ size: CGSize, _ sc: CGFloat) -> CGFloat {
        let half = (size.height / 2) / sc
        let lo = contentMinY + half, hi = contentMaxY - half
        if lo > hi { return (contentMinY + contentMaxY) / 2 }   // content shorter than the view — centre it
        return min(max(y, lo), hi)
    }

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / worldW * zoom
            ZStack {
                Canvas { ctx, size in
                    let sc = size.width / worldW * zoom
                    func S(_ p: CGPoint) -> CGPoint { project(p, sc, size) }
                    drawScene(ctx, sc, size)
                    drawRails(ctx, sc, S)
                    drawRouteLights(ctx, sc, S)
                    drawPlatforms(ctx, sc, S)
                    let ordered = station.trains.sorted { $0.path.sample($0.dist).p.y < $1.path.sample($1.dist).p.y }
                    for t in ordered { drawTrain(ctx, t, sc, S) }
                    for e in station.expresses { drawExpress(ctx, e, sc, S) }
                    drawPeople(ctx, sc, S)
                    for sp in station.sparkles {
                        drawSparkleBurst(ctx, at: S(CGPoint(x: sp.x, y: sp.y)), age: sp.age, life: sparkleLife, scale: sc,
                                         toward: CGPoint(x: size.width * 0.07, y: size.height * 0.90))
                    }
                    drawSignals(ctx, sc, S)
                    #if targetEnvironment(simulator)
                    drawDebugTags(ctx, sc, S)
                    #endif
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { v in
                            let sx = dragStartX ?? originX; dragStartX = sx
                            let sy = dragStartY ?? originY; dragStartY = sy
                            originX = clampOrigin(sx - v.translation.width / scale, worldW / zoom)
                            originY = clampOriginY(sy - v.translation.height / scale, geo.size, scale)
                        }
                        .onEnded { _ in dragStartX = nil; dragStartY = nil }
                        .simultaneously(with:
                            MagnificationGesture()
                                .onChanged { v in
                                    let z0 = zoomStart ?? zoom; zoomStart = z0
                                    zoom = min(zoomMax, max(zoomMin, z0 * v))
                                    let s = geo.size.width / worldW * zoom
                                    originX = clampOrigin(originX, worldW / zoom)
                                    originY = clampOriginY(originY, geo.size, s)
                                }
                                .onEnded { _ in zoomStart = nil }
                        )
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
        .onReceive(tick) { _ in if started { station.tick(0.03) } }
        .statusBarHidden()
    }

    // MARK: scene

    private func drawScene(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.30, green: 0.31, blue: 0.34),
                                                          Color(red: 0.23, green: 0.23, blue: 0.25)]),
                                       startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
    }

    // MARK: rails

    private func railLine(_ ctx: GraphicsContext, _ pts: [CGPoint], _ sc: CGFloat, _ S: (CGPoint) -> CGPoint,
                          width: CGFloat = 9, sheen: Color? = nil) {
        var p = Path()
        for (i, pt) in pts.enumerated() { i == 0 ? p.move(to: S(pt)) : p.addLine(to: S(pt)) }
        ctx.stroke(p, with: .color(railEdge), style: .init(lineWidth: (width + 6) * sc, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(sheen ?? railSteel), style: .init(lineWidth: width * sc, lineCap: .round, lineJoin: .round))
        if sheen == nil {
            ctx.stroke(p, with: .color(railSheen.opacity(0.5)), style: .init(lineWidth: width * 0.28 * sc, lineCap: .round, lineJoin: .round))
        }
    }

    /// A track at `y` running `xL…xR`, with a staggered staircase throat at whichever end connects out.
    private func drawTrack(_ ctx: GraphicsContext, y: CGFloat, xL: CGFloat, xR: CGFloat,
                           west: Bool, east: Bool, sc: CGFloat, _ S: (CGPoint) -> CGPoint,
                           width: CGFloat = 8, sheen: Color? = nil) {
        let s = station
        var pts: [CGPoint] = []
        if west { pts.append(contentsOf: s.westThroat(y).dropFirst()) }   // skip the run along the slow line
        pts.append(CGPoint(x: xL, y: y))
        pts.append(CGPoint(x: xR, y: y))
        if east { pts.append(contentsOf: s.eastThroat(y).dropLast()) }
        railLine(ctx, pts, sc, S, width: width, sheen: sheen)
    }

    private func buffer(_ ctx: GraphicsContext, at p: CGPoint, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let c = S(p)
        ctx.fill(Path(roundedRect: CGRect(x: c.x - 4 * sc, y: c.y - 9 * sc, width: 8 * sc, height: 18 * sc), cornerRadius: 2 * sc),
                 with: .color(Color(red: 0.80, green: 0.30, blue: 0.24)))
    }

    private func trackBundle(_ ctx: GraphicsContext, x0: CGFloat, x1: CGFloat, count: Int,
                             sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for k in 0..<count {
            let y = station.throatY - CGFloat(count - 1) * 8 + CGFloat(k) * 16
            let col: Color? = (count == 7 && (k == 3 || k == 4)) ? fastCol : nil    // the 2 fast lines in the east 7
            railLine(ctx, [CGPoint(x: x0, y: y), CGPoint(x: x1, y: y)], sc, S, width: 8, sheen: col)
        }
    }

    private func drawRails(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        // through lines (each drawn once by the platform that owns it; faces like 9/10/12 share it)
        for pl in s.plats where pl.through && pl.ownsLine {
            drawTrack(ctx, y: pl.y, xL: pl.xL, xR: pl.xR, west: true, east: true, sc: sc, S, width: 9)
        }
        // the slow lines the platforms gather onto in each throat (drawn only in the throats, clear of the
        // platform area) so the express pair between them stays visibly empty
        for ry in s.slowY {
            railLine(ctx, [CGPoint(x: s.xW, y: ry), CGPoint(x: s.xSL, y: ry)], sc, S, width: 8)
            railLine(ctx, [CGPoint(x: s.xSR, y: ry), CGPoint(x: s.xE, y: ry)], sc, S, width: 8)
        }
        // the two fast lines between 5 and 6 — expresses fly straight through, right out both ends
        for fy in s.fastY {
            railLine(ctx, [CGPoint(x: s.xW, y: fy), CGPoint(x: s.xE, y: fy)], sc, S, width: 8, sheen: fastCol)
        }
        // the single line, faced by 11 and 12
        drawTrack(ctx, y: s.singleY, xL: s.xSL, xR: s.xSR, west: true, east: true, sc: sc, S, width: 8, sheen: singleCol)

        // bays
        for pl in s.plats where pl.kind == .bayEast {   // open east, buffer at the west end
            drawTrack(ctx, y: pl.y, xL: pl.xL, xR: pl.xR, west: false, east: true, sc: sc, S, width: 8)
            buffer(ctx, at: CGPoint(x: pl.xL, y: pl.y), sc, S)
        }
        for pl in s.plats where pl.kind == .bayWest {   // open west, buffer at the east end
            drawTrack(ctx, y: pl.y, xL: pl.xL, xR: pl.xR, west: true, east: false, sc: sc, S, width: 8)
            buffer(ctx, at: CGPoint(x: pl.xR, y: pl.y), sc, S)
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

    // MARK: platforms + concourse

    private func slab(_ ctx: GraphicsContext, id: Int, xL: CGFloat, xR: CGFloat, top: CGFloat,
                      sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let rect = CGRect(x: S(CGPoint(x: xL, y: 0)).x, y: S(CGPoint(x: 0, y: top)).y,
                          width: (xR - xL) * sc, height: 15 * sc)
        let rr = Path(roundedRect: rect, cornerRadius: 6 * sc)
        let side = Path(roundedRect: rect.offsetBy(dx: 0, dy: 8 * sc), cornerRadius: 6 * sc)
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: .black.opacity(0.5), radius: 4 * sc, x: 0, y: 5 * sc))
            l.fill(side, with: .color(Color(red: 0.18, green: 0.21, blue: 0.28)))
        }
        ctx.fill(rr, with: .color(Color(red: 0.47, green: 0.48, blue: 0.53)))
        ctx.stroke(rr, with: .color(.white.opacity(0.20)), style: .init(lineWidth: 1.4 * sc))
        ctx.draw(Text("\(id)").font(.system(size: 10 * sc, weight: .heavy, design: .rounded)).foregroundColor(.white.opacity(0.9)),
                 at: CGPoint(x: S(CGPoint(x: xL, y: 0)).x + 14 * sc, y: rect.midY))
    }

    private func drawPlatforms(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        for pl in s.plats {
            // keep slabs clear of the rail so a berthed train sits beside the platform, not on it
            let top = pl.slabAbove ? pl.y - 42 : pl.y + 20
            slab(ctx, id: pl.id, xL: pl.sLeft, xR: pl.sRight, top: top, sc: sc, S)
        }
    }

    private func drawTrain(_ ctx: GraphicsContext, _ t: CreweTrain, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for c in 0..<t.spec.length {
            let d = t.dist - (CGFloat(c) + 0.5) * Track.carUnit
            guard d >= 0, d <= t.path.total else { continue }
            let smp = t.path.sample(d)
            drawCarriage(ctx, at: S(smp.p), angle: t.path.smoothAngle(d), tint: t.spec.tint,
                         cw: Track.carUnit - 6, ch: Track.carHeight, scale: sc,
                         fill: min(1, t.load / (Double(t.spec.length) * 3)), seed: t.id.hashValue &+ c)
        }
    }

    /// A fly-through express — a long silver rake with a smooth power car at each end, streaking down a
    /// fast line. A soft headlight glow at the nose sells the speed.
    private func drawExpress(_ ctx: GraphicsContext, _ e: CreweExpress, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let nose = e.path.sample(min(e.dist, e.path.total))
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 7 * sc))
            l.fill(Path(ellipseIn: CGRect(x: S(nose.p).x - 12 * sc, y: S(nose.p).y - 12 * sc, width: 24 * sc, height: 24 * sc)),
                   with: .color(Color(red: 1, green: 0.96, blue: 0.8).opacity(0.7)))
        }
        for c in 0..<e.spec.length {
            let d = e.dist - (CGFloat(c) + 0.5) * Track.carUnit
            guard d >= 0, d <= e.path.total else { continue }
            let smp = e.path.sample(d)
            let power = (c == 0 || c == e.spec.length - 1)   // a power car at each end
            drawCarriage(ctx, at: S(smp.p), angle: e.path.smoothAngle(d), tint: e.spec.tint,
                         cw: Track.carUnit - 3, ch: Track.carHeight - 2, scale: sc, endCap: power,
                         seed: e.id.hashValue &+ c)
        }
    }

    private func drawPeople(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        for (i, pl) in s.plats.enumerated() where s.throughIds.contains(pl.id) {
            let feetY = pl.slabAbove ? pl.y - 8 : pl.y + 30
            pax(ctx, count: s.passengers[i], x0: pl.xL + 90, feetY: feetY, sc: sc,
                agitated: s.agitated(i), t: s.animT, S: S)
            if s.mood(i).shows { drawMood(ctx, s.mood(i).emoji, at: S(CGPoint(x: pl.xL + 110, y: pl.y - 8)), scale: sc) }
        }
    }

    private func pax(_ ctx: GraphicsContext, count: Double, x0: CGFloat, feetY: CGFloat, sc: CGFloat,
                     agitated: Bool, t: Double, S: (CGPoint) -> CGPoint) {
        let clothes: [Color] = [Color(red: 0.30, green: 0.55, blue: 0.85), Color(red: 0.86, green: 0.45, blue: 0.38),
                                Color(red: 0.40, green: 0.70, blue: 0.52), Color(red: 0.78, green: 0.62, blue: 0.30)]
        let skin = Color(red: 0.97, green: 0.83, blue: 0.70)
        let n = min(Int(count), 12)
        for k in 0..<max(n, 0) {
            let pace = agitated ? CGFloat(sin(t * 2.0 + Double(k) * 1.7)) * 6 : 0
            let base = S(CGPoint(x: x0 + CGFloat(k) * 13 + pace, y: feetY))
            let px = base.x, feet = base.y
            let coat = agitated ? Color(red: 0.90, green: 0.36, blue: 0.32) : clothes[k % clothes.count]
            let bw = 10 * sc, bh = 12 * sc, top = feet - bh
            var torso = Path()
            torso.move(to: CGPoint(x: px - bw * 0.32, y: top + bw * 0.28))
            torso.addQuadCurve(to: CGPoint(x: px + bw * 0.32, y: top + bw * 0.28), control: CGPoint(x: px, y: top - bw * 0.05))
            torso.addLine(to: CGPoint(x: px + bw * 0.42, y: feet)); torso.addLine(to: CGPoint(x: px - bw * 0.42, y: feet))
            torso.closeSubpath()
            ctx.fill(torso, with: .color(coat))
            let hd = 7 * sc
            ctx.fill(Path(ellipseIn: CGRect(x: px - hd / 2, y: top - hd * 0.72, width: hd, height: hd)), with: .color(skin))
        }
    }

    private func drawSignals(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        // home signal at the east entrance — trains arrive from the east
        drawSignal(ctx, at: S(CGPoint(x: s.homeSignalX, y: station.throatY - 4)), red: !s.entranceOpen, scale: sc * 2.6)
        for (i, pl) in s.plats.enumerated() where s.throughIds.contains(pl.id) {
            // starter at the west (departure) end — red holds the boarded train
            drawSignal(ctx, at: S(CGPoint(x: pl.xL + 96, y: pl.y - 18)), red: s.platformHeld[i], scale: sc * 2.2)
            // entry signal at the east (arrival) end — red while the platform is occupied
            drawSignal(ctx, at: S(CGPoint(x: pl.xR - 70, y: pl.y - 18)), red: s.platformOccupied(i), scale: sc * 2.2)
            // point light out at the throat turnout, where this platform's road steps onto its slow line
            let turn = s.eastThroat(pl.y)
            if turn.count > 1 { drawSignal(ctx, at: S(CGPoint(x: turn[1].x, y: turn[1].y - 16)), red: s.platformOccupied(i), scale: sc * 1.9) }
        }
    }

    #if targetEnvironment(simulator)
    /// Simulator-only: label every signal with its id, right on the signal, plus its design coordinates so
    /// the layout can be nudged into place by name. Compiled out entirely for device builds.
    private func drawDebugTags(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        /// The id sits on the signal itself (big); the coordinates trail just past it (smaller).
        func tag(_ id: String, at sig: CGPoint, _ colour: Color) {
            let idText = Text(id).font(.system(size: 15 * sc, weight: .black, design: .rounded)).foregroundColor(colour)
            let posText = Text("\(Int(sig.x)),\(Int(sig.y))").font(.system(size: 9 * sc, weight: .bold, design: .monospaced)).foregroundColor(.white)
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black, radius: 2.4 * sc))
                l.draw(idText, at: S(sig)); l.draw(idText, at: S(sig))          // doubled: shadow reads as an outline
                l.draw(posText, at: S(CGPoint(x: sig.x, y: sig.y - 26)))
            }
        }
        tag("H", at: CGPoint(x: s.homeSignalX, y: s.throatY - 4), .cyan)
        for pl in s.plats where s.throughIds.contains(pl.id) {
            tag("S\(pl.id)", at: CGPoint(x: pl.xL + 96, y: pl.y - 18), .yellow)
            tag("E\(pl.id)", at: CGPoint(x: pl.xR - 70, y: pl.y - 18), .yellow)
            let turn = s.eastThroat(pl.y)
            if turn.count > 1 { tag("Pt\(pl.id)", at: CGPoint(x: turn[1].x, y: turn[1].y - 16), .orange) }
        }
    }
    #endif

    // MARK: controls / HUD

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
            Button(action: { station.toggleEntrance(); Sound.shared.play(.tap) }) {
                SignalHalo().frame(width: 60, height: 60).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .position(project(CGPoint(x: station.homeSignalX, y: station.throatY - 26), scale, size))

            ForEach(station.plats.indices.filter { station.throughIds.contains(station.plats[$0].id) }, id: \.self) { i in
                let pl = station.plats[i]
                Button(action: { station.toggleStarter(i); Sound.shared.play(.tap) }) {
                    SignalHalo().frame(width: 50, height: 50).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .position(project(CGPoint(x: pl.xL + 96, y: pl.y - 40), scale, size))
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

#Preview { CreweView(def: allStations[4]) { } }
