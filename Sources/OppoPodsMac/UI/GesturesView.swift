import SwiftUI
import OppoPodsCore

struct GesturesView: View {
    @EnvironmentObject private var session: EarbudsSession
    private let names: [UInt8: String] = [0: "无操作", 1: "播放／暂停", 3: "语音助手", 5: "上一曲", 6: "下一曲", 7: "音量调节", 8: "噪声模式循环", 0x0A: "切换曲目", 0x0B: "音量加", 0x0C: "音量减", 0x0D: "切换设备", 0x11: "低延迟模式"]
    // Ordinary Free4 model control masks from the pinned HeyMelody catalog.
    private let support: [UInt8: Int] = [1: 516, 2: 8807, 3: 3154531, 5: 3584]
    private let bitByFunction: [UInt8: Int] = [0: 512, 1: 4, 3: 1, 5: 32, 6: 64, 7: 1024, 8: 128, 0x0A: 2048, 0x0B: 8, 0x0C: 16, 0x0D: 4096, 0x11: 8192]
    var body: some View {
        Form {
            if session.gestures.isEmpty {
                Section { Text("连接后读取左右耳手势。未读到的手势不会写入耳机。").foregroundStyle(.secondary) }
            }
            ForEach([UInt8(1), 2], id: \.self) { side in
                Section(side == 1 ? "左耳" : "右耳") {
                    ForEach(rows(side)) { entry in
                        Picker(actionName(entry.action), selection: Binding(get: { entry.function }, set: { session.setGesture(entry, function: $0) })) {
                            ForEach(choices(entry), id: \.self) { function in Text(names[function] ?? "当前设备操作 \(function)").tag(function) }
                        }.disabled(!session.canWrite || !session.supports(0x0401))
                    }
                }
            }
            Section("长按噪声模式循环 · 左右耳共用") {
                if let mask = session.holdCycle {
                    cycle("关闭", bit: 0, mask: mask); cycle("降噪", bit: 1, mask: mask)
                    cycle("通透", bit: 2, mask: mask); cycle("自适应", bit: 11, mask: mask)
                    Text("至少保留一种模式。关闭某个手势不会自动删除循环中的模式。")
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text("等待耳机回报循环设置").foregroundStyle(.secondary) }
            }
            Section {
                Text("通话手势及手机服务专属操作暂缓。完成设置后，请在耳机上触发一次手势核对实际效果。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func rows(_ side: UInt8) -> [GestureEntry] {
        var seen: Set<UInt8> = []
        return session.gestures.filter { $0.side == side && $0.button != 6 && support[$0.action] != nil }
            .sorted { $0.button < $1.button }.filter { seen.insert($0.action).inserted }.sorted { $0.action < $1.action }
    }
    private func actionName(_ action: UInt8) -> String { [1: "单击", 2: "双击", 3: "三击", 5: "滑动"][action] ?? "动作 \(action)" }
    private func choices(_ row: GestureEntry) -> [UInt8] {
        var values = names.keys.filter { (support[row.action] ?? 0) & (bitByFunction[$0] ?? 0) != 0 }
        if !values.contains(row.function) { values.append(row.function) }
        return values.sorted()
    }
    private func cycle(_ name: String, bit: Int, mask: UInt16) -> some View {
        let flag = UInt16(1 << bit)
        return Toggle(name, isOn: Binding(get: { mask & flag != 0 }, set: { enabled in session.setHoldCycle(enabled ? mask | flag : mask & ~flag) }))
            .disabled(!session.canWrite || (!((mask & flag) == 0) && mask.nonzeroBitCount == 1))
    }
}
