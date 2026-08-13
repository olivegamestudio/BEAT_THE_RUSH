import SwiftUI

/// The people-carried score as a **split-flap counter** — the digits flap forward like a station
/// board — with a little row of figures above that fills toward the goal as you carry more.
struct ScoreTicker: View {
    let count: Int
    let goal: Int
    var label: String = "people"
    private let green = Color(red: 0.34, green: 0.86, blue: 0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            crowd
            HStack(alignment: .center, spacing: 9) {
                FlapCounter(value: count, goal: goal, cellW: 28, color: green)
                Text("/ \(goal) \(label)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(white: 0.72))
            }
        }
        .shadow(color: .black.opacity(0.8), radius: 6)
    }

    /// Ten little figures that light green in step with your progress to the goal.
    private var crowd: some View {
        let filled = goal > 0 ? min(10, Int((Double(count) / Double(goal) * 10).rounded(.down))) : 0
        return HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { i in
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(i < filled ? green : Color(white: 0.28))
            }
        }
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
