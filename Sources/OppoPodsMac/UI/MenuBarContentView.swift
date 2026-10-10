import AppKit
import SwiftUI
import OppoPodsCore

struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EarbudsSession
    @EnvironmentObject private var devices: BluetoothDeviceRepository
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "earbuds").font(.title)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enco Free4").font(.headline)
                    Text("普通版 · 仅绑定这一副耳机").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.refreshDevices(); session.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("刷新设备回报")
            }
            ConnectionSummaryView()
            Divider()
            BatteryStatusView(battery: session.battery).opacity(session.batteryIsStale ? 0.5 : 1)
            Text(session.batteryIsStale ? "电量数据已失效，等待耳机回报" : "电量由耳机回报 · “—”表示未知")
                .font(.caption).foregroundStyle(.secondary)
            SectionCard(title: "噪声控制", symbol: "waveform") { NoiseControlsView() }
            OperationResultView()
            if !session.isReady {
                if !devices.devices.isEmpty {
                    Picker("耳机", selection: $model.selectedDeviceAddress) {
                        Text("选择你的耳机").tag("")
                        ForEach(devices.devices) { Text($0.displayName).tag($0.id) }
                    }
                }
                if let message = model.connectionPrerequisiteMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Button("系统蓝牙", action: model.openBluetoothSettings)
                    Spacer()
                    Button("连接控制", action: model.connectSelectedDevice).buttonStyle(.borderedProminent)
                        .disabled(!model.selectedDeviceIsSystemConnected || session.connectionState == .connecting)
                }
            }
            Divider()
            HStack {
                Button("完整设置…") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
                Spacer()
                if session.isReady { Button("断开控制", action: model.disconnectControl) }
                Button("退出") { NSApp.terminate(nil) }
            }.buttonStyle(.borderless)
        }
        .padding(16).frame(width: 390)
        .onAppear { model.refreshDevices() }
    }
}

struct ConnectionSummaryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EarbudsSession
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(model.selectedDeviceIsSystemConnected ? "系统蓝牙已连接" : "系统蓝牙未连接", systemImage: model.selectedDeviceIsSystemConnected ? "checkmark.circle.fill" : "circle")
                Spacer()
                Text(session.isReady ? "控制已连接" : session.connectionState == .connecting ? "正在确认型号…" : "控制未连接")
                    .foregroundStyle(session.isReady ? Color.green : Color.secondary)
            }.font(.caption)
            if case .failed(let reason) = session.connectionState { Text(reason).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }
    }
}
struct NoiseControlsView: View {
    @EnvironmentObject private var session: EarbudsSession
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                mode("关闭", .off); mode("降噪", .noiseCancellation); mode("通透", .transparency)
                if session.capabilities.hasAdaptiveANC { mode("自适应", .adaptive) }
            }
            if session.noiseControl == nil { Text("等待耳机回报当前模式").font(.caption).foregroundStyle(.secondary) }
            if session.noiseControl == .noiseCancellation {
                Picker("降噪档位", selection: Binding<NoiseLevel?>(get: { session.noiseLevel }, set: { if let value = $0 { session.setNoiseLevel(value) } })) {
                    ForEach(NoiseLevel.allCases) { level in Text(level.name).tag(Optional(level)) }
                }.pickerStyle(.segmented)
                Text(session.noiseLevel.map { "耳机当前确认：" + $0.name + "降噪" } ?? "当前降噪档位尚未回报")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.disabled(!session.canWrite || session.noiseControl == nil)
    }
    private func mode(_ title: String, _ mode: NoiseControlMode) -> some View {
        Button { session.setNoiseControl(mode) } label: {
            HStack(spacing: 3) {
                if session.noiseControl == mode { Image(systemName: "checkmark").font(.caption2.bold()) }
                Text(title)
            }.frame(maxWidth: .infinity).padding(.vertical, 4)
        }.buttonStyle(.bordered).tint(session.noiseControl == mode ? .accentColor : .secondary)
    }
}
struct OperationResultView: View {
    @EnvironmentObject private var session: EarbudsSession
    var body: some View {
        if let pending = session.pendingAction {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("\(pending)，等待耳机确认…").font(.caption) }
        } else if let message = session.operationMessage {
            Label(message, systemImage: session.operationSucceeded ? "checkmark.circle" : "exclamationmark.circle")
                .font(.caption).foregroundStyle(session.operationSucceeded ? Color.green : Color.orange)
        }
    }
}
