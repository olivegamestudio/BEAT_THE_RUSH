import SwiftUI

struct LostwithielView: View {
    @StateObject private var station: LostwithielStation
    let onExit: () -> Void
    init(def: StationDef, onExit: @escaping () -> Void) {
        _station = StateObject(wrappedValue: LostwithielStation(def))
        self.onExit = onExit
    }
    private let tick = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    private let railSteel = Color(red: 0.44, green: 0.48, blue: 0.56)
    private let railSheen = Color(red: 0.82, green: 0.86, blue: 0.94)
    private let railEdge = Color(red: 0.10, green: 0.11, blue: 0.15)

    private let designW: CGFloat = 1200
    private let contentMinX: CGFloat = -360
    private let contentMaxX: CGFloat = 1560
    @State private var originX: CGFloat = 300
    @State private var dragStart: CGFloat? = nil
    @State private var confirmExit = false
    @State private var started = false
    @State private var paused = false

    private func clampOrigin(_ x: CGFloat) -> CGFloat { min(max(x, contentMinX), contentMaxX - designW) }
    private func project(_ p: CGPoint, scale sc: CGFloat, size: CGSize) -> CGPoint {
        let vOff = (size.height - Track.H * sc) / 2
        return CGPoint(x: (p.x - originX) * sc, y: p.y * sc + vOff)
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
                    drawTerrain(ctx, sc, size, S)
                    drawRails(ctx, sc, S)
                    drawRouteLights(ctx, sc, S)
                    let hauling = station.trains.contains { $0.role == .rescue && $0.hauling }
                    for t in station.trains where !t.finished {
                        if t.role == .freight && hauling { continue }   // drawn as the rescue's tail
                        drawTrain(ctx, t, sc, S)
                    }
                    drawSignals(ctx, sc, S)
                }
                .ignoresSafeArea()
                .gesture(DragGesture()
                    .onChanged { v in
                        let base = dragStart ?? originX
                        if dragStart == nil { dragStart = base }
                        originX = clampOrigin(base - v.translation.width / scale)
                    }
                    .onEnded { _ in dragStart = nil })
                Vignette(strength: 0.5)
                controls(scale: scale, size: geo.size)

                if !started && station.outcome == .playing {
                    LevelBriefing(def: station.def, onStart: { started = true }, onClose: onExit)
                }
                if station.outcome != .playing {
                    OutcomeOverlay(won: station.outcome == .won, def: station.def,
                                   carried: Int(station.carried), goal: station.def.goal,
                                   stars: station.stars, onRetry: { station.reset() }, onExit: onExit)
                }
                if confirmExit {
                    ConfirmDialog(title: "Leave Lostwithiel?", message: "You'll lose this go.",
                                  confirmTitle: "Leave", onConfirm: onExit, onCancel: { confirmExit = false })
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(tick) { _ in if started && !paused && !confirmExit { station.tick(0.03) } }
        .overlay { if paused { PausedOverlay { paused = false } } }
        .statusBarHidden()
    }

    // MARK: terrain

