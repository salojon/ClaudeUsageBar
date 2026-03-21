import SwiftUI

struct ProgressBarView: View {
    let value: Double // 0.0 ... 1.0

    private var color: Color {
        if value > 0.8 { return .red }
        if value > 0.5 { return .orange }
        return .green
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                    .animation(.easeInOut(duration: 0.4), value: value)
            }
        }
        .frame(height: 7)
    }
}
