import SwiftUI
import CrystalDiskInfoMacCore

@main
struct CrystalDiskInfoMacApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .defaultSize(width: 960, height: 640)
        .windowResizability(.contentSize)
    }
}
