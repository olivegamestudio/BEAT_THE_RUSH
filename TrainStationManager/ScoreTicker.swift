import SwiftUI

/// The people-carried score as a rolling-digit ticker — the digits spin up like a station counter —
/// with a little row of figures above it that fills toward the goal as you carry more.
struct ScoreTicker: View {
    let count: Int
    let goal: Int
    var label: String = "people"
    private let green = Color(red: 0.34, green: 0.86, blue: 0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            crowd
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                RollingNumber(value: count, size: 46, color: green)
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

/// A number whose digits each roll vertically to their target, like a mechanical ticker.
struct RollingNumber: View {
    let value: Int
    var size: CGFloat = 46
    var color: Color = .green
    private var digits: [Int] { String(max(0, value)).compactMap(\.wholeNumberValue) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, d in
                RollingDigit(value: d, size: size, color: color)
            }
        }
    }
}

private struct RollingDigit: View {
    let value: Int
    let size: CGFloat
    let color: Color
    private var h: CGFloat { size * 1.16 }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { d in
                Text("\(d)")
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .frame(height: h)
            }
        }
        .offset(y: -CGFloat(value) * h)
        .frame(height: h, alignment: .top)
        .clipped()
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: value)
    }
}
