import SwiftUI
import AppKit
import CrystalDiskInfoMacCore

@main
struct CrystalDiskInfoMacApp: App {
    @StateObject private var monitor = DiskMonitor.live

    var body: some Scene {
        Window("CrystalDiskInfo Mac", id: "main") {
            MainView(model: monitor)
                .task {
                    await monitor.refresh()
                    monitor.startAutoRefresh()
                }
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent(monitor: monitor)
        } label: {
            MenuBarLabel(model: monitor)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsPlaceholderView()
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var monitor: DiskMonitor
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuBarView(
            model: monitor,
            onOpen: { diskID in
                if let diskID {
                    monitor.selectDisk(id: diskID)
                }
                openWindow(id: "main")
                NSApplication.shared.activate()
            },
            onSettings: {
                openSettings()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Settings")
                .font(.system(size: 16, weight: .semibold))

            Text("Settings will be available in the next task.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(width: 420, height: 260)
    }
}
