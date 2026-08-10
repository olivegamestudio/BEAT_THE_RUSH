import SwiftUI

struct StationView: View {
    @StateObject private var station: Station
    let onExit: () -> Void
    init(def: StationDef, onExit: @escaping () -> Void) {
        _station = StateObject(wrappedValue: Station(def))
        self.onExit = onExit
    }
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    private let tick = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    // Modern palette — steel rail on a deep slate ground
    private let railSteel = Color(red: 0.44, green: 0.48, blue: 0.56)
    private let railSheen = Color(red: 0.82, green: 0.86, blue: 0.94)
    private let railEdge = Color(red: 0.10, green: 0.11, blue: 0.15)
    private let inkLight = Color(white: 0.82)

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / Track.W        // fill the width; tracks run off the edges
            let z = min(max(zoom * pinch, 1), 3)

            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.15, blue: 0.21),
                                        Color(red: 0.06, green: 0.08, blue: 0.12)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                diagram(scale: scale)
                    .scaleEffect(z)
                    .offset(x: pan.width + drag.width, y: pan.height + drag.height)
                    .clipped()
                    .gesture(
                        MagnifyGesture()
                            .updating($pinch) { v, s, _ in s = v.magnification }
                            .onEnded { v in
                                zoom = min(max(zoom * v.magnification, 1), 3)
                                clampPan(scale: scale, size: geo.size)
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .updating($drag) { v, s, _ in s = v.translation }
                            .onEnded { v in
                                pan.width += v.translation.width
                                pan.height += v.translation.height
                                clampPan(scale: scale, size: geo.size)
                            }
                    )

                controls(scale: scale, zoom: z)

                if station.outcome != .playing {
                    OutcomeOverlay(won: station.outcome == .won,
                                   carried: Int(station.carried), goal: station.def.goal,
                                   onRetry: { station.reset() }, onExit: onExit)
                }
            }
        }
        .onReceive(tick) { _ in station.tick(0.03) }
        .statusBarHidden()
    }

    // MARK: - Diagram

    private func diagram(scale: CGFloat) -> some View {
        Canvas { ctx, _ in
            func S(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale, y: p.y * scale) }
            drawRails(ctx, scale: scale, S: S)
            for t in station.trains { drawTrain(ctx, t, scale: scale, S: S) }
            // Platforms sit in front of the carriages — trains berth behind the platform edge.
            drawPlatforms(ctx, scale: scale, S: S)
            drawSignals(ctx, scale: scale, S: S)
        }
        .frame(width: Track.W * scale, height: Track.H * scale)
    }

    private func rail(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint,
                      scale: CGFloat, S: (CGPoint) -> CGPoint) {
        var p = Path(); p.move(to: S(a)); p.addLine(to: S(b))
        ctx.stroke(p, with: .color(railEdge),
                   style: .init(lineWidth: 18 * scale, lineCap: .round))   // dark base
        ctx.stroke(p, with: .color(railSteel), style: .init(lineWidth: 12 * scale, lineCap: .round))
        ctx.stroke(p, with: .color(railSheen.opacity(0.5)),
                   style: .init(lineWidth: 3 * scale, lineCap: .round))    // metal sheen
    }

    /// The controls, shown as signals: a home signal at the throat (hold the incoming flow) and
    /// a starter at each platform's exit end (hold or release its train). Green shows what you set.
    private func drawSignals(_ ctx: GraphicsContext, scale: CGFloat, S: (CGPoint) -> CGPoint) {
        let L = station.layout
        drawSignal(ctx, at: S(L.ladderBottom), red: !station.entranceOpen, scale: scale * 1.3)
        for i in 0..<L.n {
            drawSignal(ctx, at: S(CGPoint(x: station.exitX(i), y: L.lineY[i])),
                       red: station.platformHeld[i], scale: scale * 1.3)
        }
    }

    private func drawRails(_ ctx: GraphicsContext, scale: CGFloat, S: (CGPoint) -> CGPoint) {
        let L = station.layout
        rail(ctx, L.entry, L.ladderBottom, scale: scale, S: S)      // approach
        rail(ctx, L.ladderBottom, L.ladderTop, scale: scale, S: S)  // throat ladder
        for i in 0..<L.n {                                          // running lines
            rail(ctx, L.junction(i), CGPoint(x: Track.rightExit, y: L.lineY[i]),
                 scale: scale, S: S)
        }
    }

    private func drawPlatforms(_ ctx: GraphicsContext, scale: CGFloat, S: (CGPoint) -> CGPoint) {
        let big = station.layout.n >= 7          // slimmer slabs when the lines are packed close
        let off: CGFloat = big ? 20 : 30
        let ph: CGFloat = big ? 18 : 24
        for i in 0..<station.layout.n {
            let y = station.layout.lineY[i]
            let len = CGFloat(station.platCars[i]) * Track.carUnit
            // The platform: a wide, rounded numbered slab, set clearly off its running line.
            let rect = CGRect(x: S(CGPoint(x: Track.platLeft, y: y)).x,
                              y: S(CGPoint(x: 0, y: y + off)).y,
                              width: len * scale, height: ph * scale)
            // A free platform gets a green lip so you can read at a glance where a train can go.
            let free = !station.occupied(i)
            let surface = Color(red: 0.34, green: 0.39, blue: 0.47)
            let side = Color(red: 0.18, green: 0.21, blue: 0.28)
            let edge = free ? Color(red: 0.42, green: 0.92, blue: 0.60).opacity(0.75)
                            : Color.white.opacity(0.28)
            let depth = (big ? 12 : 20) * scale
            let corner = 14 * scale
            let rr = Path(roundedRect: rect, cornerRadius: corner)
            // The bottom face: the same slab dropped straight down, so its lower band shows
            // as the platform's vertical edge — depth without any diagonal skew.
            let rrSide = Path(roundedRect: rect.offsetBy(dx: 0, dy: depth), cornerRadius: corner)
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.45), radius: 5 * scale, x: 0, y: 6 * scale))
                l.fill(rrSide, with: .color(side))
            }
            // top face, lit from above
            ctx.fill(rr, with: .color(surface))
            ctx.fill(rr, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.18), .clear]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
            // crisp top lip to separate the face from the deck
            ctx.stroke(rr, with: .color(edge), style: .init(lineWidth: 2 * scale))
            // number
            let n = Text("\(i + 1)").font(.system(size: 16 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(inkLight)
            ctx.draw(n, at: CGPoint(x: rect.minX + 18 * scale, y: rect.midY))

            drawPeople(ctx, count: station.passengers[i], in: rect, len: len, scale: scale)
        }
    }

    /// Little figures gathering along the platform edge — they grow until a train collects them.
    private func drawPeople(_ ctx: GraphicsContext, count: Double, in rect: CGRect,
                            len: CGFloat, scale: CGFloat) {
        let maxN = max(0, Int((len - 52) / 17))
        let n = min(Int(count), maxN)
        guard n > 0 else { return }
        let clothes: [Color] = [
            Color(red: 0.30, green: 0.55, blue: 0.85), Color(red: 0.86, green: 0.45, blue: 0.38),
            Color(red: 0.40, green: 0.70, blue: 0.52), Color(red: 0.78, green: 0.62, blue: 0.30),
            Color(red: 0.62, green: 0.46, blue: 0.78)]
        let skin = Color(red: 0.97, green: 0.83, blue: 0.70)
        for k in 0..<n {
            let px = rect.minX + (42 + CGFloat(k) * 17) * scale
            let feet = rect.minY + 10 * scale        // stand them on the platform, not lying on it
            let coat = clothes[k % clothes.count]
            // torso: wider at the shoulders, tapering down — reads as a body
            let bw = 12 * scale, bh = 15 * scale
            let top = feet - bh
            var torso = Path()
            torso.move(to: CGPoint(x: px - bw * 0.32, y: top + bw * 0.28))
            torso.addQuadCurve(to: CGPoint(x: px + bw * 0.32, y: top + bw * 0.28),
                               control: CGPoint(x: px, y: top - bw * 0.05))       // shoulders
            torso.addLine(to: CGPoint(x: px + bw * 0.42, y: feet))
            torso.addLine(to: CGPoint(x: px - bw * 0.42, y: feet))
            torso.closeSubpath()
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: .black.opacity(0.5), radius: 2.5 * scale, x: 0, y: 2.5 * scale))
                l.fill(torso, with: .color(coat))
            }
            // shading over the torso: lit top-left, shadow bottom-right
            ctx.fill(torso, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.3)]),
                startPoint: CGPoint(x: px - bw / 2, y: top), endPoint: CGPoint(x: px + bw / 2, y: feet)))
            // head
            let hd = 9 * scale
            let headRect = CGRect(x: px - hd / 2, y: top - hd * 0.72, width: hd, height: hd)
            ctx.fill(Path(ellipseIn: headRect), with: .color(skin))
            ctx.fill(Path(ellipseIn: headRect), with: .linearGradient(
                Gradient(colors: [.white.opacity(0.5), .clear, .black.opacity(0.22)]),
                startPoint: CGPoint(x: headRect.minX, y: headRect.minY),
                endPoint: CGPoint(x: headRect.maxX, y: headRect.maxY)))
        }
    }

    private func drawTrain(_ ctx: GraphicsContext, _ t: ActiveTrain,
                           scale: CGFloat, S: (CGPoint) -> CGPoint) {
        for c in 0..<t.spec.length {
            let d = t.dist - (CGFloat(c) + 0.5) * Track.carUnit
            guard d > -Track.carUnit else { continue }
            let s = t.path.sample(d)
            drawCarriage(ctx, at: S(s.p), angle: s.angle, tint: t.spec.tint,
                         cw: Track.carUnit - 6, ch: Track.carHeight, scale: scale)
        }
        // A train stuck too long raises a flag — a pulsing warning over its head.
        if t.blockedTime > station.jamAfter {
            let head = S(t.path.sample(t.dist).p)
            let c = CGPoint(x: head.x, y: head.y - 26 * scale)
            let r = 11 * scale
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(red: 0.95, green: 0.75, blue: 0.20).opacity(0.35)))
            let warn = Text(Image(systemName: "exclamationmark.triangle.fill"))
                .font(.system(size: 15 * scale, weight: .black))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.18))
            ctx.draw(warn, at: c)
        }
        // dwell ring while berthed
        if t.phase == .berthed {
            let head = S(t.path.sample(t.dist).p)
            let frac = t.dwell / station.dwellTime
            let d = 18 * scale
            let box = CGRect(x: head.x - d / 2, y: head.y - 22 * scale, width: d, height: d)
            ctx.stroke(Path(ellipseIn: box), with: .color(Color(white: 0.6)),
                       style: .init(lineWidth: 3 * scale))
            var arc = Path()
            arc.addArc(center: CGPoint(x: box.midX, y: box.midY), radius: d / 2,
                       startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * frac), clockwise: false)
            ctx.stroke(arc, with: .color(Color(red: 0.20, green: 0.55, blue: 0.25)),
                       style: .init(lineWidth: 3 * scale, lineCap: .round))
        }
    }

    /// Keep the pan within the diagram so you can't drag the board off into empty space.
    private func clampPan(scale: CGFloat, size: CGSize) {
        let maxX = max(0, (Track.W * scale * zoom - size.width) / 2)
        let maxY = max(0, (Track.H * scale * zoom - size.height) / 2)
        pan.width = min(max(pan.width, -maxX), maxX)
        pan.height = min(max(pan.height, -maxY), maxY)
    }

    // MARK: - Controls (signals as buttons) + HUD

    /// A tap target over a drawn signal — the light shows red/green; a faint ring hints it's a control.
    private func signalTap(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().stroke(.white.opacity(0.16), lineWidth: 2)
                .frame(width: 48, height: 48).contentShape(Circle())
        }
    }

    private func project(_ p: CGPoint, scale: CGFloat, z: CGFloat, in size: CGSize) -> CGPoint {
        let base = CGSize(width: Track.W * scale, height: Track.H * scale)
        let originX = (size.width - base.width) / 2
        let originY = (size.height - base.height) / 2
        let cx = base.width / 2, cy = base.height / 2
        let sx = p.x * scale, sy = p.y * scale
        return CGPoint(x: originX + cx + (sx - cx) * z + pan.width + drag.width,
                       y: originY + cy + (sy - cy) * z + pan.height + drag.height)
    }

    private func controls(scale: CGFloat, zoom z: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack {
                // Home signal at the throat — tap to hold or release the incoming flow.
                signalTap { station.toggleEntrance() }
                    .position(project(CGPoint(x: station.layout.ladderBottom.x,
                                              y: station.layout.ladderBottom.y - 14),
                                      scale: scale, z: z, in: geo.size))
                // A starter at each platform's exit — tap to hold a train or send it on its way.
                ForEach(0..<station.layout.n, id: \.self) { i in
                    signalTap { station.toggleStarter(i) }
                        .position(project(CGPoint(x: station.exitX(i), y: station.layout.lineY[i] - 14),
                                          scale: scale, z: z, in: geo.size))
                }

                // back — top left
                Button(action: onExit) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(white: 0.85))
                        .frame(width: 36, height: 36)
                        .background(Color(red: 0.16, green: 0.19, blue: 0.25).opacity(0.92), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.14)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)

                // score — bottom left, big
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(Int(station.carried))")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.34, green: 0.86, blue: 0.5))
                    Text("carried")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.72))
                }
                .shadow(color: .black.opacity(0.75), radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, 22).padding(.bottom, 14)

                // station name + county — bottom right
                VStack(alignment: .trailing, spacing: 2) {
                    Text(station.name)
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(station.def.county) \(station.def.flag)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.72))
                }
                .shadow(color: .black.opacity(0.75), radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.horizontal, 22).padding(.bottom, 16)
            }
        }
    }
}

#Preview { StationView(def: allStations[8]) { } }
