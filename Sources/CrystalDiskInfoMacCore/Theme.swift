import SwiftUI
import AppKit

enum Theme {
    static let background = dynamic(
        dark: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1),
        light: NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.98, alpha: 1)
    )

    static let cardBackground = dynamic(
        dark: NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 1),
        light: NSColor(calibratedWhite: 1.0, alpha: 1)
    )

    static let selectedBackground = dynamic(
        dark: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.22, alpha: 1),
        light: NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.98, alpha: 1)
    )

    static let cardBorder = dynamic(
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10),
        light: NSColor(calibratedWhite: 0.0, alpha: 0.08)
    )

    static let warningBackground = dynamic(
        dark: NSColor(calibratedRed: 0.55, green: 0.32, blue: 0.05, alpha: 0.30),
        light: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.35, alpha: 0.28)
    )

    static let accent = Color(nsColor: NSColor.systemBlue)
    static let good = Color(nsColor: NSColor.systemGreen)
    static let caution = Color(nsColor: NSColor.systemOrange)
    static let bad = Color(nsColor: NSColor.systemRed)
    static let unknown = Color(nsColor: NSColor.systemGray)

    static func healthColor(_ status: HealthStatus) -> Color {
        switch status {
        case .good: return good
        case .caution: return caution
        case .bad: return bad
        case .unknown: return unknown
        }
    }

    static func temperatureColor(
        _ temperature: Int?,
        warning: Int,
        critical: Int
    ) -> Color {
        guard let temperature else { return unknown }
        if temperature >= critical { return bad }
        if temperature >= warning { return caution }
        return accent
    }

    static func lifeColor(_ life: Int?) -> Color {
        guard let life else { return unknown }
        if life < 50 { return bad }
        if life < 80 { return caution }
        return good
    }

    private static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}
