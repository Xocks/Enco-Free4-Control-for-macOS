import Foundation
import OppoPodsCore

struct DeviceCapabilities: Equatable {
    let modelID: String
    let modelName: String
    let noiseModeByIndex: [Int: NoiseControlMode]
    let indexByNoiseMode: [NoiseControlMode: Int]
    let hasAdaptiveANC: Bool
    let hasNoiseLevels: Bool
    let hasGameMode: Bool
    let hasSpatialSound: Bool
    let hasSpatialAudioModes: Bool
    let hasWearDetection: Bool
    let hasDualDevice: Bool
    let equalizerPresets: [EqualizerPreset]
    let hasCustomEQ: Bool
    let customEQFrequencies: [Int]
    let customEQMaximumPresets: Int
    static let generic = DeviceCapabilities(modelID: "", modelName: "等待确认普通版身份", noiseModeByIndex: [:], indexByNoiseMode: [:], hasAdaptiveANC: false, hasNoiseLevels: false, hasGameMode: false, hasSpatialSound: false, hasSpatialAudioModes: false, hasWearDetection: false, hasDualDevice: false, equalizerPresets: [], hasCustomEQ: false, customEQFrequencies: [], customEQMaximumPresets: 3)
    static let free4 = DeviceCapabilities(modelID: "068C10", modelName: "OPPO Enco Free4", noiseModeByIndex: [3: .off, 4: .noiseCancellation, 5: .noiseCancellation, 6: .noiseCancellation, 7: .noiseCancellation, 8: .transparency, 11: .adaptive], indexByNoiseMode: [.off: 0, .noiseCancellation: 4, .transparency: 2, .adaptive: 11], hasAdaptiveANC: true, hasNoiseLevels: true, hasGameMode: false, hasSpatialSound: true, hasSpatialAudioModes: false, hasWearDetection: true, hasDualDevice: true, equalizerPresets: [.init(id: 0, name: "至臻原音"), .init(id: 1, name: "纯享人声"), .init(id: 2, name: "澎湃低音")], hasCustomEQ: true, customEQFrequencies: [62, 250, 1000, 4000, 8000, 16000], customEQMaximumPresets: 3)
}
final class DeviceModelRegistry {
    var modelCount: Int { 1 }
    func capabilities(for productID: String) -> DeviceCapabilities? { productID == Free4Protocol.productID ? .free4 : nil }
}
