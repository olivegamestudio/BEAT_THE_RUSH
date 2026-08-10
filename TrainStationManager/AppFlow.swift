import SwiftUI

// MARK: - Shared style

private let bg = LinearGradient(colors: [Color(red: 0.12, green: 0.15, blue: 0.21),
                                         Color(red: 0.06, green: 0.08, blue: 0.12)],
                                startPoint: .top, endPoint: .bottom)

/// A press feel that dips and brightens instead of fading to transparent. A Button already
/// cancels if you slide off before releasing, so this keeps that while never going see-through.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The tap affordance drawn over a signal — a soft disc and a bright ring, big enough to hit and
/// clearly a control. The red/green signal itself is painted on the board underneath.
struct SignalHalo: View {
    var body: some View {
        Circle().fill(.white.opacity(0.07))
            .overlay(Circle().stroke(.white.opacity(0.42), lineWidth: 2.5))
            .frame(width: 76, height: 76)
            .contentShape(Circle())
    }
}

/// A soft darkening toward the edges to draw the eye into the middle of the board.
struct Vignette: View {
    var strength: Double = 0.5
    var body: some View {
        GeometryReader { g in
            RadialGradient(colors: [.clear, .clear, .black.opacity(strength)],
                           center: .center,
                           startRadius: min(g.size.width, g.size.height) * 0.18,
                           endRadius: hypot(g.size.width, g.size.height) * 0.62)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// A round speaker toggle for muting the synthesised sound.
struct MuteButton: View {
    @State private var muted = Sound.shared.muted
    var body: some View {
        Button {
            Sound.shared.toggleMute(); muted = Sound.shared.muted
            if !muted { Sound.shared.play(.ui) }
        } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(white: 0.82))
                .frame(width: 36, height: 36)
                .background(Color(red: 0.16, green: 0.19, blue: 0.25).opacity(0.92), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14)))
        }
        .buttonStyle(PressStyle())
    }
}

/// A non-blocking coaching card along the bottom, tapped through step by step on first play.
struct TutorialCard: View {
    let text: String
    let isLast: Bool
    let onNext: () -> Void
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 22)).foregroundStyle(Color(red: 0.42, green: 0.86, blue: 0.56))
                Text(text)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Button(action: onNext) {
                    Text(isLast ? "Got it" : "Next")
                        .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color(red: 0.20, green: 0.55, blue: 0.34), in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
            .padding(16)
            .frame(maxWidth: 660)
            .background(Color(red: 0.13, green: 0.16, blue: 0.22).opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
            .padding(.bottom, 18)
        }
    }
}

/// A small confirm sheet, used before leaving a game in progress.
struct ConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 8) {
                Text(title).font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text(message).font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.72))
                HStack(spacing: 12) {
                    Button(action: onCancel) { pill("Stay", filled: false) }.buttonStyle(PressStyle())
                    Button(action: onConfirm) { pill(confirmTitle, filled: true) }.buttonStyle(PressStyle())
                }
                .padding(.top, 12)
            }
            .padding(28)
            .background(Color(red: 0.13, green: 0.16, blue: 0.22), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.1)))
        }
    }
    private func pill(_ t: String, filled: Bool) -> some View {
        Text(t).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            .frame(width: 130, height: 48)
            .background(filled ? Color(red: 0.70, green: 0.30, blue: 0.30) : Color(red: 0.24, green: 0.27, blue: 0.34),
                       in: RoundedRectangle(cornerRadius: 13))
    }
}

enum GameOutcome { case playing, won, lost }

/// The mood of the crowd on a platform, shown as a little speech bubble once they start waiting.
enum Mood {
    case happy, waiting, cross
    var emoji: String { switch self { case .happy: "🙂"; case .waiting: "😕"; case .cross: "😠" } }
    var shows: Bool { self != .happy }   // only pop a bubble once people are impatient
}

