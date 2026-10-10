import Foundation

public struct OppoCommands: Sendable {
    private let builder: OppoPacketBuilder

    public init(builder: OppoPacketBuilder = OppoPacketBuilder()) {
        self.builder = builder
    }

    public func request(_ command: Int, payload: [UInt8] = []) -> Data { builder.make(command, payload: payload) }
    public func queryGestures() -> Data { builder.make(0x0108) }
    public func queryHoldCycle() -> Data { builder.make(0x010C, payload: [2, 1]) }
    public func setHoldCycle(_ mask: UInt16) -> Data {
        builder.make(0x0404, payload: [2, 1, UInt8(truncatingIfNeeded: mask)] + (mask > 255 ? [UInt8(mask >> 8)] : []))
    }
    public func setGestures(_ entries: [GestureEntry]) -> Data {
        precondition(!entries.isEmpty && entries.count <= 255)
        return builder.make(0x0401, payload: [UInt8(entries.count)] + entries.flatMap { [$0.side, $0.button, $0.action, $0.function] })
    }
    public func handshake() -> Data { builder.make(OppoCommand.handshake) }
    public func queryProductID() -> Data { builder.make(OppoCommand.queryProductID) }
    public func queryBattery() -> Data { builder.make(OppoCommand.queryBattery) }
    public func queryANC() -> Data { builder.make(OppoCommand.queryANC, payload: [0x01, 0x01]) }
    public func queryEQ() -> Data { builder.make(OppoCommand.queryEQ) }
    public func queryAllEQ() -> Data { builder.make(OppoCommand.queryAllEQ) }
    public func queryBroadcastCodes() -> Data { builder.make(OppoCommand.queryBroadcastCodes) }

    public func queryStatus() -> Data {
        builder.make(
            OppoCommand.queryStatus,
            payload: [0x0B, 0x05, 0x04, 0x0B, 0x11, 0x13, 0x18, 0x06, 0x1B, 0x1C, 0x27, 0x28]
        )
    }

    public func subscribe(to codes: [UInt8]) -> Data {
        builder.make(OppoCommand.subscribeBroadcast, payload: [UInt8(clamping: codes.count)] + codes)
    }

    public func setNoiseControl(_ mode: NoiseControlMode) -> Data {
        let payload: [UInt8]
        switch mode {
        case .off: payload = [0x01, 0x01, 0x01]
        case .noiseCancellation: payload = [0x01, 0x01, 0x10]
        case .transparency: payload = [0x01, 0x01, 0x04]
        case .adaptive: payload = [0x01, 0x01, 0x00, 0x08]
        }
        return builder.make(OppoCommand.setANC, payload: payload)
    }

    public func setNoiseControl(protocolIndex: Int) -> Data {
        precondition((0..<16).contains(protocolIndex))
        let byteCount = protocolIndex / 8 + 1
        var payload = [UInt8](repeating: 0, count: 2 + byteCount)
        payload[0] = 0x01
        payload[1] = 0x01
        payload[2 + protocolIndex / 8] = UInt8(1 << (protocolIndex % 8))
        return builder.make(OppoCommand.setANC, payload: payload)
    }

    public func setFeature(_ feature: UInt8, enabled: Bool) -> Data {
        builder.make(OppoCommand.setFeature, payload: [feature, enabled ? 1 : 0])
    }

    public func setSpatialAudio(_ mode: SpatialAudioMode) -> Data {
        builder.make(OppoCommand.setSpatialAudio, payload: [UInt8(mode.rawValue)])
    }

    public func setEQ(_ presetID: Int) -> Data {
        builder.make(OppoCommand.setEQ, payload: [UInt8(clamping: presetID)])
    }

    public func saveCustomEQ(
        id: Int,
        name: String,
        frequencies: [Int],
        gains: [Int],
        minimumGain: Int = -6,
        maximumGain: Int = 6
    ) -> Data {
        builder.make(
            OppoCommand.setEQDetail,
            payload: equalizerDetailPayload(
                action: id > 0 ? 2 : 1,
                id: id,
                name: name,
                frequencies: frequencies,
                gains: gains,
                minimumGain: minimumGain,
                maximumGain: maximumGain
            )
        )
    }

    public func deleteCustomEQ(_ preset: DeviceEqualizerPreset) -> Data {
        builder.make(
            OppoCommand.setEQDetail,
            payload: equalizerDetailPayload(
                action: 3,
                id: preset.id,
                name: preset.name,
                frequencies: preset.frequencies,
                gains: preset.gains,
                minimumGain: preset.minimumGain,
                maximumGain: preset.maximumGain
            )
        )
    }

    private func equalizerDetailPayload(
        action: Int,
        id: Int,
        name: String,
        frequencies: [Int],
        gains: [Int],
        minimumGain: Int,
        maximumGain: Int
    ) -> [UInt8] {
        let defaultFrequencies = [62, 250, 1_000, 4_000, 8_000, 16_000]
        let safeFrequencies = Array((frequencies.isEmpty ? defaultFrequencies : frequencies).prefix(32))
        let lower = min(minimumGain, maximumGain).clamped(to: -128...127)
        let upper = max(minimumGain, maximumGain).clamped(to: lower...127)
        var safeName = name
        while safeName.utf8.count > 255 { safeName.removeLast() }
        let nameBytes = Array(safeName.utf8)
        var payload: [UInt8] = [
            UInt8(clamping: action.clamped(to: 1...3)),
            UInt8(bitPattern: Int8(lower)),
            UInt8(bitPattern: Int8(upper)),
            UInt8(clamping: id),
            UInt8(nameBytes.count)
        ]
        payload.append(contentsOf: nameBytes)
        payload.append(UInt8(safeFrequencies.count))
        for (index, frequency) in safeFrequencies.enumerated() {
            let safeFrequency = frequency.clamped(to: 0...0xFFFF)
            payload.append(UInt8(truncatingIfNeeded: safeFrequency))
            payload.append(UInt8(truncatingIfNeeded: safeFrequency >> 8))
            let gain = (gains.indices.contains(index) ? gains[index] : 0).clamped(to: lower...upper)
            payload.append(UInt8(bitPattern: Int8(gain)))
        }
        return payload
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