    private func drawTerrain(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize, _ S: (CGPoint) -> CGPoint) {
        let s = station
        let vOff = (size.height - Track.H * sc) / 2
        let horizon = (s.yTop - 40) * sc + vOff
        // Sky — bright, behind everything.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.47, green: 0.60, blue: 0.78),
                                                          Color(red: 0.78, green: 0.82, blue: 0.84)]),
                                       startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: horizon)))
        // Two parallax layers of china-clay spoil tips — far ones barely move, near ones move more.
        clayTips(ctx, sc, size, baseY: s.yTop - 52, amp: 52, factor: 0.20,
                 fill: Color(red: 0.52, green: 0.53, blue: 0.55), sheen: Color(red: 0.72, green: 0.73, blue: 0.74))
        clayTips(ctx, sc, size, baseY: s.yTop - 40, amp: 86, factor: 0.44,
                 fill: Color(red: 0.42, green: 0.41, blue: 0.38), sheen: Color(red: 0.60, green: 0.58, blue: 0.53))
        // Green valley floor (flat, foreground).
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)),
                 with: .color(Color(red: 0.14, green: 0.21, blue: 0.16)))
        // River Fowey below the lines — milky with clay.
        var river = Path()
        let ry = s.yBot + 150
        river.move(to: S(CGPoint(x: s.xW, y: ry))); var x = s.xW
        while x <= s.xE { river.addLine(to: S(CGPoint(x: x, y: ry + 12 * sin(x / 120)))); x += 40 }
        river.addLine(to: S(CGPoint(x: s.xE, y: size.height / sc)))
        river.addLine(to: S(CGPoint(x: s.xW, y: size.height / sc))); river.closeSubpath()
        ctx.fill(river, with: .color(Color(red: 0.13, green: 0.25, blue: 0.32)))
    }

    /// A ridge of pale conical clay tips at a parallax `factor` (0 = fixed, 1 = moves with the foreground),
    /// drawn well past the pannable range so its ends never come into view.
    private func clayTips(_ ctx: GraphicsContext, _ sc: CGFloat, _ size: CGSize,
                          baseY: CGFloat, amp: CGFloat, factor: CGFloat, fill: Color, sheen: Color) {
        let s = station
        let vOff = (size.height - Track.H * sc) / 2
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - originX * factor) * sc, y: y * sc + vOff) }
        var path = Path()
        let x0 = s.xW - 600, x1 = s.xE + 600
        path.move(to: P(x0, baseY)); var x = x0
        while x <= x1 {
            let cone = pow(max(0, sin(x / 95 + 0.6)), 6) * amp
            let ridge = 22 + 10 * sin(x / 230)
            path.addLine(to: P(x, baseY - ridge - cone)); x += 22
        }
        path.addLine(to: P(x1, baseY)); path.closeSubpath()
        ctx.fill(path, with: .color(fill))
        ctx.fill(path, with: .linearGradient(Gradient(colors: [sheen.opacity(0.6), .clear]),
                                             startPoint: P(x0, baseY - amp), endPoint: P(x0, baseY)))
    }

    // MARK: rails

    private func rail(_ ctx: GraphicsContext, _ pts: [CGPoint], _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        var p = Path()
        for (i, pt) in pts.enumerated() { i == 0 ? p.move(to: S(pt)) : p.addLine(to: S(pt)) }
        ctx.stroke(p, with: .color(railEdge), style: .init(lineWidth: 17 * sc, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(railSteel), style: .init(lineWidth: 11 * sc, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(railSheen.opacity(0.5)), style: .init(lineWidth: 3 * sc, lineCap: .round, lineJoin: .round))
    }

    private func drawRails(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        rail(ctx, [CGPoint(x: s.xW, y: s.yTop), CGPoint(x: s.xE, y: s.yTop)], sc, S)   // up lane
        rail(ctx, [CGPoint(x: s.xW, y: s.yBot), CGPoint(x: s.xE, y: s.yBot)], sc, S)   // down lane
        // Crossovers between the lanes.
        rail(ctx, [CGPoint(x: s.xCW, y: s.yTop), CGPoint(x: s.xCW + s.xOff, y: s.yBot)], sc, S)
        rail(ctx, [CGPoint(x: s.xCE - s.xOff, y: s.yBot), CGPoint(x: s.xCE, y: s.yTop)], sc, S)
        // The St Blazey line trails off the up lane to the east — the rescue comes from it, and the
        // casualty is dragged back off along it.
        rail(ctx, [CGPoint(x: s.xSideTurn, y: s.yTop), s.blazeTurn, s.stBlazey], sc, S)
    }

    private func buffer(_ ctx: GraphicsContext, _ p: CGPoint, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        var b = Path()
        b.move(to: S(CGPoint(x: p.x + 8, y: p.y - 12))); b.addLine(to: S(CGPoint(x: p.x + 8, y: p.y + 12)))
        ctx.stroke(b, with: .color(Color(red: 0.5, green: 0.3, blue: 0.2)), style: .init(lineWidth: 5 * sc, lineCap: .round))
    }

    private func drawRouteLights(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        for t in station.trains where !t.finished && !t.dead && t.role == .service {
            let start = max(0, t.dist)
            let end = min(t.path.total, t.dist + Track.carUnit * 6)
            if end <= start + 1 { continue }
            var pts: [CGPoint] = []; var d = start
            while d <= end { pts.append(S(t.path.sample(d).p)); d += 9 }
            drawRouteAhead(ctx, pts, aspect: t.railAspect, scale: sc)
        }
    }

    // MARK: trains

    private func drawTrain(_ ctx: GraphicsContext, _ t: LwTrain, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        switch t.role {
        case .freight:
            // A regular diesel loco at the head (east end), then ten short clay hoods trailing west.
            let locoCW = Track.carUnit * 0.92, locoCH = Track.carHeight
            let engD = t.dist - locoCW * 0.5
            let ep = t.path.sample(max(0, engD))
            let diesel = Color(red: 0.30, green: 0.33, blue: 0.38)     // clay-line diesel, not steam
            drawCarriage(ctx, at: S(ep.p), angle: t.path.smoothAngle(max(0, engD)), tint: diesel,
                         cw: locoCW, ch: locoCH, scale: sc, endCap: true)
            for c in 0..<s.freightWagons {
                let d = t.dist - locoCW - (CGFloat(c) + 0.5) * s.wagonUnit
                guard d >= 0 else { continue }
                let smp = t.path.sample(d)
                drawCarriage(ctx, at: S(smp.p), angle: t.path.smoothAngle(d), tint: t.spec.tint,
                             cw: s.wagonUnit - 4, ch: Track.carHeight * 0.86, scale: sc,
                             fill: 0, seed: t.id.hashValue &+ c, cornerRadius: Track.carHeight * 0.12, windows: false)   // clay hoods: no windows
            }
            // Smoke only once it's failed — the stricken engine vents until it's dragged clear.
            if t.dead {
                let base = S(ep.p)
                let chim = CGPoint(x: base.x, y: base.y - 0.52 * locoCH * sc)
                drawSteamPlume(ctx, at: chim, back: 0, t: s.animT, scale: sc, rate: t.smokeRate)   // stationary — rises straight up
            }
            if t.dead {
                drawMood(ctx, "⚠️", at: S(CGPoint(x: t.path.sample(t.dist).p.x, y: s.yTop - 40)), scale: sc)
            }
        case .rescue:
            // The rescue loco at the head.
            let loD = max(0, t.dist - Track.carUnit * 0.5)
            drawCarriage(ctx, at: S(t.path.sample(loD).p), angle: t.path.smoothAngle(loD),
                         tint: t.spec.tint, cw: Track.carUnit - 4, ch: Track.carHeight, scale: sc, endCap: true)
            if t.hauling, let f = t.casualty {
                // The coupled diesel (still venting until it's clear) and its clay hoods, trailing behind.
                let diesel = Color(red: 0.30, green: 0.33, blue: 0.38)
                let locoCW = Track.carUnit * 0.92, locoCH = Track.carHeight
                let engD = t.dist - Track.carUnit * 1.15
                if engD >= 0 {
                    let ep = t.path.sample(engD)
                    drawCarriage(ctx, at: S(ep.p), angle: t.path.smoothAngle(engD), tint: diesel,
                                 cw: locoCW, ch: locoCH, scale: sc, endCap: true)
                    let base = S(ep.p)
                    drawSteamPlume(ctx, at: CGPoint(x: base.x + 0.30 * locoCW * sc, y: base.y - 0.52 * locoCH * sc),
                                   back: -1, t: s.animT, scale: sc, rate: f.smokeRate)
                }
                let tail = t.dist - Track.carUnit * 1.15 - locoCW
                for c in 0..<s.freightWagons {
                    let d = tail - (CGFloat(c) + 0.5) * s.wagonUnit
                    guard d >= 0 else { continue }
                    let smp = t.path.sample(d)
                    drawCarriage(ctx, at: S(smp.p), angle: t.path.smoothAngle(d), tint: f.spec.tint,
                                 cw: s.wagonUnit - 4, ch: Track.carHeight * 0.86, scale: sc,
                                 fill: 0, seed: f.id.hashValue &+ c, cornerRadius: Track.carHeight * 0.12, windows: false)
                }
            }
        case .service:
            for c in 0..<t.spec.length {
                let d = t.dist - (CGFloat(c) + 0.5) * Track.carUnit
                guard d >= 0 else { continue }
                let smp = t.path.sample(d)
                drawCarriage(ctx, at: S(smp.p), angle: t.path.smoothAngle(d), tint: t.spec.tint,
                             cw: Track.carUnit - 6, ch: Track.carHeight, scale: sc, seed: t.id.hashValue &+ c)
            }
            if t.stopped > 3.5 {
                let prog = CGFloat((t.stopped - 3.5).truncatingRemainder(dividingBy: 2.4) / 2.4)
                var g = ctx; g.opacity = Double(1 - prog)
                let head = t.path.sample(t.dist).p
                drawMood(g, "😴", at: S(CGPoint(x: head.x, y: head.y - 28 - prog * 26)), scale: sc)
            }
        }
    }

    // MARK: signals

    private func drawSignals(_ ctx: GraphicsContext, _ sc: CGFloat, _ S: (CGPoint) -> CGPoint) {
        let s = station
        // Up-line signal by the top lane at the west crossover; down-line signal by the bottom lane at the
        // east crossover — always on the board, red = held.
        drawSignal(ctx, at: S(CGPoint(x: s.xCW, y: s.yTop)), red: !s.granted(.east), scale: sc * 2.2)
        drawSignal(ctx, at: S(CGPoint(x: s.xCE, y: s.yBot + 44)), red: !s.granted(.west), scale: sc * 2.2)
        if s.rescueReady {
            drawSignal(ctx, at: S(CGPoint(x: s.xSideTurn + 20, y: s.yTop)), red: false, scale: sc * 2.2)
        }
        // Automatic filter signals along the two approaches — they space the arrivals.
        for sx in s.blockXsUp {
            drawBlockSignal(ctx, at: S(CGPoint(x: sx, y: s.yTop - 26)), aspect: s.blockAspect(sx, .east), scale: sc * 1.7)
        }
        for sx in s.blockXsDown {
            drawBlockSignal(ctx, at: S(CGPoint(x: sx, y: s.yBot + 26)), aspect: s.blockAspect(sx, .west), scale: sc * 1.7)
        }
    }

    // MARK: controls

    private func signalButton(_ action: @escaping () -> Void, foot: CGPoint, scale: CGFloat, size: CGSize) -> some View {
        Button(action: { action(); Sound.shared.play(.tap) }) { SignalHalo() }
            .buttonStyle(PressStyle())
            .position(project(CGPoint(x: foot.x, y: foot.y - 40), scale: scale, size: size))
    }

    private func controls(scale: CGFloat, size: CGSize) -> some View {
        let s = station
        return ZStack {
            signalButton({ s.clear(.east) }, foot: CGPoint(x: s.xCW, y: s.yTop), scale: scale, size: size)
            signalButton({ s.clear(.west) }, foot: CGPoint(x: s.xCE, y: s.yBot + 44), scale: scale, size: size)
            if s.rescueReady {
                signalButton({ s.releaseRescue() }, foot: CGPoint(x: s.xSideTurn + 20, y: s.yTop), scale: scale, size: size)
            }

            Button(action: { Sound.shared.play(.ui); confirmExit = true }) {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).foregroundStyle(Color(white: 0.85))
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.82, green: 0.24, blue: 0.24).opacity(0.94), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14)))
            }
            .buttonStyle(PressStyle()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(28)

            HStack(spacing: 10) { PauseButton(paused: $paused); HapticsButton(); MuteButton() }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(28)

            ScoreTicker(count: Int(s.carried), goal: s.def.goal, label: "trains")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(.horizontal, 34).padding(.bottom, 26)

            VStack(alignment: .trailing, spacing: 2) {
                Text(s.name).font(.system(size: 27, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("\(s.def.county) \(s.def.flag)").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Color(white: 0.72))
            }
            .shadow(color: .black.opacity(0.75), radius: 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.horizontal, 34).padding(.bottom, 26)
        }
    }
}

#Preview { LostwithielView(def: allStations[5]) { } }
