import Foundation

public enum OppoParsers {
    public static func battery(from frame: OppoFrame) -> BatteryStatus? {
        let payload = Array(frame.payload)
        let pairs: [UInt8]
        if frame.command == OppoCommand.batteryResponse {
            if payload.count >= 2 && payload[0] == 0 {
                guard payload.count == 2 + Int(payload[1]) * 2 else { return nil }
                pairs = Array(payload.dropFirst(2))
            } else {
                guard !payload.isEmpty, payload.count % 2 == 0 else { return nil }
                pairs = payload
            }
        } else if frame.command == OppoCommand.activeReport {
            guard payload.count >= 2, payload[0] == 1, payload.count == 2 + Int(payload[1]) * 2 else { return nil }
            pairs = Array(payload.dropFirst(2))
        } else { return nil }
        var status = BatteryStatus()
        var seen: Set<UInt8> = []
        for i in stride(from: 0, to: pairs.count, by: 2) {
            let component = pairs[i], raw = pairs[i+1]
            guard (1...3).contains(component), seen.insert(component).inserted else { return nil }
            let level = Int(raw & 0x7F)
            let value: BatteryLevel? = (1...100).contains(level) ? .init(level: level, isCharging: raw & 0x80 != 0) : nil
            switch component { case 1: status.left = value; case 2: status.right = value; default: status.chargingCase = value }
        }
        return status
    }

    public static func productID(from frame: OppoFrame) -> String? {
        let bytes = Array(frame.payload)
        guard frame.command == OppoCommand.productIDResponse,
              bytes.count == 4, bytes[0] == 0 else { return nil }
        let identifier = Int(bytes[1]) | (Int(bytes[2]) << 8) | (Int(bytes[3]) << 16)
        return String(format: "%06X", identifier)
    }

    public static func noiseControl(from frame: OppoFrame) -> NoiseControlMode? { Free4Protocol.noise(frame)?.mode }
    public static func noiseControl(from frame: OppoFrame, indexToMode: [Int: NoiseControlMode]) -> NoiseControlMode? {
        Free4Protocol.noise(frame)?.mode
    }
    public static func featureStatus(from frame: OppoFrame) -> FeatureStatus? {
        guard let map = Free4Protocol.features(frame) else { return nil }
        func flag(_ id: UInt8) -> Bool? { guard let value = map[id], value <= 1 else { return nil }; return value == 1 }
        return .init(gameMode: flag(0x28), lowLatencyMode: flag(6), wearDetection: flag(4), dualDevice: flag(0x11), spatialSound: flag(0x1B))
    }

    public static func spatialAudio(from frame: OppoFrame) -> SpatialAudioMode? {
        guard frame.command == OppoCommand.spatialAudioNotify,
              let raw = frame.payload.first else { return nil }
        return SpatialAudioMode(rawValue: Int(raw))
    }

    public static func broadcastCodes(from frame: OppoFrame) -> [UInt8]? {
        let bytes = Array(frame.payload)
        guard frame.command == OppoCommand.broadcastCodesResponse, bytes.count >= 2, bytes[0] == 0, bytes.count == 2 + Int(bytes[1]) else { return nil }
        return Array(bytes.dropFirst(2))
    }

    public static func currentEQ(from frame: OppoFrame) -> Int? {
        let bytes = Array(frame.payload)
        if frame.command == 0x0504, bytes.count == 1 { return Int(bytes[0]) }
        guard frame.command == OppoCommand.eqResponse, bytes.count == 2, bytes[0] == 0 else { return nil }
        return Int(bytes[1])
    }

    public static func allEqualizers(from frame: OppoFrame) -> [DeviceEqualizerPreset]? {
        guard frame.command == OppoCommand.allEQResponse else { return nil }
        let bytes = Array(frame.payload)
        guard bytes.count >= 2, bytes[0] == 0 else { return nil }

        let expectedCount = Int(bytes[1])
        var position = 2
        var presets: [DeviceEqualizerPreset] = []
        while presets.count < expectedCount {
            guard position + 5 <= bytes.count else { return nil }
            let selected = bytes[position] != 0
            let minimumGain = Int(Int8(bitPattern: bytes[position + 1]))
            let maximumGain = Int(Int8(bitPattern: bytes[position + 2]))
            let presetID = Int(bytes[position + 3])
            let nameLength = Int(bytes[position + 4])
            position += 5
            guard position + nameLength <= bytes.count else { return nil }
            guard let name = String(bytes: bytes[position..<(position + nameLength)], encoding: .utf8),
                  minimumGain <= maximumGain else { return nil }
            position += nameLength

            guard position < bytes.count else { return nil }
            let frequencyCount = Int(bytes[position])
            position += 1
            guard position + frequencyCount * 3 <= bytes.count else { return nil }
            var frequencies: [Int] = []
            var gains: [Int] = []
            for _ in 0..<frequencyCount {
                frequencies.append(Int(bytes[position]) | (Int(bytes[position + 1]) << 8))
                gains.append(Int(Int8(bitPattern: bytes[position + 2])))
                position += 3
            }
            presets.append(DeviceEqualizerPreset(
                id: presetID,
                name: name,
                isSelected: selected,
                minimumGain: minimumGain,
                maximumGain: maximumGain,
                frequencies: frequencies,
                gains: gains
            ))
        }
        guard position == bytes.count, Set(presets.map(\.id)).count == presets.count else { return nil }
        return presets
    }
}
