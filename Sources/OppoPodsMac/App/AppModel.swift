import AppKit
import Combine
import IOBluetooth
import ServiceManagement
import UniformTypeIdentifiers
import OppoPodsCore

@MainActor
final class AppModel: NSObject, ObservableObject {
    let devices = BluetoothDeviceRepository()
    let session = EarbudsSession()
    @Published var selectedDeviceAddress: String {
        didSet {
            guard selectedDeviceAddress != oldValue else { return }
            session.disconnect(); manualDisconnect = false; attempts = 0
            UserDefaults.standard.set(selectedDeviceAddress, forKey: "selectedDeviceAddress")
            devices.boundAddress = selectedDeviceAddress; devices.refresh()
            connectionPrerequisiteMessage = nil
        }
    }
    @Published var autoConnect: Bool {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: "autoConnect")
            if autoConnect { manualDisconnect = false; attempts = 0; reconnectIfNeeded() }
        }
    }
    @Published private(set) var loginEnabled = false
    @Published private(set) var connectionPrerequisiteMessage: String?
    @Published private(set) var applicationMessage: String?
    private var connectNotification: IOBluetoothUserNotification?
    private var registeringConnectNotification = false
    private var disconnectNotification: IOBluetoothUserNotification?
    private var observers: [NSObjectProtocol] = []
    private var monitorTask: Task<Void, Never>?
    private var observation: AnyCancellable?
    private var hardwareChecks: HardwareCheckRunner?
    private var manualDisconnect = false
    private var sleeping = false
    private var attempts = 0
    private var nextAttempt = Date.distantPast
    private var lastSystemConnected = false
    private var hardwarePreviouslyVisible = false

    var selectedDeviceIsSystemConnected: Bool { devices.devices.first(where: { $0.id == selectedDeviceAddress })?.isConnected == true }
    var bluetoothAvailable: Bool { devices.isBluetoothPoweredOn }

    override init() {
        selectedDeviceAddress = UserDefaults.standard.string(forKey: "selectedDeviceAddress") ?? ""
        autoConnect = UserDefaults.standard.object(forKey: "autoConnect") as? Bool ?? true
        super.init()
        devices.boundAddress = selectedDeviceAddress; devices.refresh()
        if selectedDeviceAddress.isEmpty, devices.devices.count == 1 { selectedDeviceAddress = devices.devices[0].id }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = true; self?.session.log("system sleep"); self?.session.disconnect() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }; self.sleeping = false; self.attempts = 0
                self.nextAttempt = Date().addingTimeInterval(2); self.session.log("system wake")
            }
        })
        observation = session.$connectionState.dropFirst().sink { [weak self] state in
            guard let self else { return }
            if state == .connected { self.attempts = 0 }
        }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refreshDevices()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        refreshLoginState()
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--hardware-check") || arguments.contains("--hardware-check-extended") || arguments.contains("--hardware-check-extras") {
            hardwareChecks = HardwareCheckRunner(session: session)
            hardwareChecks?.start(extended: arguments.contains("--hardware-check-extended"), extras: arguments.contains("--hardware-check-extras"))
        }
    }
    func refreshDevices() {
        guard !sleeping else { return }
        devices.refresh()
        guard devices.hasLoaded else { connectionPrerequisiteMessage = "正在读取系统蓝牙，请留意首次授权提示。"; return }
        if connectNotification == nil && !registeringConnectNotification {
            registeringConnectNotification = true
            connectNotification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(bluetoothConnected(_:device:)))
            registeringConnectNotification = false
            updateDisconnectNotification()
        }
        if selectedDeviceAddress.isEmpty, devices.devices.count == 1 { selectedDeviceAddress = devices.devices[0].id }
        let connected = selectedDeviceIsSystemConnected
        if connected != lastSystemConnected {
            session.log("system connection changed=\(connected)")
            lastSystemConnected = connected
            if connected { attempts = 0; manualDisconnect = false; nextAttempt = Date().addingTimeInterval(1); updateDisconnectNotification() }
            else { session.disconnect() }
        }
        hardwarePreviouslyVisible = hardwarePreviouslyVisible || !devices.devices.isEmpty
        if devices.authorization == .denied || devices.authorization == .restricted {
            connectionPrerequisiteMessage = "蓝牙访问未获允许，请在系统隐私设置中授权后重试。"
        }
        else if !bluetoothAvailable { connectionPrerequisiteMessage = "蓝牙已关闭，请先在系统设置中开启。" }
        else if devices.devices.isEmpty {
            connectionPrerequisiteMessage = hardwarePreviouslyVisible ? "耳机暂不可见，请检查蓝牙授权。" : "请在系统蓝牙中配对 Enco Free4，并允许本应用访问蓝牙。"
        } else { connectionPrerequisiteMessage = nil }
        reconnectIfNeeded()
    }
    func connectSelectedDevice() {
        manualDisconnect = false; attempts = 0; connectNow()
    }
    private func connectNow() {
        guard !sleeping else { return }
        devices.refresh()
        guard !selectedDeviceAddress.isEmpty, let device = devices.device(for: selectedDeviceAddress), device.isConnected() else {
            connectionPrerequisiteMessage = "请先在系统蓝牙中连接这副 Enco Free4。"; return
        }
        connectionPrerequisiteMessage = nil
        attempts += 1
        // Bounded backoff. A new audio connection, wake or explicit retry resets this budget.
        nextAttempt = Date().addingTimeInterval([3.0, 8.0, 20.0][min(attempts-1, 2)])
        session.connect(to: device)
    }
    func reconnectIfNeeded() {
        guard autoConnect, !manualDisconnect, !sleeping, attempts < 3, Date() >= nextAttempt, selectedDeviceIsSystemConnected else { return }
        switch session.connectionState {
        case .disconnected, .failed: connectNow()
        default: break
        }
    }
    func disconnectControl() { manualDisconnect = true; session.disconnect() }
    func openBluetoothSettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }
    func openPrivacySettings() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!) }
    func refreshLoginState() { loginEnabled = SMAppService.mainApp.status == .enabled }
    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLoginState()
            if enabled, SMAppService.mainApp.status == .requiresApproval {
                applicationMessage = "请在系统“登录项”中允许 Enco Free4 控制。"; SMAppService.openSystemSettingsLoginItems()
            } else { applicationMessage = nil }
        } catch { applicationMessage = "登录启动设置失败：\(error.localizedDescription)"; refreshLoginState() }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Enco-Free4-诊断.txt"; panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try session.diagnosticText().write(to: url, atomically: true, encoding: .utf8); applicationMessage = "诊断日志已导出。" }
        catch { applicationMessage = "导出失败：\(error.localizedDescription)" }
    }
    private func updateDisconnectNotification() {
        disconnectNotification?.unregister(); disconnectNotification = nil
        if let device = devices.device(for: selectedDeviceAddress) {
            disconnectNotification = device.register(forDisconnectNotification: self, selector: #selector(bluetoothDisconnected(_:device:)))
        }
    }
    @objc private func bluetoothConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString
        // Registration synchronously reports already-connected devices. Defer handling until
        // the returned notification token is assigned, otherwise refresh can register recursively.
        Task { @MainActor [weak self] in
            guard let self, address == self.selectedDeviceAddress else { return }
            self.attempts = 0; self.manualDisconnect = false
            self.nextAttempt = Date().addingTimeInterval(1)
            self.refreshDevices(); self.updateDisconnectNotification()
        }
    }
    @objc private func bluetoothDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString
        Task { @MainActor [weak self] in
            guard let self, address == self.selectedDeviceAddress else { return }
            self.session.disconnect(); self.refreshDevices()
        }
    }
}