/// Which stations the player has unlocked, persisted across launches. Station 1 is always open;
/// clearing station N unlocks N+1.
enum Progress {
    private static let key = "btr.unlockedThrough"
    static var unlockedThrough: Int {
        get { max(1, UserDefaults.standard.integer(forKey: key)) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func isUnlocked(_ id: Int) -> Bool { id <= unlockedThrough }
    static func clear(_ id: Int) { if id + 1 > unlockedThrough { unlockedThrough = id + 1 } }

    /// Best star rating (0–3) earned at each station, kept as a personal best.
    static func stars(_ id: Int) -> Int { UserDefaults.standard.integer(forKey: "btr.stars.\(id)") }
    static func record(stars s: Int, at id: Int) {
        if s > stars(id) { UserDefaults.standard.set(s, forKey: "btr.stars.\(id)") }
    }
}

/// Stars earned from how comfortably a station was cleared — the closer a platform came to
/// overflowing at its worst, the fewer stars. 3 = kept it flowing, 1 = a white-knuckle finish.
func starsFor(peakFill f: Double) -> Int { f < 0.75 ? 3 : (f < 1.0 ? 2 : 1) }

func tierColour(_ t: Int) -> Color {
    switch t {
    case 1: return Color(red: 0.32, green: 0.78, blue: 0.48)
    case 2: return Color(red: 0.30, green: 0.64, blue: 0.90)
    case 3: return Color(red: 0.88, green: 0.74, blue: 0.30)
    case 4: return Color(red: 0.92, green: 0.56, blue: 0.28)
    default: return Color(red: 0.92, green: 0.36, blue: 0.40)
    }
}

// MARK: - Win / lose overlay

/// Shown over a station when it's cleared or overwhelmed. Both station types use it.
struct OutcomeOverlay: View {
    let won: Bool
    let carried: Int
    let goal: Int
    var stars: Int = 0
    let onRetry: () -> Void
    let onExit: () -> Void
    @State private var pop = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.64).ignoresSafeArea()
            if won {
                RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4).opacity(0.26), .clear],
                               center: .center, startRadius: 10, endRadius: 340)
                    .ignoresSafeArea()
                burst
            }
            VStack(spacing: 14) {
                if won {
                    HStack(spacing: 10) { star(48, stars >= 1); star(68, stars >= 2); star(48, stars >= 3) }
                        .shadow(color: Color(red: 1, green: 0.7, blue: 0.2).opacity(0.5), radius: 10)
                }
                Text(won ? "Station cleared!" : "Too busy!")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(won ? Color(red: 0.42, green: 0.9, blue: 0.6)
                                         : Color(red: 0.97, green: 0.5, blue: 0.5))
                Text("\(carried) people · goal \(goal)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.8))
                HStack(spacing: 12) {
                    if !won {
                        Button(action: onRetry) { label("Try Again", filled: false) }.buttonStyle(PressStyle())
                    }
                    Button(action: onExit) { label(won ? "Continue" : "Stations", filled: won) }
                        .buttonStyle(PressStyle())
                }
                .padding(.top, 6)
            }
            .padding(32)
            .background(Color(red: 0.13, green: 0.16, blue: 0.22), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.1)))
        }
        .onAppear { pop = true }
    }

    /// A rating star that springs up when the card appears — gold if earned, dim if not.
    private func star(_ size: CGFloat, _ earned: Bool) -> some View {
        Image(systemName: earned ? "star.fill" : "star").font(.system(size: size))
            .foregroundStyle(earned ? Color(red: 1.0, green: 0.82, blue: 0.28) : Color(white: 0.38))
            .scaleEffect(pop ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.05), value: pop)
    }

    /// A one-shot burst of little stars flying out from the centre.
    private var burst: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    let a = Double(i) / 16 * 2 * .pi
                    Image(systemName: "star.fill")
                        .font(.system(size: [10.0, 14, 18][i % 3]))
                        .foregroundStyle([Color.yellow,
                                          Color(red: 1, green: 0.6, blue: 0.3),
                                          Color(red: 0.5, green: 0.8, blue: 1)][i % 3])
                        .position(x: geo.size.width / 2 + CGFloat(cos(a)) * (pop ? 300 : 30),
                                  y: geo.size.height / 2 + CGFloat(sin(a)) * (pop ? 190 : 20))
                        .opacity(pop ? 0 : 0.95)
                        .animation(.easeOut(duration: 0.9).delay(0.05), value: pop)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func label(_ t: String, filled: Bool) -> some View {
        Text(t).font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(.white).frame(width: 150, height: 52)
            .background(filled ? Color(red: 0.20, green: 0.55, blue: 0.34)
                               : Color(red: 0.24, green: 0.27, blue: 0.34),
                        in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Root navigation

enum Screen {
    case menu
    case select
    case play(StationDef)
}

struct RootView: View {
    @State private var screen: Screen = .menu

    var body: some View {
        ZStack {
            switch screen {
            case .menu:
                MenuView(onPlay: { screen = .select })
            case .select:
                StationSelectView(onPick: { screen = .play($0) }, onBack: { screen = .menu })
            case .play(let def):
                switch def.kind {
                case .saltash: SaltashView(def: def, onExit: { screen = .select }).id(def.id)
                case .dawlish: DawlishView(def: def, onExit: { screen = .select }).id(def.id)
                case .ladder:  StationView(def: def, onExit: { screen = .select }).id(def.id)
                }
            }
        }
        .statusBarHidden()
    }
}

// MARK: - Main menu

/// A tangle of carriages weaving along crossing lines behind the menu — a junction throat.
final class MenuField: ObservableObject {
    struct Rake { var path: Int; var dist: CGFloat; var speed: CGFloat; var length: Int; var tint: Color }
    let W: CGFloat = 1000
    let H: CGFloat = 520
    struct Cloud { var x: CGFloat; var y: CGFloat; var size: CGFloat; var speed: CGFloat }
    struct Signal { var path: Int; var dist: CGFloat; var red: Bool; var clock: Double; var period: Double }
    let gap: CGFloat = 32
    let paths: [RoutePath]
    var rakes: [Rake]
    var signals: [Signal] = []
    var clouds: [Cloud] = [
        Cloud(x: 120, y: 110, size: 1.1, speed: 11), Cloud(x: 520, y: 80, size: 1.5, speed: 7),
        Cloud(x: 860, y: 200, size: 1.0, speed: 13), Cloud(x: 360, y: 320, size: 1.3, speed: 9),
        Cloud(x: 760, y: 430, size: 1.2, speed: 10), Cloud(x: 60, y: 420, size: 1.0, speed: 12),
    ]

    init() {
        // Straight running lines at assorted angles, some left→right, some right→left —
        // they cross like a junction throat, and trains on them read as trains, not worms.
        let segs: [(CGPoint, CGPoint)] = [
            (CGPoint(x: -320, y: 120), CGPoint(x: 1320, y: 205)),
            (CGPoint(x: 1320, y: 250), CGPoint(x: -320, y: 250)),
            (CGPoint(x: -320, y: 400), CGPoint(x: 1320, y: 320)),
            (CGPoint(x: 1320, y: 40),  CGPoint(x: -320, y: 520)),
            (CGPoint(x: -320, y: 520), CGPoint(x: 1320, y: 70)),
            (CGPoint(x: 1320, y: 300), CGPoint(x: -320, y: 470)),
            (CGPoint(x: -320, y: 470), CGPoint(x: 1320, y: 140)),
        ]
        paths = segs.map { RoutePath([$0.0, $0.1]) }

        var rk: [Rake] = []
        for (i, path) in paths.enumerated() {
            for j in 0..<2 {
                let len = 4 + (i * 3 + j * 2) % 5
                let tint = trainPalette[(i * 2 + j) % trainPalette.count]
                let speed = CGFloat(78 + (i * 17 + j * 41) % 74)
                let dist = path.total * CGFloat(j) / 2 + CGFloat(i) * 44
                rk.append(Rake(path: i, dist: dist, speed: speed, length: len, tint: tint))
            }
        }
        rakes = rk
        // one signal per line, part-way along, that the trains obey
        signals = paths.enumerated().map { i, p in
            Signal(path: i, dist: p.total * 0.6, red: i % 3 == 1,
                   clock: Double(i) * 0.6, period: 3.0 + Double(i % 3))
        }
    }

    func tick(_ dt: Double) {
        // signals cycle red/green on their own timers
        for i in signals.indices {
            signals[i].clock += dt
            if signals[i].clock > signals[i].period {
                signals[i].clock = 0
                signals[i].red.toggle()
            }
        }
        // clouds drift across and wrap
        for i in clouds.indices {
            clouds[i].x += clouds[i].speed * CGFloat(dt)
            if clouds[i].x > W + 240 { clouds[i].x = -240 }
        }
        // rakes advance, but stop short of a red signal ahead on their line
        for i in rakes.indices {
            let p = rakes[i].path
            let total = paths[p].total
            var d = rakes[i].dist + rakes[i].speed * CGFloat(dt)
            for s in signals where s.path == p && s.red {
                if rakes[i].dist <= s.dist && d > s.dist - gap { d = s.dist - gap }
            }
            if d > total { d -= total }        // wraps off-screen; rakes reappear from the far edge
            rakes[i].dist = d
        }
        objectWillChange.send()
    }
}

struct MenuView: View {
    let onPlay: () -> Void
    @StateObject private var field = MenuField()
    @State private var pulse = false
    private let tick = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    private let carUnit: CGFloat = 30
    private let carH: CGFloat = 19

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            Canvas { ctx, size in
                let scale = size.width / field.W
                func S(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale, y: p.y * scale) }
                // faint rails
                for path in field.paths {
                    var pp = Path()
                    for (i, pt) in path.pts.enumerated() { i == 0 ? pp.move(to: S(pt)) : pp.addLine(to: S(pt)) }
                    ctx.stroke(pp, with: .color(.white.opacity(0.055)),
                               style: .init(lineWidth: 11 * scale, lineCap: .round))
                }
                // weaving carriages
                for r in field.rakes {
                    let path = field.paths[r.path]
                    for c in 0..<r.length {
                        let d = r.dist - CGFloat(c) * carUnit
                        guard d > 0, d < path.total else { continue }
                        let s = path.sample(d)
                        drawCarriage(ctx, at: S(s.p), angle: s.angle, tint: r.tint,
                                     cw: carUnit - 4, ch: carH, scale: scale)
                    }
                }
                // signals the trains actually obey, at their positions on the lines
                for sig in field.signals {
                    let foot = field.paths[sig.path].sample(sig.dist).p
                    drawSignal(ctx, at: S(foot), red: sig.red, scale: scale)
                }
            }
            .ignoresSafeArea()

            // soft scrim so the title reads over the busy field
            RadialGradient(colors: [.black.opacity(0.62), .black.opacity(0)],
                           center: .center, startRadius: 8, endRadius: 400)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text("BEAT THE RUSH")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                Text("Route the trains. Clear the platforms.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.72))
                    .shadow(color: .black.opacity(0.6), radius: 6)
                    .padding(.bottom, 26)

                Button(action: { Sound.shared.play(.ui); onPlay() }) {
                    Text("Play")
                        .font(.system(size: 25, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 244, height: 64)
                        .background(
                            LinearGradient(colors: [Color(red: 0.28, green: 0.74, blue: 0.46),
                                                    Color(red: 0.16, green: 0.52, blue: 0.32)],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.3), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
                        .shadow(color: Color(red: 0.32, green: 0.88, blue: 0.52).opacity(pulse ? 0.85 : 0.3),
                                radius: pulse ? 26 : 12)
                }
                .buttonStyle(PressStyle())
                .scaleEffect(pulse ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true), value: pulse)
            }
        }
        .overlay(alignment: .topTrailing) { MuteButton().padding(16) }
        .onReceive(tick) { _ in field.tick(0.03) }
        .onAppear { pulse = true }
    }
}

