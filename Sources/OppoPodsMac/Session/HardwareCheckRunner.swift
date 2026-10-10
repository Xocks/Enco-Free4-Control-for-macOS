import Foundation
import OppoPodsCore

// Opt-in acceptance driver. Exercises the same session methods as the UI and restores settings.
@MainActor
final class HardwareCheckRunner {
    private unowned let session: EarbudsSession
    private var results: [[String: String]] = []
    private var task: Task<Void, Never>?
    init(session: EarbudsSession) { self.session = session }
    func start(extended: Bool, extras: Bool = false) {
        guard task == nil else { return }
        task = Task { [weak self] in if extras { await self?.runExtras() } else { await self?.run(extended: extended) } }
    }
    private func wait(_ seconds: Double, until condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !Task.isCancelled {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return condition()
    }
    private func record(_ name: String, _ status: String, _ detail: String) {
        results.append(["name": name, "status": status, "detail": detail])
        session.log("hardware check: \(name) = \(status) \(detail)")
        writeReport()
    }
    private func writeReport() {
        let report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "productID": session.productID ?? "unknown", "firmware": session.firmware, "checks": results]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]) {
            try? data.write(to: Self.reportURL, options: .atomic)
        }
    }
    static var reportURL: URL { EarbudsSession.logURL.deletingLastPathComponent().appendingPathComponent("hardware-check.json") }
    private func operation(_ name: String, action: () -> Void) async -> Bool {
        guard session.canWrite else { record(name,"blocked","控制未就绪"); return false }
        action()
        guard session.pendingAction != nil else { record(name,"skipped","设备未声明能力或状态未读取"); return false }
        let ended = await wait(9) { self.session.pendingAction == nil }
        let success = ended && session.operationSucceeded
        record(name, success ? "passed" : "failed", session.operationMessage ?? "操作未结束")
        return success
    }
    private func runExtras() async {
        record("start extras","running","空间／低延迟／提示音逐项回读；恢复原设置")
        guard await wait(20, until: { self.session.isReady && !self.session.features.isEmpty && self.session.firmware != "未知" }) else {
            record("extras initialization","blocked","设备未就绪"); return
        }
        session.readPersonalization()
        _ = await wait(6) {
            (!self.session.supports(0x0130) || self.session.promptVolume != nil) &&
            (!self.session.supports(0x0121) || self.session.tonesRead) &&
            (!self.session.supports(0x0115) || self.session.goldenSummary != "尚未读取") &&
            (!self.session.supports(0x011E) || self.session.scanSummary != "尚未读取")
        }
        record("P2 tone presets read", session.tonesRead ? "passed" : "unconfirmed", "方案数=\(session.earTones.count)；仅记录数量，不导出名称")
        record("P2 Golden Sound read", session.hasGoldenRecord ? "passed" : "unconfirmed", "严格结构解析；不导出方案内容")
        record("P2 ear scan read", session.hasScanRecord ? "passed" : "unconfirmed", "严格结构解析；不导出扫描数据")
        if let spatial = session.feature(0x1B), session.feature(0x18) == false {
            let changed = await operation("P2 spatial toggle") { session.setSpatialSound(!spatial) }
            let restored = await operation("restore spatial") { session.setSpatialSound(spatial) }
            if changed && restored { session.markExperimentalVerified("spatial") }
        } else { record("P2 spatial","skipped","高音质互斥或未取得空间状态") }
        if let latency = session.feature(session.gameModeID) {
            let changed = await operation("P2 low latency toggle") { session.setFeature(session.gameModeID,enabled: !latency) }
            let restored = await operation("restore low latency") { session.setFeature(session.gameModeID,enabled: latency) }
            if changed && restored { session.markExperimentalVerified("latency") }
        }
        if let volume = session.promptVolume {
            let test = volume > 1 ? volume-1 : 2
            let changed = await operation("P2 prompt volume") { session.setPromptVolume(test) }
            let restored = await operation("restore prompt volume") { session.setPromptVolume(volume) }
            if changed && restored { session.markExperimentalVerified("prompt") }
        }
        record("finished extras","completed","回读成功的能力才开放；实际听感待用户核对")
    }
    private func run(extended: Bool) async {
        record("start","running","仅进行显式启用的验收；结束恢复原设置")
        guard await wait(20, until: { self.session.isReady && self.session.noiseControl != nil && self.session.eqListRead && !self.session.gestures.isEmpty && self.session.holdCycle != nil && self.session.codec != "未知" }) else {
            record("initialization","blocked","20 秒内未取得必要回报"); return
        }
        record("identity","passed","普通版 ID 已确认")
        record("firmware","passed",session.firmware)
        record("battery","passed","左\(session.battery.left?.level.description ?? "未知") 右\(session.battery.right?.level.description ?? "未知") 盒\(session.battery.chargingCase?.level.description ?? "未知")；未回报盒电量不算盒读数通过")
        let originalMode = session.noiseControl!, originalLevel = session.noiseLevel
        let remembered = session.rememberedLevel
        for (name,mode) in [("off",NoiseControlMode.off),("ANC",.noiseCancellation),("transparency",.transparency)] {
            _ = await operation("P0 mode \(name)") { session.setNoiseControl(mode) }
        }
        for level in NoiseLevel.allCases {
            _ = await operation("P1 ANC \(level.name)") { session.setNoiseLevel(level) }
        }
        _ = await operation("P1 adaptive") { session.setNoiseControl(.adaptive) }
        _ = await operation("restore ANC memory") { session.setNoiseLevel(originalLevel ?? remembered) }
        _ = await operation("restore original mode") { session.setNoiseControl(originalMode) }
        if extended {
            let originalEQ = session.selectedEQ
            for preset in session.equalizerPresets where [0,1,2,7].contains(preset.id) {
                _ = await operation("P1 EQ \(preset.id)") { session.setEQ(preset.id) }
            }
            if let originalEQ { _ = await operation("restore EQ") { session.setEQ(originalEQ) } }
            if let row = session.gestures.first(where: { $0.side == 1 && $0.button == 1 && $0.action == 2 }) {
                let next: UInt8 = row.function == 1 ? 5 : 1
                _ = await operation("P1 left double-tap write") { session.setGesture(row, function: next) }
                if let changed = session.gestures.first(where: { $0.id == row.id }) {
                    _ = await operation("restore left double-tap") { session.setGesture(changed, function: row.function) }
                }
            }
            if let wear = session.feature(4) {
                _ = await operation("P1 wear detection write") { session.setFeature(4,enabled: !wear) }
                _ = await operation("restore wear detection") { session.setFeature(4,enabled: wear) }
            }
            if let dual = session.feature(0x11) {
                _ = await operation("P1 multipoint same-value write") { session.setFeature(0x11,enabled: dual) }
            }
            if let cycle = session.holdCycle {
                _ = await operation("P1 hold cycle write") { session.setHoldCycle(cycle | 1) }
                _ = await operation("restore hold cycle") { session.setHoldCycle(cycle) }
            }
            if session.supports(0x0418), session.customEQPresets.count < session.capabilities.customEQMaximumPresets {
                let name = "Mac验收-" + UUID().uuidString.prefix(6)
                let frequencies = session.customEQFrequencies
                let initialCount = session.deviceEQPresets.count
                let range = session.deviceEQPresets.first
                let lower = range?.minimumGain ?? -6, upper = range?.maximumGain ?? 6
                let created = await operation("P1 custom EQ create") {
                    session.saveCustomEQ(id:0,name:String(name),frequencies:frequencies,gains:frequencies.map { _ in 0 },minimumGain:lower,maximumGain:upper)
                }
                if created, session.deviceEQPresets.count == initialCount+1,
                   let preset = session.customEQPresets.first(where: { $0.name == name }) {
                    var gains = preset.gains
                    if !gains.isEmpty { gains[0] = min(upper,1) }
                    _ = await operation("P1 custom EQ edit") {
                        session.saveCustomEQ(id:preset.id,name:preset.name,frequencies:preset.frequencies,gains:gains,minimumGain:lower,maximumGain:upper)
                    }
                    if let own = session.customEQPresets.first(where: { $0.name == name }) {
                        _ = await operation("P1 custom EQ delete own test preset") { session.deleteCustomEQ(own) }
                    }
                }
                if let originalEQ { _ = await operation("restore EQ after custom test") { session.setEQ(originalEQ) } }
            } else { record("P1 custom EQ CRUD","skipped","设备已达方案上限或未声明能力；不改动现有用户方案") }
            session.readPersonalization()
            _ = await wait(5) { self.session.goldenSummary != "尚未读取" && self.session.scanSummary != "尚未读取" }
            record("P2 personalization read","observed","已尝试读取；结果只显示在应用中，不写入方案名称")
        }
        record("finished","completed","只代表协议回读验证；实际手势效果、听感、手机核对与稳定性另验收")
    }
}
