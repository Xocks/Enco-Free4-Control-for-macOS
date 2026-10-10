import SwiftUI
import OppoPodsCore

struct BatteryStatusView: View {
    let battery: BatteryStatus

    var body: some View {
        HStack(spacing: 18) {
            BatteryItem(title: "左耳", symbol: "earbud.left", value: battery.left)
            BatteryItem(title: "右耳", symbol: "earbud.right", value: battery.right)
            BatteryItem(title: "充电盒", symbol: "airpodspro.chargingcase.wireless", value: battery.chargingCase)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BatteryItem: View {
    let title: String
    let symbol: String
    let value: BatteryLevel?

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(height: 24)
            HStack(spacing: 2) {
                Text(value.map { "\($0.level)%" } ?? "—")
                    .monospacedDigit()
                if value?.isCharging == true {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .font(.callout.weight(.medium))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
