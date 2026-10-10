import Foundation
import IOBluetooth
import OppoPodsCore

@MainActor
final class EarbudsSession: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var deviceName = "OPPO Enco Free4"
    @Published private(set) var productID: String?
    @Published private(set) var firmware = "未知"
    @Published private(set) var earFirmwareVersion = 0
    @Published private(set) var battery = BatteryStatus()
    @Published private(set) var batteryUpdatedAt: Date?
    @Published private(set) var noiseControl: NoiseControlMode?
    @Published private(set) var noiseLevel: NoiseLevel?
    @Published private(set) var rememberedLevel: NoiseLevel
    @Published private(set) var features: [UInt8: UInt8] = [:]
    @Published private(set) var selectedEQ: Int?
    @Published private(set) var deviceEQPresets: [DeviceEqualizerPreset] = []
    @Published private(set) var eqListRead = false
    @Published private(set) var gestures: [GestureEntry] = []
    @Published private(set) var holdCycle: UInt16?
    @Published private(set) var hosts: [ConnectedHost] = []
    @Published private(set) var supportedCommands: Set<Int> = []
    @Published private(set) var capabilities = DeviceCapabilities.generic
    @Published private(set) var pendingAction: String?
    @Published private(set) var operationMessage: String?
    @Published private(set) var operationSucceeded = false
    @Published private(set) var batteryIsStale = true
    @Published private(set) var codec = "未知"
    @Published private(set) var promptVolume: Int?
    @Published private(set) var earTones: [EarTonePreset] = []
    @Published private(set) var tonesRead = false
    @Published private(set) var goldenSummary = "尚未读取"
    @Published private(set) var scanSummary = "尚未读取"
    @Published private(set) var verifiedExperimental: Set<String> = []

    var isReady: Bool { connectionState == .connected && productID == Free4Protocol.productID }
    var canWrite: Bool { isReady && pendingAction == nil }
    var customEQPresets: [DeviceEqualizerPreset] {
        let builtIn = Set(capabilities.equalizerPresets.map(\.id) + (earFirmwareVersion >= 118 ? [7] : []))
        return deviceEQPresets.filter { !builtIn.contains($0.id) && !$0.name.isEmpty }
    }
    var equalizerPresets: [EqualizerPreset] {
        var result = capabilities.equalizerPresets
        // Ordinary Free4 metadata enables preset 7 starting with ear firmware 118.
        if earFirmwareVersion >= 118 { result.append(.init(id: 7, name: "活力动感")) }
        for preset in deviceEQPresets where !result.contains(where: { $0.id == preset.id }) {
            result.append(.init(id: preset.id, name: preset.name.isEmpty ? "设备音效 \(preset.id)" : preset.name))
        }
        return result
    }
    var customEQFrequencies: [Int] { customEQPresets.first(where: { !$0.frequencies.isEmpty })?.frequencies ?? capabilities.customEQFrequencies }
    func feature(_ id: UInt8) -> Bool? { guard let value = features[id], value <= 1 else { return nil }; return value == 1 }
    var gameModeID: UInt8 { features[0x28] != nil ? 0x28 : 0x06 }
    func supports(_ command: Int) -> Bool { supportedCommands.contains(command) }

    private var transport = RFCOMMTransport()
    private let commands = OppoCommands()
    private var framer = OppoPacketFramer()
    private var queue: [Data] = []
    private var queueTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var operationTimeoutTask: Task<Void, Never>?
    private var confirmationReadTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var queryRequests: [UInt8: (command: Int, time: Date)] = [:]
    private var generation = UUID()
    private var channelOpen = false
    private var pending: Pending?
    private var readStarted = false
    private var lines: [String] = []
    var hasGoldenRecord: Bool { goldenPayload != nil }
    var hasScanRecord: Bool { scanPayload != nil }
    private var goldenPayload: Data?
    private var scanPayload: Data?
    private struct Pending {
        var confirmation: OperationConfirmation
        let reads: () -> [Data]
        let matches: (OppoFrame) -> Bool
    }
    static var logURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EncoFree4/diagnostics.log")
    }

    init() {
        rememberedLevel = NoiseLevel(rawValue: UserDefaults.standard.integer(forKey: "confirmedNoiseLevel")) ?? .deep
        installCallbacks()
    }
    private func installCallbacks() {
        transport.onData = { [weak self] in self?.receive($0) }
        transport.onClosed = { [weak self] error in self?.endSession(error?.localizedDescription ?? "控制通道已断开") }
    }
    func connect(to device: IOBluetoothDevice) {
        guard connectionState != .connecting, connectionState != .connected else { return }
        disconnect()
        // A new delegate instance prevents late callbacks from an old SDP query entering this session.
        transport = RFCOMMTransport(); installCallbacks()
        clearReadings()
        connectionState = .connecting
        log("connect requested; systemConnected=\(device.isConnected())")
        let token = generation
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.generation == token, !self.isReady else { return }
            self.endSession("控制通道或型号确认超时，请检查蓝牙授权及耳机连接后重试。")
        }
        transport.connect(to: device) { [weak self] result in
            guard let self, self.generation == token else { return }
            switch result {
            case .success:
                self.channelOpen = true
                self.enqueue([self.commands.handshake(), self.commands.queryProductID(), self.commands.queryBroadcastCodes()])
            case .failure(let error): self.endSession(error.localizedDescription)
            }
        }
    }
    func disconnect() {
        generation = UUID()
        queueTask?.cancel(); queueTask = nil; queue.removeAll()
        connectionTimeoutTask?.cancel(); periodicTask?.cancel(); operationTimeoutTask?.cancel(); confirmationReadTask?.cancel()
        connectionTimeoutTask = nil; periodicTask = nil; operationTimeoutTask = nil; confirmationReadTask = nil
        channelOpen = false
        transport.close()
        if pending != nil { operationMessage = "连接已断开，操作未确认。" }
        else { operationMessage = nil }
        operationSucceeded = false
        pending = nil; pendingAction = nil; queryRequests.removeAll()
        framer = .init(); connectionState = .disconnected; batteryIsStale = true
    }
    private func endSession(_ reason: String) {
        log("disconnect: \(reason)"); disconnect(); connectionState = .failed(reason)
    }
    private func clearReadings() {
        productID = nil; firmware = "未知"; earFirmwareVersion = 0; battery = .init(); batteryUpdatedAt = nil; batteryIsStale = true
        noiseControl = nil; noiseLevel = nil; features = [:]; supportedCommands = []
        selectedEQ = nil; deviceEQPresets = []; eqListRead = false; gestures = []; holdCycle = nil; hosts = []
        capabilities = .generic; readStarted = false; operationMessage = nil
        earTones = []; tonesRead = false; verifiedExperimental = []; codec = "未知"; promptVolume = nil; goldenPayload = nil; scanPayload = nil
        goldenSummary = "尚未读取"; scanSummary = "尚未读取"
    }
    private func startReadings() {
        guard isReady, !readStarted else { return }
        readStarted = true
        refresh()
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, self.isReady else { return }
                if let time = self.batteryUpdatedAt, Date().timeIntervalSince(time) > 45 { self.batteryIsStale = true }
                self.refresh()
            }
        }
    }
    func refresh() {
        guard isReady, pendingAction == nil, queue.count < 10 else { return }
        var reads = [commands.queryBattery(), commands.queryANC(), commands.queryStatus()]
        for (cmd, payload) in [(0x0105, [UInt8]()), (0x010F, []), (0x0122, []), (0x0108, []),
                               (0x010C, [2, 1]), (0x0112, []), (0x0114, [])] where supports(cmd) {
            reads.append(commands.request(cmd, payload: payload))
        }
        enqueue(reads)
    }
    func setNoiseControl(_ mode: NoiseControlMode) {
        let index = mode == .noiseCancellation ? rememberedLevel.rawValue : capabilities.indexByNoiseMode[mode] ?? 0
        perform("切换噪声模式", write: commands.setNoiseControl(protocolIndex: index), reads: { [self] in [commands.queryANC()] }) {
            Free4Protocol.noise($0)?.mode == mode
        }
    }
    func setNoiseLevel(_ level: NoiseLevel) {
        perform("调整降噪档位", write: commands.setNoiseControl(protocolIndex: level.rawValue), reads: { [self] in [commands.queryANC()] }) {
            Free4Protocol.noise($0)?.level == level
        }
    }
    func setFeature(_ id: UInt8, enabled: Bool) {
        guard features[id] != nil, supports(0x0403) else { return }
        perform("更新耳机设置", write: commands.setFeature(id, enabled: enabled), reads: { [self] in [commands.queryStatus()] }) {
            Free4Protocol.features($0)?[id] == (enabled ? 1 : 0)
        }
    }
    private var verificationKey: String { "verifiedExperimental-068C10-" + firmware }
    func markExperimentalVerified(_ key: String) {
        verifiedExperimental.insert(key)
        UserDefaults.standard.set(verifiedExperimental.sorted(), forKey: verificationKey)
    }
    func setSpatialSound(_ enabled: Bool) {
        if enabled && feature(0x18) != false {
            operationSucceeded = false; operationMessage = "空间音效与高音质模式互斥。请先在欢律关闭高音质模式并刷新。"; return
        }
        setFeature(0x1B, enabled: enabled)
    }
    func setPromptVolume(_ value: Int) {
        guard (1...10).contains(value), promptVolume != nil, supports(0x0427) else { return }
        perform("设置提示音音量", write: commands.request(0x0427, payload: [UInt8(value)]), reads: { [self] in [commands.request(0x0130)] }) {
            $0.command == 0x8130 && Array($0.payload) == [0,UInt8(value)]
        }
    }
    func setEQ(_ id: Int) {
        guard selectedEQ != nil, supports(0x0406), equalizerPresets.contains(where: { $0.id == id }) else { return }
        perform("切换音效", write: commands.setEQ(id), reads: { [self] in [commands.queryEQ()] }) { OppoParsers.currentEQ(from: $0) == id }
    }
    func refreshCustomEQ() { guard isReady, supports(0x0122), pending == nil else { return }; enqueue([commands.queryAllEQ()]) }
    func saveCustomEQ(id: Int, name: String, frequencies: [Int], gains: [Int], minimumGain: Int, maximumGain: Int) {
        guard eqListRead, supports(0x0418), !name.isEmpty, name.utf8.count <= 255,
              !frequencies.isEmpty, frequencies.count == gains.count, minimumGain <= maximumGain,
              gains.allSatisfy({ (minimumGain...maximumGain).contains($0) }),
              id > 0 || customEQPresets.count < capabilities.customEQMaximumPresets else { return }
        let count = deviceEQPresets.count
        perform("保存均衡器", write: commands.saveCustomEQ(id: id, name: name, frequencies: frequencies, gains: gains, minimumGain: minimumGain, maximumGain: maximumGain), reads: { [self] in [commands.queryAllEQ()] }) {
            guard let rows = OppoParsers.allEqualizers(from: $0), id > 0 || rows.count == count+1 else { return false }
            return rows.contains { (id == 0 || $0.id == id) && $0.name == name && $0.frequencies == frequencies && $0.gains == gains }
        }
    }
    func deleteCustomEQ(_ preset: DeviceEqualizerPreset) {
        guard eqListRead, customEQPresets.contains(preset), supports(0x0418) else { return }
        let count = deviceEQPresets.count
        perform("删除均衡器", write: commands.deleteCustomEQ(preset), reads: { [self] in [commands.queryAllEQ(), commands.queryEQ()] }) {
            guard let rows = OppoParsers.allEqualizers(from: $0) else { return false }
            return rows.count == count-1 && !rows.contains(where: { $0.name == preset.name && $0.frequencies == preset.frequencies && $0.gains == preset.gains })
        }
    }
    func setGesture(_ entry: GestureEntry, function: UInt8) {
        guard supports(0x0401), gestures.contains(entry), entry.button != 6 else { return }
        // Update every non-call slot for the chosen ear/action, preserving actual button groups.
        let changes = gestures.filter { $0.side == entry.side && $0.action == entry.action && $0.button != 6 }.map { $0.replacingFunction(function) }
        guard !changes.isEmpty else { return }
        perform("更新耳机手势", write: commands.setGestures(changes), reads: { [self] in [commands.queryGestures()] }) {
            guard let rows = Free4Protocol.gestures($0) else { return false }
            return changes.allSatisfy { rows.contains($0) }
        }
    }
    func setHoldCycle(_ mask: UInt16) {
        guard mask != 0, mask & ~UInt16(0x0807) == 0, holdCycle != nil else { return }
        perform("更新长按循环", write: commands.setHoldCycle(mask), reads: { [self] in [commands.queryHoldCycle()] }) { Free4Protocol.holdCycle($0) == mask }
    }
    func readPersonalization() {
        guard isReady, pending == nil else { return }
        let codes = [0x0115, 0x011E, 0x0130, 0x0121].filter { supports($0) }
        enqueue(codes.map { commands.request($0) })
        if !supports(0x0115) { goldenSummary = "设备未声明此读取能力" }
        if !supports(0x011E) { scanSummary = "设备未声明此读取能力" }
    }
    private func perform(_ title: String, write: Data, reads: @escaping () -> [Data], matches: @escaping (OppoFrame) -> Bool) {
        guard canWrite, let frame = OppoFrame(data: write) else { return }
        queue.removeAll() // Polling must not delay a user operation.
        pendingAction = title; operationMessage = nil; operationSucceeded = false
        pending = Pending(confirmation: .init(write: frame), reads: reads, matches: matches)
        enqueue([write])
        let token = generation
        operationTimeoutTask?.cancel()
        operationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled, let self, self.generation == token, self.pending != nil else { return }
            self.finishOperation(false, "耳机未确认操作。保留最后回报的状态，请刷新或重试。")
        }
    }
    private func finishOperation(_ success: Bool, _ message: String) {
        log("operation \(pendingAction ?? "") success=\(success)")
        pending = nil; pendingAction = nil; operationTimeoutTask?.cancel(); operationTimeoutTask = nil
        confirmationReadTask?.cancel(); confirmationReadTask = nil
        operationSucceeded = success; operationMessage = message
    }
    private func enqueue(_ packets: [Data]) {
        guard channelOpen else { return }
        queue += packets
        guard queueTask == nil else { return }
        let token = generation
        queueTask = Task { [weak self] in
            // Earbud firmware needs the RFCOMM open event to settle.
            try? await Task.sleep(for: .milliseconds(200))
            while !Task.isCancelled, let self, self.generation == token, self.channelOpen, !self.queue.isEmpty {
                let packet = self.queue.removeFirst()
                self.sendNow(packet)
                try? await Task.sleep(for: .milliseconds(180))
            }
            if let self, self.generation == token { self.queueTask = nil }
        }
    }
    private func sendNow(_ packet: Data) {
        guard channelOpen, let frame = OppoFrame(data: packet) else { return }
        do {
            if frame.command < 0x8000 {
                queryRequests[frame.sequence] = (frame.command | 0x8000, Date())
                queryRequests = queryRequests.filter { Date().timeIntervalSince($0.value.time) < 15 }
            }
            try transport.send(packet)
            log(String(format: "TX %04X seq=%02X length=%d", frame.command, frame.sequence, frame.payload.count))
        } catch { endSession(error.localizedDescription) }
    }
    private func receive(_ data: Data) {
        for packet in framer.append(data) {
            guard let frame = OppoFrame(data: packet) else { continue }
            let rawCommands: Set<Int> = [0x8100,0x8103,0x8105,0x8106,0x810C,0x810D,0x8200]
            let hex = rawCommands.contains(frame.command) ? frame.payload.prefix(128).map { String(format: "%02X", $0) }.joined() : "redacted"
            log(String(format: "RX %04X seq=%02X length=%d payload=%@", frame.command, frame.sequence, frame.payload.count, hex))
            if answerDeviceRequest(frame) { continue }
            let solicited = frame.command >= 0x8000
            if solicited {
                guard let request = queryRequests[frame.sequence], request.command == frame.command,
                      Date().timeIntervalSince(request.time) < 15 else { log("ignored unmatched response"); continue }
                queryRequests.removeValue(forKey: frame.sequence)
            }
            if let id = OppoParsers.productID(from: frame) {
                guard id == Free4Protocol.productID else { endSession("型号 \(id) 不属于本应用适配的 Enco Free4 普通版。"); return }
                productID = id; capabilities = .free4; connectionState = .connected
                connectionTimeoutTask?.cancel(); connectionTimeoutTask = nil
                log("ordinary Free4 identity confirmed"); startReadings()
            }
            if let supported = Free4Protocol.supportedCommands(frame) {
                supportedCommands = supported
                if isReady { readStarted = false; startReadings() }
            }
            if let codes = OppoParsers.broadcastCodes(from: frame) {
                if supports(0x0205) { enqueue([commands.subscribe(to: codes)]) }
                else { enqueue(codes.map { commands.request(0x0201, payload: [$0]) }) }
            }
            guard isReady else { continue }
            if let reading = OppoParsers.battery(from: frame) {
                if frame.command == 0x8106 { battery = reading }
                else {
                    let b = Array(frame.payload)
                    let components = Set(stride(from: 2, to: b.count, by: 2).map { b[$0] })
                    if components.contains(1) { battery.left = reading.left }
                    if components.contains(2) { battery.right = reading.right }
                    if components.contains(3) { battery.chargingCase = reading.chargingCase }
                }
                batteryUpdatedAt = Date(); batteryIsStale = false
            }
            if let reading = Free4Protocol.noise(frame) {
                noiseControl = reading.mode; noiseLevel = reading.level
                log("noise report mode=\(reading.mode.rawValue) level=\(reading.level?.rawValue.description ?? "unknown") source=\(frame.command == 0x0204 ? "push" : "query")")
                if let level = reading.level {
                    rememberedLevel = level; UserDefaults.standard.set(level.rawValue, forKey: "confirmedNoiseLevel")
                }
            }
            if let values = Free4Protocol.features(frame) { features = values }
            if let value = Free4Protocol.firmware(frame), !value.isEmpty {
                firmware = value
                verifiedExperimental = Set(UserDefaults.standard.stringArray(forKey: verificationKey) ?? [])
                earFirmwareVersion = value.split(separator: ".").prefix(2).compactMap { Int($0) }.filter { $0 > 0 }.min() ?? 0
            }
            if let value = OppoParsers.currentEQ(from: frame) { selectedEQ = value }
            if let values = OppoParsers.allEqualizers(from: frame) {
                deviceEQPresets = values; eqListRead = true
                if let chosen = values.first(where: \.isSelected) { selectedEQ = chosen.id }
            }
            if let values = Free4Protocol.gestures(frame) { gestures = values }
            if let value = Free4Protocol.holdCycle(frame) { holdCycle = value }
            if let values = Free4Protocol.hosts(frame) { hosts = values }
            if let values = EarTonePreset.parse(frame) { earTones = values; tonesRead = true }
            parseOptionalReading(frame)
            if var action = pending {
                let alreadyACK = action.confirmation.acknowledged
                if let accepted = action.confirmation.acceptAcknowledgement(frame), !alreadyACK {
                    guard accepted else { finishOperation(false, "耳机拒绝了操作（\(frame.payload.first ?? 255)），原设置保留。"); continue }
                    let reads = action.reads()
                    for read in reads { if let f = OppoFrame(data: read) { action.confirmation.registerRead(f) } }
                    pending = action; enqueue(reads); scheduleConfirmationReads()
                } else if action.confirmation.acceptsRead(frame), action.matches(frame) {
                    finishOperation(true, "耳机已回报并确认设置。")
                }
            }
        }
    }
    private func scheduleConfirmationReads() {
        confirmationReadTask?.cancel()
        let token = generation
        confirmationReadTask = Task { [weak self] in
            // Some firmware acknowledges before its query state changes. Re-read, never resend
            // the write, and still require a response to a registered query before the deadline.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, let self, self.generation == token,
                      var action = self.pending, action.confirmation.acknowledged else { return }
                let reads = action.reads()
                for read in reads { if let frame = OppoFrame(data: read) { action.confirmation.registerRead(frame) } }
                self.pending = action; self.enqueue(reads)
            }
        }
    }
    private func parseOptionalReading(_ frame: OppoFrame) {
        let b = Array(frame.payload)
        guard b.first == 0 else { return }
        if frame.command == 0x8114, b.count == 2 {
            codec = [1: "SBC", 2: "AAC", 3: "LDAC", 4: "aptX", 5: "aptX HD", 6: "aptX Adaptive", 7: "LHDC", 8: "LHDC v5"][Int(b[1])] ?? "设备回报 \(b[1])"
        }
        if frame.command == 0x8130, b.count == 2, (1...10).contains(b[1]) { promptVolume = Int(b[1]) }
        if frame.command == 0x8115 {
            if let record = HearingRecord.parse(frame) {
                goldenPayload = frame.payload; goldenSummary = record.name.isEmpty ? "已读取当前听感方案（12 项参数）" : "已读取：" + record.name
            } else { goldenSummary = "未取得可识别的当前方案" }
        }
        if frame.command == 0x811E {
            if let record = EarScanRecord.parse(frame) {
                scanPayload = frame.payload; scanSummary = "已读取当前耳道数据（\(record.data.count) 字节）"
            } else { scanSummary = "未取得可识别的耳道数据" }
        }
    }
    private func answerDeviceRequest(_ frame: OppoFrame) -> Bool {
        let payload: [UInt8]
        switch frame.command {
        case 0x0500:
            let seconds = UInt32(Date().timeIntervalSince1970)
            payload = [0] + (0..<4).map { UInt8(truncatingIfNeeded: seconds >> ($0*8)) }
        case 0x050C: payload = [0,1,0]
        case 0x051C: payload = [0,0,0]
        case 0x051D: payload = [1]
        case 0x0204 where frame.payload.first == 0xF2: payload = [0,0xF2]
        case 0x0204 where frame.payload.first == 0xF4:
            let json = frame.payload.dropFirst()
            if json.isEmpty { payload = [0,0xF4] }
            else if let object = try? JSONSerialization.jsonObject(with: Data(json)) as? [String: Any] {
                let answer: [String: String] = (object["cmd"] as? String).map { ["cmd": $0] } ?? [:]
                payload = [0,0xF4] + Array((try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])) ?? Data())
            } else { payload = [1,0xF4] }
        default:
            guard frame.command < 0x8000, ![0x0100,0x0200,0x0300,0x0400,0x0500,0x0F00].contains(frame.command & 0x7F00) else { return false }
            payload = [1]
        }
        sendNow(OppoFrame(command: frame.command | 0x8000, sequence: frame.sequence, payload: Data(payload)).data)
        return true
    }
    func log(_ message: String) {
        let time = ISO8601DateFormatter().string(from: Date())
        lines.append("\(time) \(message)")
        if lines.count > 1000 { lines.removeFirst(lines.count-1000) }
        let url = Self.logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    func diagnosticText() -> String {
        "Enco Free4 控制 0.1.0\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n型号: \(productID ?? "未知")\n固件: \(firmware)\n控制: \(connectionState)\n电量过期: \(batteryIsStale)\n功能已声明: \(supportedCommands.sorted().map { String(format: "%04X", $0) }.joined(separator: ","))\n\n" + lines.joined(separator: "\n")
    }
}