// MARK: - Station select

struct StationSelectView: View {
    let onPick: (StationDef) -> Void
    let onBack: () -> Void

    private let cols = [GridItem(.adaptive(minimum: 168), spacing: 14)]

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(white: 0.8))
                            .frame(width: 36, height: 36)
                            .background(Color(red: 0.16, green: 0.19, blue: 0.25), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12)))
                    }
                    .buttonStyle(PressStyle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BEAT THE RUSH")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Pick your station")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.6))
                    }
                    Spacer()
                    Image(systemName: "tram.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.32, green: 0.82, blue: 0.5))
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)

                ScrollView {
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(allStations) { def in
                            StationCard(def: def, locked: !Progress.isUnlocked(def.id),
                                        onPick: { onPick(def) })
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

struct StationCard: View {
    let def: StationDef
    var locked: Bool = false
    let onPick: () -> Void
    @State private var swing = 0.0
    private var colour: Color { tierColour(def.tier) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(def.name)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text("\(def.county) \(def.flag)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if !locked {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { i in
                                let earned = Progress.stars(def.id) > i
                                Image(systemName: earned ? "star.fill" : "star")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(earned ? Color(red: 1.0, green: 0.82, blue: 0.28)
                                                            : Color(white: 0.3))
                            }
                        }
                    }
                    Spacer()
                    Text("\(def.platformCount) platforms")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(locked ? 0.5 : 1)

            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(red: 1.0, green: 0.85, blue: 0.42), Color(red: 0.82, green: 0.58, blue: 0.16)],
                        startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
                    .rotationEffect(.degrees(swing), anchor: .top)   // swings from its shackle
                    .offset(x: 11, y: -11)                           // sits on the corner edge
            }
        }
        .padding(14)
        .frame(height: 118, alignment: .topLeading)
        .background(Color(red: 0.16, green: 0.19, blue: 0.25), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke((locked ? Color.white.opacity(0.14) : colour.opacity(0.45)), lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            if locked {
                swing = 18
                withAnimation(.spring(response: 0.5, dampingFraction: 0.26)) { swing = 0 }
            } else { onPick() }
        }
    }
}
