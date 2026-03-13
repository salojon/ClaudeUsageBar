import SwiftUI

struct UsageRowView: View {
    let title: String
    let usage: UsagePeriod

    private var barColor: Color {
        let percent = usage.utilizationPercent
        if percent >= 90 {
            return .red
        } else if percent >= 70 {
            return .orange
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(.body, design: .default))
                Spacer()
                Text("\(usage.utilizationPercent)%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: geometry.size.width * CGFloat(min(usage.utilization, 100)) / 100, height: 8)
                }
            }
            .frame(height: 8)

            Text("Resets in \(usage.timeUntilReset)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
