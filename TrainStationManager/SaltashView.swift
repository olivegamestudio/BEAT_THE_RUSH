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

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Track.W
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.15, blue: 0.21),
                                        Color(red: 0.06, green: 0.08, blue: 0.12)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                Canvas { ctx, size in
                    let sc = size.width / Track.W
                    func S(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * sc, y: p.y * sc) }
                    drawRails(ctx, sc, S)
                    drawBridge(ctx, sc, S)
                    for t in station.trains { drawTrain(ctx, t, sc, S) }
                    drawPlatforms(ctx, sc, S)
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

    // MARK: the Royal Albert Bridge — two lenticular trusses over the single line

    private func drawBridge(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let y = s.yBridge
        let mid = (s.xBridgeW + s.xBridgeE) / 2
        let steel = Color(red: 0.62, green: 0.28, blue: 0.28)      // the bridge's oxide-red iron
        let steelHi = Color(red: 0.80, green: 0.42, blue: 0.40)
        for (x0, x1) in [(s.xBridgeW, mid), (mid, s.xBridgeE)] {
            let c = (x0 + x1) / 2
            // hangers first (behind the tube)
            for f in stride(from: 0.16, through: 0.84, by: 0.17) {
                let hx = x0 + (x1 - x0) * CGFloat(f)
                let arcY = y - 34 * (1 - pow((CGFloat(f) - 0.5) * 2, 2))   // parabolic top chord
                var h = Path(); h.move(to: S(CGPoint(x: hx, y: arcY))); h.addLine(to: S(CGPoint(x: hx, y: y - 6)))
                ctx.stroke(h, with: .color(steel.opacity(0.8)), style: .init(lineWidth: 2 * sc))
            }
            // the lenticular tube (top chord bowing up, tied to the deck)
            var lens = Path()
            lens.move(to: S(CGPoint(x: x0, y: y - 6)))
            lens.addQuadCurve(to: S(CGPoint(x: x1, y: y - 6)), control: S(CGPoint(x: c, y: y - 56)))
            lens.addQuadCurve(to: S(CGPoint(x: x0, y: y - 6)), control: S(CGPoint(x: c, y: y - 20)))
            ctx.fill(lens, with: .linearGradient(Gradient(colors: [steelHi, steel]),
                     startPoint: S(CGPoint(x: c, y: y - 56)), endPoint: S(CGPoint(x: c, y: y - 6))))
            ctx.stroke(lens, with: .color(.black.opacity(0.35)), style: .init(lineWidth: 1.5 * sc))
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

    private func project(_ p: CGPoint, scale: CGFloat, size: CGSize) -> CGPoint {
        let base = CGSize(width: Track.W * scale, height: Track.H * scale)
        return CGPoint(x: (size.width - base.width) / 2 + p.x * scale,
                       y: (size.height - base.height) / 2 + p.y * scale)
    }

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
            // bridge control — tap to give the bridge to a direction
            Button(action: station.toggleBridge) {
                HStack(spacing: 6) {
                    Image(systemName: station.bridgeDir == .east ? "arrow.right" : "arrow.left")
                        .font(.system(size: 18, weight: .black))
                    Text("Bridge").font(.system(size: 14, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color(red: 0.16, green: 0.19, blue: 0.25).opacity(0.95), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.18)))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            }
            .position(project(CGPoint(x: (station.xBridgeW + station.xBridgeE) / 2, y: station.yBridge - 76),
                              scale: scale, size: size))

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
