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

    // Saltash runs wider than a generic station: the single line reaches right out to the east
    // portal past the bridge. Frame the whole run — west exit to east entry — so both sides of
    // the bridge are on screen and you can see a westbound train coming before it's on you.
    private let boxMinX: CGFloat = -140
    private let boxMaxX: CGFloat = 1170
    private var designW: CGFloat { boxMaxX - boxMinX }

    /// Maps a design point into screen space: fit the wide run across the width, and centre the
    /// (shorter) content band vertically so it isn't stuck to the top.
    private func project(_ p: CGPoint, scale sc: CGFloat, size: CGSize) -> CGPoint {
        let vOff = (size.height - Track.H * sc) / 2
        return CGPoint(x: (p.x - boxMinX) * sc, y: p.y * sc + vOff)
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
                    drawRiver(ctx, sc, size, S)
                    drawRails(ctx, sc, S)
                    drawBridge(ctx, sc, S)
                    drawPlatforms(ctx, sc, S)
                    for t in station.trains { drawTrain(ctx, t, sc, S) }
                    drawSignals(ctx, sc, S)
                }
                .ignoresSafeArea()
                controls(scale: scale, size: geo.size)
            }
        }
        .onReceive(tick) { _ in station.tick(0.03) }
        .statusBarHidden()
    }

    // MARK: rails

    private func rail(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        var p = Path(); p.move(to: S(a)); p.addLine(to: S(b))
        ctx.stroke(p, with: .color(railEdge), style: .init(lineWidth: 18 * sc, lineCap: .round))
        ctx.stroke(p, with: .color(railSteel), style: .init(lineWidth: 12 * sc, lineCap: .round))
        ctx.stroke(p, with: .color(railSheen.opacity(0.5)), style: .init(lineWidth: 3 * sc, lineCap: .round))
    }

    private func drawRails(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        rail(ctx, CGPoint(x: s.exitW, y: s.yBot), CGPoint(x: s.xMerge, y: s.yBot), sc, S)   // eastbound line
        rail(ctx, CGPoint(x: s.xMerge, y: s.yTop), CGPoint(x: s.exitW, y: s.yTop), sc, S)    // westbound line
        rail(ctx, CGPoint(x: s.xMerge, y: s.yBot), CGPoint(x: s.xBridgeW, y: s.yBridge), sc, S) // converge
        rail(ctx, CGPoint(x: s.xMerge, y: s.yTop), CGPoint(x: s.xBridgeW, y: s.yBridge), sc, S)
        rail(ctx, CGPoint(x: s.xBridgeW, y: s.yBridge), CGPoint(x: s.exitE, y: s.yBridge), sc, S) // the bridge
    }

    // MARK: the River Tamar — a vertical band the bridge crosses

    private func drawRiver(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let rect = CGRect(x: S(CGPoint(x: s.riverL, y: 0)).x, y: 0,
                          width: (s.riverR - s.riverL) * sc, height: size.height)
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(red: 0.10, green: 0.26, blue: 0.42), Color(red: 0.07, green: 0.19, blue: 0.33)]),
            startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
        // ripples
        for k in 0..<9 {
            let ry = (30 + CGFloat(k) * 60) * sc
            var wave = Path(); wave.move(to: CGPoint(x: rect.minX + 10 * sc, y: ry))
            wave.addLine(to: CGPoint(x: rect.maxX - 10 * sc, y: ry))
            ctx.stroke(wave, with: .color(.white.opacity(0.05)), style: .init(lineWidth: 2 * sc, lineCap: .round))
        }
    }

    // MARK: the Royal Albert Bridge — twin bowstring arches over the single line

    private func drawBridge(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let y = s.yBridge
        let mid = (s.xBridgeW + s.xBridgeE) / 2
        let dark = Color(red: 0.34, green: 0.13, blue: 0.13)
        let red = Color(red: 0.68, green: 0.26, blue: 0.24)
        let redHi = Color(red: 0.88, green: 0.44, blue: 0.40)
        // piers down toward the water
        for px in [s.xBridgeW, mid, s.xBridgeE] {
            var pier = Path(); pier.move(to: S(CGPoint(x: px, y: y + 4))); pier.addLine(to: S(CGPoint(x: px, y: y + 40)))
            ctx.stroke(pier, with: .color(Color(white: 0.32)), style: .init(lineWidth: 6 * sc, lineCap: .round))
        }
        for (x0, x1) in [(s.xBridgeW, mid), (mid, s.xBridgeE)] {
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

    private func drawPlatforms(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        // top platform (above the westbound line), bottom platform (below the eastbound line)
        drawPlatform(ctx, top: true, y: s.yTop, pax: s.pTop, sc: sc, S: S)
        drawPlatform(ctx, top: false, y: s.yBot, pax: s.pBot, sc: sc, S: S)
    }

    private func drawPlatform(_ ctx: GraphicsContext, top: Bool, y: CGFloat, pax: Double,
                              sc: CGFloat, S: (CGPoint) -> CGPoint) {
        let s = station
        let h: CGFloat = 24, depth: CGFloat = 11
        let slabY = top ? y - 14 - h : y + 14
        let rect = CGRect(x: S(CGPoint(x: s.platL, y: 0)).x, y: S(CGPoint(x: 0, y: slabY)).y,
                          width: (s.platR - s.platL) * sc, height: h * sc)
        let rr = Path(roundedRect: rect, cornerRadius: 14 * sc)
        let side = Path(roundedRect: rect.offsetBy(dx: 0, dy: depth * sc), cornerRadius: 14 * sc)
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: .black.opacity(0.5), radius: 5 * sc, x: 0, y: 6 * sc))
            l.fill(side, with: .color(Color(red: 0.18, green: 0.21, blue: 0.28)))
        }
        ctx.fill(rr, with: .color(Color(red: 0.34, green: 0.39, blue: 0.47)))
        ctx.stroke(rr, with: .color(.white.opacity(0.22)), style: .init(lineWidth: 2 * sc))
        // passengers stand on the track-facing edge
        let feetY = top ? rect.maxY - 4 * sc : rect.minY + 4 * sc
        drawPax(ctx, count: pax, x0: rect.minX + 16 * sc, feetY: feetY, sc: sc)
    }

    private func drawPax(_ ctx: GraphicsContext, count: Double, x0: CGFloat, feetY: CGFloat, sc: CGFloat) {
        let clothes: [Color] = [Color(red: 0.30, green: 0.55, blue: 0.85), Color(red: 0.86, green: 0.45, blue: 0.38),
                                Color(red: 0.40, green: 0.70, blue: 0.52), Color(red: 0.78, green: 0.62, blue: 0.30),
                                Color(red: 0.62, green: 0.46, blue: 0.78)]
        let skin = Color(red: 0.97, green: 0.83, blue: 0.70)
        let n = min(Int(count), 12)
        for k in 0..<max(n, 0) {
            let px = x0 + CGFloat(k) * 15 * sc
            let coat = clothes[k % clothes.count]
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
        drawSignal(ctx, at: S(CGPoint(x: s.xBridgeW - 10, y: s.yBridge)), red: !s.portalGreen(.east), scale: sc)
        drawSignal(ctx, at: S(CGPoint(x: s.xBridgeE + 10, y: s.yBridge)), red: !s.portalGreen(.west), scale: sc)
    }

    private func drawTrain(_ ctx: GraphicsContext, _ t: SaltTrain, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for c in 0..<t.spec.length {
            let d = t.dist - (CGFloat(c) + 0.5) * Track.carUnit
            guard d > -Track.carUnit else { continue }
            let s = t.path.sample(d)
            drawCarriage(ctx, at: S(s.p), angle: s.angle, tint: t.spec.tint,
                         cw: Track.carUnit - 6, ch: Track.carHeight, scale: sc)
        }
    }

    // MARK: controls / HUD

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
            // The point before the bridge: throw it to connect the single line to the up
            // line or the down line — the chevron points at whichever line is set.
            Button(action: station.toggleBridge) {
                ZStack {
                    Circle().fill(.white)
                        .overlay(Circle().stroke(Color(red: 0.25, green: 0.6, blue: 1.0), lineWidth: 3))
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .frame(width: 30, height: 30)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(Color(red: 0.25, green: 0.6, blue: 1.0))
                        .offset(y: -22)
                }
                .rotationEffect(.degrees(station.bridgeDir == .east ? 180 : 0))  // down = bottom line, up = top
                .animation(.easeInOut(duration: 0.2), value: station.bridgeDir)
                .frame(width: 70, height: 70)
                .contentShape(Circle())
            }
            .position(project(CGPoint(x: station.xMerge + 26, y: station.yBridge), scale: scale, size: size))

            // back — top left
            Button(action: onExit) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Color(white: 0.85))
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.16, green: 0.19, blue: 0.25).opacity(0.92), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)

            // score bottom-left
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(Int(station.carried))")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.34, green: 0.86, blue: 0.5))
                Text("carried").font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.72))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 22).padding(.bottom, 14)

            // name bottom-right
            Text(station.name)
                .font(.system(size: 27, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.75), radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.horizontal, 22).padding(.bottom, 16)
        }
    }
}

#Preview { SaltashView(def: allStations[0]) { } }
