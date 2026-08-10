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

    private let designW: CGFloat = 1200
    private let railSteel = Color(red: 0.44, green: 0.48, blue: 0.56)
    private let railSheen = Color(red: 0.82, green: 0.86, blue: 0.94)
    private let railEdge = Color(red: 0.10, green: 0.11, blue: 0.15)

    private func project(_ p: CGPoint, _ sc: CGFloat, _ size: CGSize) -> CGPoint {
        let vOff = (size.height - Track.H * sc) / 2
        return CGPoint(x: p.x * sc, y: p.y * sc + vOff)
    }

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / designW
            ZStack {
                Canvas { ctx, size in
                    let sc = size.width / designW
                    func S(_ p: CGPoint) -> CGPoint { project(p, sc, size) }
                    drawScene(ctx, sc, size, S)
                    drawPlatforms(ctx, sc, S)
                    drawRails(ctx, sc, S)
                    for t in station.trains { drawTrain(ctx, t, sc, S) }
                    drawPeople(ctx, sc, S)
                    for sp in station.sparkles {
                        drawSparkleBurst(ctx, at: S(CGPoint(x: sp.x, y: sp.y)), age: sp.age, life: sparkleLife, scale: sc)
                    }
                    drawDunes(ctx, sc, size, S)         // sandy dunes at the ends, hiding off-view trains
                    drawSignals(ctx, sc, S)
                }
                .ignoresSafeArea()
                Vignette(strength: 0.45)
                controls(scale: scale, size: geo.size)

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
        .onReceive(tick) { _ in station.tick(0.03) }
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
        band(ctx, 0, w, 0, y(102), Color(red: 0.55, green: 0.72, blue: 0.90), Color(red: 0.72, green: 0.83, blue: 0.93))     // sky
        band(ctx, 0, w, y(90), y(108), Color(red: 0.40, green: 0.50, blue: 0.44), Color(red: 0.34, green: 0.44, blue: 0.40)) // far shore (Exmouth)
        band(ctx, 0, w, y(102), y(140), Color(red: 0.38, green: 0.56, blue: 0.62), Color(red: 0.32, green: 0.50, blue: 0.56)) // Exe estuary
        band(ctx, 0, w, y(140), y(196), Color(red: 0.84, green: 0.74, blue: 0.52), Color(red: 0.74, green: 0.63, blue: 0.42)) // sand dunes
        band(ctx, 0, w, y(196), y(348), Color(red: 0.82, green: 0.75, blue: 0.58), Color(red: 0.76, green: 0.68, blue: 0.52)) // sandy ground
        band(ctx, 0, w, y(348), y(394), Color(red: 0.90, green: 0.82, blue: 0.62), Color(red: 0.82, green: 0.73, blue: 0.53)) // beach
        band(ctx, 0, w, y(394), size.height, Color(red: 0.16, green: 0.44, blue: 0.60), Color(red: 0.10, green: 0.30, blue: 0.48)) // sea
        marram(ctx, y0: y(150), x0: 0, x1: w, sc: sc)          // grass on the dunes
        for k in 0..<4 {                                        // waves + estuary ripples
            let wy = y(406 + CGFloat(k) * 12)
            var wave = Path(); wave.move(to: CGPoint(x: 20, y: wy)); wave.addLine(to: CGPoint(x: w - 20, y: wy))
            ctx.stroke(wave, with: .color(.white.opacity(0.10)), style: .init(lineWidth: 2 * sc, lineCap: .round))
        }
        var rip = Path(); rip.move(to: CGPoint(x: 20, y: y(122))); rip.addLine(to: CGPoint(x: w - 20, y: y(122)))
        ctx.stroke(rip, with: .color(.white.opacity(0.08)), style: .init(lineWidth: 2 * sc, lineCap: .round))
    }

    /// A row of little marram-grass tufts along the dune top.
    private func marram(_ ctx: GraphicsContext, y0: CGFloat, x0: CGFloat, x1: CGFloat, sc: CGFloat) {
        let g = Color(red: 0.42, green: 0.52, blue: 0.28)
        var x = x0 + 12 * sc
        var seed = 3
        while x < x1 {
            seed = (seed * 7 + 13) % 1000        // bounded pseudo-random, never overflows
            let h = (10 + CGFloat(seed % 5) * 2) * sc
            var tuft = Path()
            for b in -2...2 {
                tuft.move(to: CGPoint(x: x, y: y0))
                tuft.addLine(to: CGPoint(x: x + CGFloat(b) * 2.4 * sc, y: y0 - h))
            }
            ctx.stroke(tuft, with: .color(g.opacity(0.8)), style: .init(lineWidth: 1.4 * sc, lineCap: .round))
            x += (18 + CGFloat(seed % 4) * 6) * sc
        }
    }

    /// Sandy dune mounds at each end that the line runs behind, hiding trains not yet in view.
    private func drawDunes(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize, _ S: (CGPoint) -> CGPoint) {
        let s = station
        for mouth in [s.tunL, s.tunR] {
            let toRight = mouth < designW / 2          // left dune slopes down to the right
            let base = S(CGPoint(x: mouth, y: 352))
            let crest = S(CGPoint(x: toRight ? 0 : designW, y: 150))
            var dune = Path()
            dune.move(to: CGPoint(x: crest.x, y: base.y))
            dune.addLine(to: CGPoint(x: crest.x, y: crest.y))
            dune.addQuadCurve(to: CGPoint(x: base.x, y: base.y),
                              control: CGPoint(x: (crest.x + base.x) / 2, y: crest.y + (base.y - crest.y) * 0.15))
            dune.closeSubpath()
            ctx.fill(dune, with: .linearGradient(
                Gradient(colors: [Color(red: 0.86, green: 0.76, blue: 0.54), Color(red: 0.72, green: 0.62, blue: 0.42)]),
                startPoint: CGPoint(x: crest.x, y: crest.y), endPoint: CGPoint(x: base.x, y: base.y)))
            marram(ctx, y0: S(CGPoint(x: 0, y: 160)).y,
                   x0: toRight ? 0 : mouth * sc, x1: toRight ? mouth * sc : size.width, sc: sc)
        }
    }

    private func drawPlatforms(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        drawPlatform(ctx, y: 214, occupied: s.pUp > 0, sc: sc, S: S)     // up platform, above the up line
        drawPlatform(ctx, y: 338, occupied: s.pDown > 0, sc: sc, S: S)   // down platform, below the down line
    }

    private func drawPlatform(_ ctx: GraphicsContext, y: CGFloat, occupied: Bool, sc: CGFloat, S: (CGPoint) -> CGPoint) {
        let s = station
        let rect = CGRect(x: S(CGPoint(x: s.platL - 30, y: 0)).x, y: S(CGPoint(x: 0, y: y)).y,
                          width: (s.platR - s.platL + 60) * sc, height: 20 * sc)
        let rr = Path(roundedRect: rect, cornerRadius: 8 * sc)
        ctx.fill(rr, with: .color(Color(red: 0.62, green: 0.63, blue: 0.67)))
        ctx.stroke(rr, with: .color(.white.opacity(0.25)), style: .init(lineWidth: 1.5 * sc))
    }

    private func drawRails(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        for ly in [s.upY, s.downY] {
            var p = Path(); p.move(to: S(CGPoint(x: 0, y: ly))); p.addLine(to: S(CGPoint(x: designW, y: ly)))
            ctx.stroke(p, with: .color(railEdge), style: .init(lineWidth: 16 * sc, lineCap: .round))
            ctx.stroke(p, with: .color(railSteel), style: .init(lineWidth: 10 * sc, lineCap: .round))
            ctx.stroke(p, with: .color(railSheen.opacity(0.5)), style: .init(lineWidth: 2.5 * sc, lineCap: .round))
        }
    }

    private func drawTrain(_ ctx: GraphicsContext, _ t: DawTrain, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for c in 0..<t.spec.length {
            let d = t.dist - (CGFloat(c) + 0.5) * Track.carUnit
            guard d >= 0 else { continue }
            let smp = t.path.sample(d)
            drawCarriage(ctx, at: S(smp.p), angle: t.path.smoothAngle(d), tint: t.spec.tint,
                         cw: Track.carUnit - 6, ch: Track.carHeight, scale: sc)
        }
    }

    private func drawPeople(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        pax(ctx, count: s.pUp, x0: s.platL - 6, feetY: 214 + 18, sc: sc, agitated: s.upAgitated, t: s.animT, S: S)
        pax(ctx, count: s.pDown, x0: s.platL - 6, feetY: 338 + 4, sc: sc, agitated: s.downAgitated, t: s.animT, S: S)
        if s.upMood.shows { drawMood(ctx, s.upMood.emoji, at: S(CGPoint(x: s.platL + 20, y: 200)), scale: sc) }
        if s.downMood.shows { drawMood(ctx, s.downMood.emoji, at: S(CGPoint(x: s.platL + 20, y: 326)), scale: sc) }
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
        let sig = sc * 1.9
        drawSignal(ctx, at: S(CGPoint(x: s.platR + 30, y: s.upY)), red: s.upHeld, scale: sig)    // up starter (east)
        drawSignal(ctx, at: S(CGPoint(x: s.platL - 30, y: s.downY)), red: s.downHeld, scale: sig) // down starter (west)
    }

    // MARK: controls / HUD

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
            Button(action: { station.toggle(.east); Sound.shared.play(.tap) }) { SignalHalo() }
                .buttonStyle(PressStyle())
                .position(project(CGPoint(x: station.platR + 30, y: station.upY - 22), scale, size))
            Button(action: { station.toggle(.west); Sound.shared.play(.tap) }) { SignalHalo() }
                .buttonStyle(PressStyle())
                .position(project(CGPoint(x: station.platL - 30, y: station.downY - 22), scale, size))

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
                Text(station.name).font(.system(size: 27, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(station.def.county) \(station.def.flag)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.82))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 22).padding(.bottom, 16)
        }
    }
}

#Preview { DawlishView(def: allStations[1]) { } }
