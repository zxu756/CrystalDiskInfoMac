public enum HealthStatus: String, Codable, CaseIterable, Sendable {
    case good
    case caution
    case bad
    case unknown
}
