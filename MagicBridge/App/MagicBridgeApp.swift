import SwiftUI

@main
struct MagicBridgeApp: App {
    @StateObject private var model = BridgeViewModel()

    var body: some Scene {
        WindowGroup {
            BridgeView()
                .environmentObject(model)
                .frame(minWidth: 560, minHeight: 420)
        }
        .defaultSize(width: 720, height: 520)

        MenuBarExtra("Magic Bridge", systemImage: "link.badge.plus") {
            Button("修复 Apple 备忘录清单") {
                model.repairAppleNotesChecklists()
            }
            .disabled(model.isBusy)

            Divider()

            Button("打开 Magic Bridge") {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}
