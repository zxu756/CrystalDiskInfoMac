import SwiftUI

public enum SmartctlSetup {
    public static let installCommand = "brew install smartmontools"
}

public struct SmartctlSetupView: View {
    private let onRecheck: () -> Void

    public init(onRecheck: @escaping () -> Void = {}) {
        self.onRecheck = onRecheck
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("smartctl is not installed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caution)

            Text("CrystalDiskInfo Mac reads SMART data through smartctl. Install smartmontools with Homebrew:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(SmartctlSetup.installCommand)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.selectedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 12) {
                Button("Recheck", action: onRecheck)
                Link("smartmontools.org", destination: URL(string: "https://www.smartmontools.org/")!)
                    .font(.system(size: 11))
            }
        }
    }
}
