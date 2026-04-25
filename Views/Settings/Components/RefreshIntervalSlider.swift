import SwiftUI

/// Slider for picking refresh interval in seconds (30…600 step 30) with live readout.
struct RefreshIntervalSlider: View {
    @Binding var seconds: Double

    private let minValue: Double = 30
    private let maxValue: Double = 600
    private let step: Double = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Slider(value: $seconds, in: minValue...maxValue, step: step)
                    .accessibilityValue(readout)
                Text(readout)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 140, alignment: .trailing)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: seconds)
                    .accessibilityHidden(true)
            }

            Text(String(localized: "settings.sync.refresh.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var readout: String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        if minutes == 0 {
            return String(format: String(localized: "settings.sync.refresh.everySec"), secs)
        }
        if secs == 0 {
            return String(format: String(localized: "settings.sync.refresh.everyMin"), minutes)
        }
        return String(format: String(localized: "settings.sync.refresh.everyMinSec"), minutes, secs)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var seconds: Double = 60
        var body: some View {
            RefreshIntervalSlider(seconds: $seconds)
                .frame(width: 420)
                .padding()
        }
    }
    return PreviewWrapper()
}
