import SwiftUI
import Combine

public struct MenuBarLabelContent: Equatable, Sendable {
    public let title: String?
    public let systemImage: String

    public init(title: String?, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }
}

public enum MenuBarSummary {
    public static func hottestTemperature(in disks: [DiskInfo]) -> Int? {
        disks
            .compactMap(\.temperatureCelsius)
            .filter { (0...150).contains($0) }
            .max()
    }

    public static func label(
        for disks: [DiskInfo],
        showTemperature: Bool
    ) -> MenuBarLabelContent {
        if showTemperature, let hottest = hottestTemperature(in: disks) {
            return MenuBarLabelContent(
                title: "\(hottest)°",
                systemImage: "thermometer.medium"
            )
        }
        return MenuBarLabelContent(title: nil, systemImage: "internaldrive")
    }

    public static func diskTitle(for disk: DiskInfo) -> String {
        var parts = [disk.model, disk.health.displayName]
        if let temperature = disk.temperatureCelsius {
            parts.append("\(temperature) °C")
        }
        if let life = disk.lifePercent {
            parts.append("\(life)% life")
        }
        return parts.joined(separator: " · ")
    }
}

public struct MenuBarLabel: View {
    @ObservedObject private var model: DiskMonitor

    public init(model: DiskMonitor) {
        self._model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        if let title = content.title {
            HStack(spacing: 3) {
                Image(systemName: content.systemImage)
                Text(title)
            }
        } else {
            Image(systemName: content.systemImage)
        }
    }

    private var content: MenuBarLabelContent {
        MenuBarSummary.label(
            for: model.disks,
            showTemperature: model.settings.showMenuBarTemperature
        )
    }
}

public struct MenuBarView: View {
    @ObservedObject private var model: DiskMonitor

    private let onOpen: (String?) -> Void
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    public init(
        model: DiskMonitor,
        onOpen: @escaping (String?) -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self._model = ObservedObject(wrappedValue: model)
        self.onOpen = onOpen
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    public var body: some View {
        Group {
            ForEach(model.disks) { disk in
                Button {
                    onOpen(disk.id)
                } label: {
                    Label(
                        MenuBarSummary.diskTitle(for: disk),
                        systemImage: disk.health.symbolName
                    )
                }
            }

            if model.disks.isEmpty {
                Text("No disks found")
            }

            Divider()

            Button("Open CrystalDiskInfo Mac") {
                onOpen(nil)
            }

            Button("Refresh") {
                Task { await model.refresh() }
            }

            Button("Settings…", action: onSettings)

            Divider()

            Button("Quit CrystalDiskInfo Mac", action: onQuit)
        }
    }
}
