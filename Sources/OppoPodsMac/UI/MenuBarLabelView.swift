import SwiftUI
import OppoPodsCore

struct MenuBarLabelView: View {
    @EnvironmentObject private var session: EarbudsSession

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: session.connectionState == .connected ? "earbuds" : "earbuds.case")
            if let level = session.battery.menuBarLevel, session.connectionState == .connected {
                Text("\(level)%")
                    .monospacedDigit()
            }
        }
    }
}
