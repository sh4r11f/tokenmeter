import SwiftUI
import TokenMeterCore

struct MenuBarLabelView: View {
    let label: CompactLabel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            Text(label.text)
        }
        .foregroundStyle(color)
        .opacity(label.isStale ? 0.5 : 1.0)
    }

    private var color: Color {
        switch label.level {
        case .normal: return .primary
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
}
