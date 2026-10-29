import SwiftUI
import CrystalDiskInfoMacCore

@main
struct CrystalDiskInfoMacApp: App {
    @StateObject private var monitor = DiskMonitor.live

    var body: some Scene {
        WindowGroup {
            MainView(model: monitor)
                .task {
                    await monitor.refresh()
                    monitor.startAutoRefresh()
                }
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentSize)
    }
}
