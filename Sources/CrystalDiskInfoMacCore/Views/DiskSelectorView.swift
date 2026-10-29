import SwiftUI

struct DiskSelectorView: View {
    let disks: [DiskInfo]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        if disks.count > 4 {
            ScrollView(.horizontal, showsIndicators: false) {
                row
            }
            .frame(height: 58)
        } else {
            row
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            ForEach(disks) { disk in
                Button {
                    onSelect(disk.id)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Theme.healthColor(disk.health))
                            .frame(width: 9, height: 9)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(disk.model)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)

                            Text("\(disk.bsdName) · \(disk.interfaceName)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minWidth: 190, alignment: .leading)
                    .background(
                        selectedID == disk.id
                            ? Theme.selectedBackground
                            : Theme.cardBackground
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                selectedID == disk.id
                                    ? Theme.accent.opacity(0.85)
                                    : Theme.cardBorder,
                                lineWidth: selectedID == disk.id ? 1.5 : 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(disk.model), \(disk.health.displayName)")
            }
        }
    }
}
