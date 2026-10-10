import Foundation

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

public enum NoiseControlMode: Int, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case noiseCancellation
    case transparency
    case adaptive

    public var id: Int { rawValue }
}

public enum SpatialAudioMode: Int, CaseIterable, Identifiable, Sendable {
    case off = 0
    case fixed = 1
    case headTracking = 2

    public var id: Int { rawValue }
}

public struct BatteryLevel: Equatable, Sendable {
    public var level: Int
    public var isCharging: Bool

    public init(level: Int, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }
}

public struct BatteryStatus: Equatable, Sendable {
    public var left: BatteryLevel?
    public var right: BatteryLevel?
    public var chargingCase: BatteryLevel?

    public init(left: BatteryLevel? = nil, right: BatteryLevel? = nil, chargingCase: BatteryLevel? = nil) {
        self.left = left
        self.right = right
        self.chargingCase = chargingCase
    }

    public var menuBarLevel: Int? {
        [left?.level, right?.level].compactMap { $0 }.min()
    }
}

public struct FeatureStatus: Equatable, Sendable {
    public var gameMode: Bool?
    public var lowLatencyMode: Bool?
    public var wearDetection: Bool?
    public var dualDevice: Bool?
    public var spatialSound: Bool?

    public init(gameMode: Bool? = nil, lowLatencyMode: Bool? = nil, wearDetection: Bool? = nil, dualDevice: Bool? = nil, spatialSound: Bool? = nil) {
        self.gameMode = gameMode
        self.lowLatencyMode = lowLatencyMode
        self.wearDetection = wearDetection
        self.dualDevice = dualDevice
        self.spatialSound = spatialSound
    }
}

public struct EqualizerPreset: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct DeviceEqualizerPreset: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let name: String
    public let isSelected: Bool
    public let minimumGain: Int
    public let maximumGain: Int
    public let frequencies: [Int]
    public let gains: [Int]

    public init(
        id: Int,
        name: String,
        isSelected: Bool = false,
        minimumGain: Int = -6,
        maximumGain: Int = 6,
        frequencies: [Int] = [],
        gains: [Int] = []
    ) {
        self.id = id
        self.name = name
        self.isSelected = isSelected
        self.minimumGain = minimumGain
        self.maximumGain = maximumGain
        self.frequencies = frequencies
        self.gains = gains
    }
}
