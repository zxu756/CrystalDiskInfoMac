public enum HealthStatus: String, Codable, CaseIterable, Sendable {
    case good
    case caution
    case bad
    case unknown
}

extension HealthStatus: Comparable {
    /// `Bad > Caution > Unknown > Good`, matching the product health rule.
    private var severity: Int {
        switch self {
        case .good: return 0
        case .unknown: return 1
        case .caution: return 2
        case .bad: return 3
        }
    }

    public static func < (lhs: HealthStatus, rhs: HealthStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}
