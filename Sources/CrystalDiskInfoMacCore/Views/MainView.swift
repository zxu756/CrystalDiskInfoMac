import SwiftUI

public struct MainView: View {
    @ObservedObject private var model: DiskMonitor

    public init(model: DiskMonitor) {
        self._model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                header

                if let error = model.errorMessage {
                    errorBanner(error, style: .warning)
                } else if let disk = model.selectedDisk, let readError = disk.readError {
                    errorBanner(readError, style: disk.health == .good ? .info : .warning)
                }

                if !model.disks.isEmpty {
                    DiskSelectorView(
                        disks: model.disks,
                        selectedID: model.selectedDiskID
                    ) { id in
                        model.selectDisk(id: id)
                    }

                    if let disk = model.selectedDisk {
                        StatusCardsView(disk: disk)
                        IdentityGridView(disk: disk)
                    }
                } else {
                    emptyState
                }

                Spacer(minLength: 0)
                footer
            }
            .padding(24)
        }
        .frame(width: 960, height: 640)
        .tint(Theme.accent)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CrystalDiskInfo Mac")
                    .font(.system(size: 20, weight: .semibold))

                Text("Disk health and SMART monitor")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(lastRefreshText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                Task { await model.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(model.isRefreshing)
        }
    }

    private var lastRefreshText: String {
        guard let lastRefresh = model.lastRefresh else {
            return "Not refreshed yet"
        }
        let style = Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            locale: Locale(identifier: "en_US")
        )
        return "Updated \(lastRefresh.formatted(style))"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)

            Text("No physical disks found")
                .font(.system(size: 15, weight: .semibold))

            Text("Connect a drive or check smartctl setup, then refresh.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String, style: BannerStyle) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.icon)
                .foregroundStyle(style.tint)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Recheck") {
                Task { await model.refresh() }
            }
            .buttonStyle(.link)
            .disabled(model.isRefreshing)
        }
        .padding(12)
        .background(style.background)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(style.tint.opacity(0.35))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            if let disk = model.selectedDisk {
                Text("\(disk.bsdName) · \(disk.model)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text("SMART data via smartctl")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

private enum BannerStyle {
    case info
    case warning

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: return Theme.accent
        case .warning: return Theme.caution
        }
    }

    var background: Color {
        switch self {
        case .info: return Theme.selectedBackground
        case .warning: return Theme.warningBackground
        }
    }
}

