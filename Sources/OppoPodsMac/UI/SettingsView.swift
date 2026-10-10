import AppKit
import SwiftUI
import OppoPodsCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: EarbudsSession
    @EnvironmentObject private var devices: BluetoothDeviceRepository
    @State private var showEQ = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Enco Free4 控制").font(.title2.bold())
                        Text("普通版 · 型号 \(session.productID ?? "待确认") · 固件 \(session.firmware)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("刷新") { model.refreshDevices(); session.refresh() }.disabled(session.pendingAction != nil)
                    if session.isReady { Button("断开控制", action: model.disconnectControl) }
                    else { Button("连接控制", action: model.connectSelectedDevice).disabled(!model.selectedDeviceIsSystemConnected || session.connectionState == .connecting) }
                }
                ConnectionSummaryView()
                OperationResultView()
            }.padding(20)
            Divider()
            TabView {
                sound.tabItem { Label("声音与设备", systemImage: "waveform") }
                GesturesView().tabItem { Label("耳机手势", systemImage: "hand.tap") }
                personalization.tabItem { Label("个性化", systemImage: "ear") }
                general.tabItem { Label("应用设置", systemImage: "gearshape") }
                progress.tabItem { Label("功能状态", systemImage: "checklist") }
            }.padding(12)
        }
        .frame(minWidth: 700, minHeight: 660)
        .sheet(isPresented: $showEQ) { CustomEqualizerEditorView(session: session) }
        .onAppear { NSApp.activate(ignoringOtherApps: true); model.refreshDevices(); model.refreshLoginState() }
    }
    private var sound: some View {
        Form {
            Section("电量") {
                BatteryStatusView(battery: session.battery).padding(.vertical, 8).opacity(session.batteryIsStale ? 0.5 : 1)
                Text(session.batteryIsStale ? "上次数据已失效，连接后刷新。" : "充电图标表示正在充电；未知信息显示为“—”。").font(.caption).foregroundStyle(.secondary)
            }
            Section("噪声控制") { NoiseControlsView() }
            Section("音效") {
                Picker("设备音效", selection: Binding<Int?>(get: { session.selectedEQ }, set: { if let value = $0 { session.setEQ(value) } })) {
                    Text("等待回报").tag(Int?.none)
                    ForEach(session.equalizerPresets) { Text($0.name).tag(Optional($0.id)) }
                }.disabled(!session.canWrite || session.selectedEQ == nil || !session.supports(0x0406))
                Button("自定义均衡器…") { showEQ = true }.disabled(!session.isReady || !session.eqListRead || !session.supports(0x0418))
            }
            Section("设备设置") {
                featureToggle("佩戴检测", 4)
                featureToggle("双设备连接", 0x11)
                if session.hosts.isEmpty { Text("尚未取得已连接设备列表").foregroundStyle(.secondary) }
                ForEach(session.hosts) { host in
                    LabeledContent(host.name.isEmpty ? "未命名设备" : host.name, value: (host.thisMac ? "这台 Mac · " : "") + (host.connected ? "已连接" : "未连接") + (host.playing ? " · 播放中" : ""))
                }
                LabeledContent("设备回报的音频编码", value: session.codec)
                Text("实际可用编码由 macOS 与耳机协商。耳机端空间音效在“个性化”中设置。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    @ViewBuilder private func featureToggle(_ title: String, _ id: UInt8) -> some View {
        if let value = session.feature(id) {
            Toggle(title, isOn: Binding(get: { value }, set: { session.setFeature(id, enabled: $0) }))
                .disabled(!session.canWrite || !session.supports(0x0403))
        } else { LabeledContent(title, value: "等待设备回报") }
    }
    private var personalization: some View {
        Form {
            Section("读取当前方案") {
                Text("先读取耳机已经保存的方案。完整听感测试和耳道扫描仍需实机校准，暂不开放测试音及方案写入。")
                Button("读取当前个性化数据") { session.readPersonalization() }.disabled(!session.isReady || session.pendingAction != nil)
                LabeledContent("黄金听感", value: session.goldenSummary)
                LabeledContent("耳道扫描", value: session.scanSummary)
            }
            Section("提示音内容与音色") {
                if session.tonesRead {
                    if session.earTones.isEmpty { Text("耳机未返回已安装的提示音方案") }
                    ForEach(session.earTones) { tone in
                        LabeledContent(tone.name.isEmpty ? (tone.id == 1 ? "系统默认" : "提示音方案 \(tone.id)") : tone.name, value: tone.selected ? "当前使用" : tone.valid ? "已安装" : "不可用")
                    }
                } else { Text("读取个性化数据后显示耳机内的提示音方案").foregroundStyle(.secondary) }
                Text("已找到欢律的提示音资源包接口。任意音频的编码、资源包校验及恢复流程尚未验证，暂不开放音色写入。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("其他能力") {
                if session.verifiedExperimental.contains("spatial"), let enabled = session.feature(0x1B) {
                    Toggle("空间音效", isOn: Binding(get: { enabled }, set: { session.setSpatialSound($0) })).disabled(!session.canWrite)
                    Text("耳机端空间音效，与高音质模式互斥；普通版不提供头部跟踪。").font(.caption).foregroundStyle(.secondary)
                } else { LabeledContent("空间音效", value: "待验证") }
                if session.verifiedExperimental.contains("latency") { featureToggle("低延迟模式", session.gameModeID) }
                else { LabeledContent("低延迟模式", value: "待验证") }
                if session.verifiedExperimental.contains("prompt"), let volume = session.promptVolume {
                    Stepper("提示音音量：\(volume) / 10", value: Binding(get: { volume }, set: { session.setPromptVolume($0) }), in: 1...10)
                        .disabled(!session.canWrite)
                    Text("修改后耳机会播放提示音。").font(.caption).foregroundStyle(.secondary)
                } else { LabeledContent("提示音音量", value: session.promptVolume.map { "\($0) / 10 · 待验证" } ?? "尚未取得状态") }
                Text("查找耳机、贴合检测和高级设备切换暂缓；完整听感测试不会自动启动。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var general: some View {
        Form {
            Section("你的耳机") {
                Picker("绑定设备", selection: $model.selectedDeviceAddress) {
                    Text("选择这副耳机").tag("")
                    ForEach(devices.devices) { Text($0.displayName).tag($0.id) }
                }
                Text("只接受产品 ID 068C10 的 Enco Free4 普通版。丹拿版及其他型号不会开放控制。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("打开系统蓝牙设置", action: model.openBluetoothSettings)
                Button("打开蓝牙隐私授权", action: model.openPrivacySettings)
                if let message = model.connectionPrerequisiteMessage { Text(message).foregroundStyle(.orange) }
            }
            Section("日常使用") {
                Toggle("耳机连接系统后自动连接控制", isOn: $model.autoConnect)
                Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                Text("登录启动默认关闭。手动断开控制后，本次系统连接期间不会自动重连。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("诊断") {
                Button("导出诊断日志…", action: model.exportDiagnostics)
                Text("日志不包含蓝牙地址、设备名称、账号或自定义方案内容。保留最近 1000 条协议事件。")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = model.applicationMessage { Text(message).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped)
    }
    private var progress: some View {
        Form {
            Section("0.1.0 · 实机验收中") {
                Text("界面可用不等于实机验收通过。协议和构建检查与实机验证分别记录，完整状态见随附文档。")
                LabeledContent("P0 基础连接、电量、噪声模式", value: "核心回读已验证 · 稳定性待验收")
                LabeledContent("P1 降噪档位、EQ、手势、双设备", value: "主要设置回读已验证 · 实际效果待核对")
                LabeledContent("P2 个性化方案", value: "已有方案读取已验证 · 写入与测试暂缓")
                LabeledContent("P2 空间、低延迟、提示音音量", value: "回读通过后开放 · 听感待核对")
                LabeledContent("P2 提示音内容／音色、查找", value: "方案读取已验证 · 写入／响铃暂缓")
                LabeledContent("P3 固件升级、账号、AI 服务", value: "仅研究 · 不执行刷写")
            }
            Section("来源与许可证") {
                Text("基于 OPPO Pods for macOS；参考 EncoFree4Menu 和 QuickBuds。遵循 GPL-3.0，来源版本及改动记录随源码提供。")
                Link("OPPO Pods for macOS", destination: URL(string: "https://github.com/ssigpoy/OPPO-Pods-for-macOS")!)
                Link("EncoFree4Menu", destination: URL(string: "https://github.com/wang29a/EncoFree4Menu")!)
                Link("QuickBuds", destination: URL(string: "https://github.com/spizganed/QuickBuds")!)
            }
        }.formStyle(.grouped)
    }
}
