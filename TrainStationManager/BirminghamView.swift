import SwiftUI

struct BirminghamView: View {
    @StateObject private var station: BirminghamStation
    let onExit: () -> Void
    init(def: StationDef, onExit: @escaping () -> Void) {
        _station = StateObject(wrappedValue: BirminghamStation(def))
        self.onExit = onExit
    }
    private let tick = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    @State private var confirmExit = false
    @State private var started = false

    private let worldW: CGFloat = 1500
    private let contentMinX: CGFloat = -840
    private let contentMaxX: CGFloat = 2280
    @State private var originX: CGFloat = -60
    @State private var dragStartX: CGFloat? = nil

    private let railSteel = Color(red: 0.42, green: 0.46, blue: 0.54)
    private let railSheen = Color(red: 0.80, green: 0.84, blue: 0.92)
    private let railEdge = Color(red: 0.09, green: 0.10, blue: 0.14)

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
                    drawPlatforms(ctx, sc, S)
                    for t in station.trains { drawTrain(ctx, t, sc, S) }
                    drawPeople(ctx, sc, S)
                    drawSignals(ctx, sc, S)
                    for sp in station.sparkles {
                        drawSparkleBurst(ctx, at: S(CGPoint(x: sp.x, y: sp.y)), age: sp.age, life: sparkleLife, scale: sc, toward: CGPoint(x: size.width * 0.07, y: size.height * 0.90))
                    }
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
                Vignette(strength: 0.5)
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

    private func drawScene(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize) {
        // Birmingham New Street sits under the city — a dim, roofed-over trainshed.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.16),
                                                         Color(red: 0.08, green: 0.08, blue: 0.10)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    private func railLine(_ ctx: GraphicsContext, _ pts: [CGPoint], _ sc: CGFloat, width: CGFloat = 11, _ S: (CGPoint) -> CGPoint) {
        var p = Path()
        for (i, pt) in pts.enumerated() { i == 0 ? p.move(to: S(pt)) : p.addLine(to: S(pt)) }
        ctx.stroke(p, with: .color(railEdge), style: .init(lineWidth: width * sc, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(railSteel), style: .init(lineWidth: (width - 5) * sc, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(railSheen.opacity(0.35)), style: .init(lineWidth: 1.6 * sc, lineCap: .round, lineJoin: .round))
    }

    private func drawRails(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        // One staircase each side, springing from a lane: the upper off lane 6, the lower off lane 7.
        for (mouthX, platX) in [(s.xWT, s.platL), (s.xET, s.platR)] {
            railLine(ctx, s.ladderPath(mouthX, platX, to: 0, startY: s.levelY(6)), sc, S)   // upper fan
            railLine(ctx, s.ladderPath(mouthX, platX, to: 13, startY: s.levelY(7)), sc, S)  // lower fan
        }
        // The twelve platform roads, each from its west tee across to its east tee.
        for p in 0..<s.platformCount {
            let lvl = s.platformLevel(p), y = s.platformY(p)
            railLine(ctx, [CGPoint(x: s.teeX(lvl, s.xWT, s.platL), y: y), CGPoint(x: s.teeX(lvl, s.xET, s.platR), y: y)], sc, S)
        }
        // The two central approach lanes carry on off-screen.
        for l in s.laneLevels {
            let y = s.levelY(l)
            railLine(ctx, [CGPoint(x: contentMinX, y: y), CGPoint(x: contentMaxX, y: y)], sc, S)
            let c = s.laneIsIn(l) ? Color(red: 0.34, green: 0.72, blue: 0.48) : Color(red: 0.80, green: 0.52, blue: 0.30)
            for px in [contentMinX + 70, contentMaxX - 70] {
                ctx.fill(Path(ellipseIn: CGRect(x: S(CGPoint(x: px, y: y)).x - 5 * sc,
                                                y: S(CGPoint(x: px, y: y)).y - 5 * sc, width: 10 * sc, height: 10 * sc)),
                         with: .color(c))
            }
        }
    }

    /// A starting signal at each end of every platform — red while a train is berthed there.
    private func drawSignals(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        for p in 0..<s.platformCount {
            let y = s.platformY(p)
            let red = s.occupied(p)
            drawSignal(ctx, at: S(CGPoint(x: s.platL - 20, y: y)), red: red, scale: sc * 0.85)
            drawSignal(ctx, at: S(CGPoint(x: s.platR + 20, y: y)), red: red, scale: sc * 0.85)
        }
    }

    private func drawPlatforms(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        // Each island is a raised deck between its two face roads.
        for k in 0..<s.islandCount {
            let cy = s.islandY(k)
            let rect = CGRect(x: S(CGPoint(x: s.platL + 4, y: 0)).x, y: S(CGPoint(x: 0, y: cy - 6)).y,
                              width: (s.platR - s.platL - 8) * sc, height: 12 * sc)
            var lip = ctx; lip.addFilter(.shadow(color: .black.opacity(0.5), radius: 5 * sc, y: 3 * sc))
            lip.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3 * sc), cornerRadius: 4 * sc),
                     with: .color(Color(red: 0.19, green: 0.20, blue: 0.24)))
            ctx.fill(Path(roundedRect: rect, cornerRadius: 4 * sc), with: .color(Color(red: 0.40, green: 0.42, blue: 0.48)))
        }
    }

    private func drawTrain(_ ctx: GraphicsContext, _ t: BirmTrain, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for c in 0..<t.spec.length {
            let d = t.dist - (CGFloat(c) + 0.5) * Track.carUnit
            guard d >= 0, d <= t.path.total else { continue }
            let smp = t.path.sample(d)
            drawCarriage(ctx, at: S(smp.p), angle: t.path.smoothAngle(d), tint: t.spec.tint,
                         cw: Track.carUnit - 8, ch: Track.carHeight - 6, scale: sc, seatsFilled: Int(t.load.rounded()) - c * 3)
        }
    }

    private func drawPeople(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        for i in 0..<s.platformCount {
            let n = min(Int(s.pax[i]), 8)
            let toIsland: CGFloat = (i % 2 == 0) ? 9 : -9        // even face above its island, odd below
            let y = s.platformY(i) + toIsland
            for k in 0..<max(n, 0) {
                let base = S(CGPoint(x: s.platL + 26 + CGFloat(k) * 13, y: y))
                let col = s.agitated(i) ? Color(red: 0.90, green: 0.36, blue: 0.32) : Color(red: 0.62, green: 0.72, blue: 0.92)
                ctx.fill(Path(ellipseIn: CGRect(x: base.x - 3 * sc, y: base.y - 6 * sc, width: 6 * sc, height: 9 * sc)), with: .color(col))
            }
            if s.mood(i).shows {
                drawMood(ctx, s.mood(i).emoji, at: S(CGPoint(x: s.platL + 14, y: s.platformY(i) + toIsland * 1.8)), scale: sc * 0.7)
            }
        }
    }

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        ZStack {
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
                Text("\(Int(station.carried))").font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.34, green: 0.86, blue: 0.5))
                Text("people").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.82))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 34).padding(.bottom, 26)

            VStack(alignment: .trailing, spacing: 2) {
                Text(station.name).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(station.def.county) \(station.def.flag)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.82))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.horizontal, 34).padding(.bottom, 26)
        }
    }
}

#Preview { BirminghamView(def: allStations[18]) { } }
