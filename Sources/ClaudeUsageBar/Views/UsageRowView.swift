import SwiftUI

struct UsageRowView: View {
    let title: String
    let subtitle: String
    let utilization: Double?
    let resetsAt: Date?

    private var color: Color {
        let v = utilization ?? 0
        if v > 80 { return .red }
        if v > 50 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout).fontWeight(.semibold)
                    Text(subtitle)
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                if let u = utilization {
                    Text("\(Int(u.rounded()))%")
                        .font(.system(.callout, design: .monospaced)).fontWeight(.bold)
                        .foregroundColor(color)
                } else {
                    Text("—").foregroundColor(.secondary)
                }
            }

            ProgressBarView(value: (utilization ?? 0) / 100)

            if let resetsAt {
                Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}
