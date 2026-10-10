import AppKit
import SwiftUI

@main
struct OppoPodsMacApp: App {
    @StateObject private var model = AppModel()
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        Window("Enco Free4 控制", id: "settings") {
            SettingsView().environmentObject(model).environmentObject(model.session).environmentObject(model.devices)
        }.defaultSize(width: 740, height: 760)

        MenuBarExtra {
            MenuBarContentView().environmentObject(model).environmentObject(model.session).environmentObject(model.devices)
        } label: { MenuBarLabelView().environmentObject(model.session) }
        .menuBarExtraStyle(.window)
    }
}
