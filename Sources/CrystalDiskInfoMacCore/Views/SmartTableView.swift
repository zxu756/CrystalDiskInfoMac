import SwiftUI
import Foundation
import Combine

public struct SmartTableRow: Identifiable, Equatable, Sendable {
    public let attribute: SmartAttribute

    public var id: Int { attribute.id }
    public var currentDisplay: String { display(attribute.current) }
    public var worstDisplay: String { display(attribute.worst) }
    public var thresholdDisplay: String { display(attribute.threshold) }
    public var isWarning: Bool { attribute.isWarning }

    public var rawDisplay: String {
        if let rawString = attribute.rawString,
           !rawString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rawString
        }
        if let rawValue = attribute.rawValue {
            return String(rawValue)
        }
        return "—"
    }

    public var currentSortValue: Int { attribute.current ?? Int.max }
    public var worstSortValue: Int { attribute.worst ?? Int.max }
    public var thresholdSortValue: Int { attribute.threshold ?? Int.max }

    public var tooltip: String {
        var lines = [
            "ID \(attribute.id) · \(attribute.name)",
            "Raw: \(rawDisplay)",
            "Prefailure: \(attribute.isPrefailure ? "Yes" : "No")",
            "At or below threshold: \(isWarning ? "Yes" : "No")"
        ]
        if let rawValue = attribute.rawValue {
            lines.append("Raw value: \(rawValue)")
        }
        return lines.joined(separator: "\n")
    }

    public init(attribute: SmartAttribute) {
        self.attribute = attribute
    }

    private func display(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }
}

public struct SmartTableView: View {
    private let rows: [SmartTableRow]
    @StateObject private var state = SmartTableState()

    public init(attributes: [SmartAttribute]) {
        self.rows = attributes.map(SmartTableRow.init)
    }

    public var body: some View {
        if rows.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SMART attributes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(rows.count) attributes")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Table(rows, sortOrder: $state.sortOrder) {
                    TableColumn("ID", value: \.id) { row in
                        HStack(spacing: 4) {
                            if row.isWarning {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.caution)
                            }

                            Text("\(row.id)")
                                .monospacedDigit()
                        }
                    }
                    .width(48)

                    TableColumn("Attribute", value: \.attribute.name) { row in
                        Text(row.attribute.name)
                            .foregroundStyle(row.isWarning ? Theme.caution : Color.primary)
                            .lineLimit(1)
                            .help(row.tooltip)
                    }
                    .width(min: 170, ideal: 240)

                    TableColumn("Current", value: \.currentSortValue) { row in
                        Text(row.currentDisplay)
                            .monospacedDigit()
                    }
                    .width(64)

                    TableColumn("Worst", value: \.worstSortValue) { row in
                        Text(row.worstDisplay)
                            .monospacedDigit()
                    }
                    .width(64)

                    TableColumn("Threshold", value: \.thresholdSortValue) { row in
                        Text(row.thresholdDisplay)
                            .monospacedDigit()
                    }
                    .width(76)

                    TableColumn("Raw", value: \.rawDisplay) { row in
                        Text(row.rawDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(row.tooltip)
                    }
                    .width(min: 160, ideal: 240)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.cardBorder)
                )
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)

            Text("No SMART attributes available")
                .font(.system(size: 13, weight: .semibold))

            Text("The drive did not return a SMART attribute table.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class SmartTableState: ObservableObject {
    @Published var sortOrder = [KeyPathComparator(\SmartTableRow.id)]
}

