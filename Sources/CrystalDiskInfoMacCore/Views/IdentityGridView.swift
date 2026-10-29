import SwiftUI

struct IdentityGridView: View {
    let disk: DiskInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drive details")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 12) {
                GridRow {
                    field("Model", disk.model)
                    field("Serial", disk.serial)
                }
                GridRow {
                    field("Firmware", disk.firmware)
                    field("Interface", "\(disk.protocolName) · \(disk.interfaceName)")
                }
                GridRow {
                    field("Capacity", capacity)
                    field("SMART status", disk.smartStatus.displayName)
                }
                GridRow {
                    field("Power on hours", disk.powerOnHours.map { "\($0.formatted()) h" } ?? "—")
                    field("Power cycles", disk.powerCycleCount.map(String.init) ?? "—")
                }
                GridRow {
                    field("Unsafe shutdowns", disk.unsafeShutdowns.map(String.init) ?? "—")
                    field("Media errors", disk.mediaErrors.map(String.init) ?? "—")
                }
            }

            if !disk.diagnostics.isEmpty {
                DisclosureGroup("Diagnostics (\(disk.diagnostics.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(disk.diagnostics.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.cardBorder))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var capacity: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(disk.capacityBytes),
            countStyle: .file
        )
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
