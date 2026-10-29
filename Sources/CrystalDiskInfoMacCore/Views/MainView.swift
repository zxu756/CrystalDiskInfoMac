import SwiftUI

public struct MainView: View {
    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.11)
            VStack(spacing: 10) {
                Text("CrystalDiskInfo Mac")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Disk health and SMART monitor")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: 960, height: 640)
    }
}
