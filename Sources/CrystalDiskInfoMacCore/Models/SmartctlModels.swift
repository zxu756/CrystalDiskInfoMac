import Foundation

/// Top-level structure emitted by `smartctl -j -a`.
///
/// Every field is optional because smartctl output varies by device type,
/// firmware, version, and permission state. A decodable report with only
/// identity fields is still useful: the domain layer decides whether it has
/// enough data to produce a health result.
public struct SmartctlReport: Codable, Sendable {
    public let jsonFormatVersion: [Int]?
    public let smartctl: SmartctlMeta?
    public let device: SmartctlDevice?
    public let modelName: String?
    public let modelFamily: String?
    public let serialNumber: String?
    public let firmwareVersion: String?
    public let userCapacity: SmartctlCapacity?
    public let rotationRate: Int?
    public let smartStatus: SmartctlStatus?
    public let temperature: SmartctlTemperature?
    public let powerOnTime: SmartctlPowerOnTime?
    public let powerCycleCount: Int64?
    public let nvmeSmartHealthInformationLog: NVMeSmartLog?
    public let ataSmartAttributes: AtaSmartAttributes?

    public static func decode(_ data: Data) throws -> SmartctlReport {
        let decoder = JSONDecoder()
        return try decoder.decode(SmartctlReport.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case jsonFormatVersion = "json_format_version"
        case smartctl
        case device
        case modelName = "model_name"
        case modelFamily = "model_family"
        case serialNumber = "serial_number"
        case firmwareVersion = "firmware_version"
        case userCapacity = "user_capacity"
        case rotationRate = "rotation_rate"
        case smartStatus = "smart_status"
        case temperature
        case powerOnTime = "power_on_time"
        case powerCycleCount = "power_cycle_count"
        case nvmeSmartHealthInformationLog = "nvme_smart_health_information_log"
        case ataSmartAttributes = "ata_smart_attributes"
    }
}

/// The `smartctl` block: tool version and process-level diagnostics.
public struct SmartctlMeta: Codable, Sendable {
    public let version: [Int]?
    public let preRelease: Bool?
    public let svnRevision: String?
    public let platformInfo: String?
    public let buildInfo: String?
    public let argv: [String]?
    public let messages: [SmartctlMessage]?
    public let exitStatus: Int?

    enum CodingKeys: String, CodingKey {
        case version
        case preRelease = "pre_release"
        case svnRevision = "svn_revision"
        case platformInfo = "platform_info"
        case buildInfo = "build_info"
        case argv
        case messages
        case exitStatus = "exit_status"
    }
}

/// A single diagnostic message from smartctl.
public struct SmartctlMessage: Codable, Sendable {
    public let string: String?
    public let severity: String?

    enum CodingKeys: String, CodingKey {
        case string
        case severity
    }
}

/// Device node and protocol information.
public struct SmartctlDevice: Codable, Sendable {
    public let name: String?
    public let infoName: String?
    public let type: String?
    public let deviceProtocol: String?

    enum CodingKeys: String, CodingKey {
        case name
        case infoName = "info_name"
        case type
        case deviceProtocol = "protocol"
    }
}

/// `user_capacity` (and ATA `capacity`) in blocks and bytes.
public struct SmartctlCapacity: Codable, Sendable {
    public let blocks: Int64?
    public let bytes: Int64?

    enum CodingKeys: String, CodingKey {
        case blocks
        case bytes
    }
}

/// Overall SMART self-assessment.
public struct SmartctlStatus: Codable, Sendable {
    public let passed: Bool?

    enum CodingKeys: String, CodingKey {
        case passed
    }
}

/// Drive-reported temperature values in degrees Celsius.
public struct SmartctlTemperature: Codable, Sendable {
    public let current: Int?
    public let opLimitMax: Int?
    public let criticalLimitMax: Int?
    public let driveTrip: Int?

    enum CodingKeys: String, CodingKey {
        case current
        case opLimitMax = "op_limit_max"
        case criticalLimitMax = "critical_limit_max"
        case driveTrip = "drive_trip"
    }
}

/// Cumulative power-on time.
public struct SmartctlPowerOnTime: Codable, Sendable {
    public let hours: Int64?

    enum CodingKeys: String, CodingKey {
        case hours
    }
}

/// NVMe SMART/Health Information log (log page 0x02).
public struct NVMeSmartLog: Codable, Sendable {
    public let nsid: Int?
    public let criticalWarning: Int?
    public let temperature: Int?
    public let availableSpare: Int?
    public let availableSpareThreshold: Int?
    public let percentageUsed: Int?
    public let dataUnitsRead: Int64?
    public let dataUnitsWritten: Int64?
    public let hostReads: Int64?
    public let hostWrites: Int64?
    public let controllerBusyTime: Int64?
    public let powerCycles: Int64?
    public let powerOnHours: Int64?
    public let unsafeShutdowns: Int64?
    public let mediaErrors: Int64?
    public let numErrLogEntries: Int64?
    public let warningTempTime: Int64?
    public let criticalCompTime: Int64?
    public let temperatureSensors: [Int]?

    enum CodingKeys: String, CodingKey {
        case nsid
        case criticalWarning = "critical_warning"
        case temperature
        case availableSpare = "available_spare"
        case availableSpareThreshold = "available_spare_threshold"
        case percentageUsed = "percentage_used"
        case dataUnitsRead = "data_units_read"
        case dataUnitsWritten = "data_units_written"
        case hostReads = "host_reads"
        case hostWrites = "host_writes"
        case controllerBusyTime = "controller_busy_time"
        case powerCycles = "power_cycles"
        case powerOnHours = "power_on_hours"
        case unsafeShutdowns = "unsafe_shutdowns"
        case mediaErrors = "media_errors"
        case numErrLogEntries = "num_err_log_entries"
        case warningTempTime = "warning_temp_time"
        case criticalCompTime = "critical_comp_time"
        case temperatureSensors = "temperature_sensors"
    }
}

/// ATA SMART attribute table.
public struct AtaSmartAttributes: Codable, Sendable {
    public let revision: Int?
    public let table: [AtaSmartAttribute]?

    enum CodingKeys: String, CodingKey {
        case revision
        case table
    }
}

/// One ATA SMART attribute row.
public struct AtaSmartAttribute: Codable, Sendable {
    public let id: Int?
    public let name: String?
    public let value: Int?
    public let worst: Int?
    public let thresh: Int?
    public let whenFailed: String?
    public let flags: AtaSmartFlags?
    public let raw: AtaSmartRaw?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case value
        case worst
        case thresh
        case whenFailed = "when_failed"
        case flags
        case raw
    }
}

/// Decoded ATA attribute flag bits plus smartctl's readable flag string.
public struct AtaSmartFlags: Codable, Sendable {
    public let value: Int?
    public let string: String?
    public let prefailure: Bool?
    public let updatedOnline: Bool?
    public let performance: Bool?
    public let errorRate: Bool?
    public let eventCount: Bool?
    public let autoKeep: Bool?

    enum CodingKeys: String, CodingKey {
        case value
        case string
        case prefailure
        case updatedOnline = "updated_online"
        case performance
        case errorRate = "error_rate"
        case eventCount = "event_count"
        case autoKeep = "auto_keep"
    }
}

/// ATA raw attribute value in both numeric and vendor-formatted forms.
public struct AtaSmartRaw: Codable, Sendable {
    public let value: Int64?
    public let string: String?

    enum CodingKeys: String, CodingKey {
        case value
        case string
    }
}
