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
            SettingsContainer(monitor: monitor)
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

private struct SettingsContainer: View {
    @ObservedObject var monitor: DiskMonitor

    var body: some View {
        SettingsView(
            settings: monitor.settings,
            smartctlStatus: monitor.smartctlStatus,
            onRecheck: {
                Task { await monitor.refresh() }
            },
            onSave: { settings in
                monitor.apply(settings: settings)
                NSApplication.shared.keyWindow?.close()
            },
            onCancel: {
                NSApplication.shared.keyWindow?.close()
            }
        )
    }
}
