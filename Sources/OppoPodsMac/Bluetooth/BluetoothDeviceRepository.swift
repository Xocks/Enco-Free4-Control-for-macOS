import Foundation
import IOBluetooth
import CoreBluetooth

struct PairedBluetoothDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let isConnected: Bool
    var displayName: String { name.isEmpty ? "已绑定的 Enco Free4" : name }
}

@MainActor
final class BluetoothDeviceRepository: ObservableObject {
    @Published private(set) var devices: [PairedBluetoothDevice] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var isBluetoothPoweredOn = false
    @Published private(set) var authorization: CBManagerAuthorization = .notDetermined
    var boundAddress = ""
    private var loading = false
    private let discoveryQueue = DispatchQueue(label: "local.encofree4.discovery", qos: .utility)

    func refresh() {
        guard !loading else { return }
        loading = true
        let bound = boundAddress
        // IOBluetooth's coordinator can synchronously wait for CoreBluetooth initialization.
        // Never do this while SwiftUI is constructing its scene, or block the app's main run loop.
        discoveryQueue.async { [weak self] in
            let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            let snapshots = paired.filter { $0.addressString == bound || Self.isCandidate($0.name ?? "") }.map {
                PairedBluetoothDevice(id: $0.addressString, name: $0.name ?? "", isConnected: $0.isConnected())
            }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            let powered = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
            let permission = CBCentralManager.authorization
            Task { @MainActor in
                guard let self else { return }
                self.loading = false
                guard self.boundAddress == bound else { self.refresh(); return }
                self.devices = snapshots; self.isBluetoothPoweredOn = powered
                self.authorization = permission; self.hasLoaded = true
            }
        }
    }
    func device(for address: String) -> IOBluetoothDevice? {
        guard hasLoaded, !address.isEmpty else { return nil }
        return IOBluetoothDevice(addressString: address)
    }
    nonisolated private static func isCandidate(_ name: String) -> Bool {
        let value = name.lowercased()
        return value.contains("enco free4") && !value.contains("dynaudio") && !value.contains("丹拿")
    }
}
