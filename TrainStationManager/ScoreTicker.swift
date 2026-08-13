import SwiftUI

/// The people-carried score as a **split-flap counter** — the digits flap forward like a station
/// board — with a little row of figures above that fills toward the goal as you carry more.
struct ScoreTicker: View {
    let count: Int
    let goal: Int
    var label: String = "people"

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(4)
                .foregroundStyle(Color(white: 0.62))
            FlapCounter(value: count, goal: goal, cellW: 30, color: Flap.ink)
        }
        .shadow(color: .black.opacity(0.8), radius: 6)
    }
}

/// A fixed-width split-flap number. The digit count is fixed to the goal's width (leading zeros, as a
/// real board shows), so it never changes size — that's what keeps the layout stable.
struct FlapCounter: View {
    let value: Int
    let goal: Int
    var cellW: CGFloat = 28
    var color: Color = Flap.ink

    private var width: Int { max(String(max(goal, 1)).count, 1) }
    private var text: String {
        let s = String(max(0, value))
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    var body: some View {
        HStack(spacing: 3) {
            let chars = Array(text)
            ForEach(0..<width, id: \.self) { i in
                FlapDigitCell(digit: chars[i].wholeNumberValue ?? 0, cellW: cellW, color: color)
            }
        }
    }
}

/// One digit that flaps forward (0→1→…→9→0) to its target when the value changes, using the same
/// leaf-fold drawing as the departure board.
private struct FlapDigitCell: View {
    let digit: Int
    let cellW: CGFloat
    let color: Color
    @State private var from = 0
    @State private var start = Date()
    @State private var animating = false
    private let stepDur = 0.06

    var body: some View {
        let cell = CGSize(width: cellW, height: cellW * 1.5)
        Group {
            if animating {
                TimelineView(.animation) { tl in canvas(cell, elapsed: tl.date.timeIntervalSince(start)) }
            } else {
                canvas(cell, elapsed: 9999)
            }
        }
        .frame(width: cell.width, height: cell.height)
        .onAppear { from = digit }
        .onChange(of: digit) { old, new in
            from = old; start = Date(); animating = true
            let steps = (new - old + 10) % 10
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps) * stepDur + 0.12) { animating = false }
        }
    }

    private func canvas(_ cell: CGSize, elapsed: Double) -> some View {
        Canvas { ctx, _ in
            let (a, b, p) = flapState(elapsed: elapsed)
            drawFlapCell(ctx, CGRect(origin: .zero, size: cell), a, b, p, ink: color)
        }
    }

    /// Step forward from `from` to `digit`, one flip per `stepDur`.
    private func flapState(elapsed: Double) -> (Character, Character, Double) {
        let steps = (digit - from + 10) % 10
        func ch(_ n: Int) -> Character { Character("\((n % 10 + 10) % 10)") }
        if steps == 0 { return (ch(digit), ch(digit), 0) }
        let stepsF = elapsed / stepDur
        let done = Int(floor(stepsF))
        if done >= steps { return (ch(digit), ch(digit), 0) }
        let cur = from + done
        return (ch(cur), ch(cur + 1), min(max(stepsF - Double(done), 0), 1))
    }
}
