import SwiftUI

// MARK: - Shared style

private let bg = LinearGradient(colors: [Color(red: 0.12, green: 0.15, blue: 0.21),
                                         Color(red: 0.06, green: 0.08, blue: 0.12)],
                                startPoint: .top, endPoint: .bottom)

func tierColour(_ t: Int) -> Color {
    switch t {
    case 1: return Color(red: 0.32, green: 0.78, blue: 0.48)
    case 2: return Color(red: 0.30, green: 0.64, blue: 0.90)
    case 3: return Color(red: 0.88, green: 0.74, blue: 0.30)
    case 4: return Color(red: 0.92, green: 0.56, blue: 0.28)
    default: return Color(red: 0.92, green: 0.36, blue: 0.40)
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
                StationView(def: def, onExit: { screen = .select }).id(def.id)
            }
        }
        .statusBarHidden()
    }
}

// MARK: - Main menu

struct MenuView: View {
    let onPlay: () -> Void

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("BEAT THE RUSH")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                Text("Route the trains. Clear the platforms.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(white: 0.6))
                    .padding(.bottom, 26)

                Button(action: onPlay) {
                    Text("Play")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 220, height: 58)
                        .background(Color(red: 0.20, green: 0.55, blue: 0.34),
                                    in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.18)))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 5)
                }
            }
        }
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
                    Text("Choose a station")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)

                ScrollView {
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(allStations) { def in
                            StationCard(def: def)
                                .contentShape(RoundedRectangle(cornerRadius: 14))
                                .onTapGesture { onPick(def) }
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
    private var colour: Color { tierColour(def.tier) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(def.id)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(colour)
                Spacer()
                Text("Tier \(def.tier)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(colour, in: Capsule())
            }
            Text(def.name)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 2)
            HStack(spacing: 4) {
                ForEach(0..<def.platformCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(colour.opacity(0.85))
                        .frame(width: 14, height: 5)
                }
                Text("\(def.platformCount) platforms")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.leading, 4)
            }
        }
        .padding(14)
        .frame(height: 118, alignment: .topLeading)
        .background(Color(red: 0.16, green: 0.19, blue: 0.25), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(colour.opacity(0.4), lineWidth: 1.5))
    }
}
