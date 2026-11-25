import Foundation

enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case light = "Light"
    case switchDevice = "Switch"
    case sensor = "Sensor"
    case camera = "Camera"
    case thermostat = "Thermostat"
    case generic = "Generic HTTP"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .light: return "lightbulb.fill"
        case .switchDevice: return "power"
        case .sensor: return "sensor.fill"
        case .camera: return "video.fill"
        case .thermostat: return "thermometer.medium"
        case .generic: return "network"
        }
    }
}

struct SmartDevice: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var room: String
    var kind: DeviceKind
    var host: String
    var port: String
    var onURL: String
    var offURL: String
    var toggleURL: String
    var stateURL: String
    var notes: String
    var isOn: Bool = false
    var lastSeen: Date? = nil

    static func empty(room: String = "Sanctum") -> SmartDevice {
        SmartDevice(
            name: "",
            room: room,
            kind: .switchDevice,
            host: "",
            port: "80",
            onURL: "",
            offURL: "",
            toggleURL: "",
            stateURL: "",
            notes: ""
        )
    }

    var displayAddress: String {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.isEmpty { return "No address" }
        if p.isEmpty || p == "80" { return h }
        return "\(h):\(p)"
    }
}

struct DiscoveredService: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var type: String
    var host: String
    var port: Int
}

struct HAEntity: Identifiable, Codable, Equatable {
    var id: String { entityId }
    let entityId: String
    let state: String
    let friendlyName: String
    let domain: String

    var isOn: Bool {
        let s = state.lowercased()
        return s == "on" || s == "open" || s == "playing" || s == "home" || s == "unlocked"
    }

    var icon: String {
        switch domain {
        case "light": return "lightbulb.fill"
        case "switch": return "power"
        case "fan": return "fan.fill"
        case "climate": return "thermometer.medium"
        case "cover": return "curtains.closed"
        case "lock": return "lock.fill"
        case "camera": return "video.fill"
        case "sensor", "binary_sensor": return "sensor.fill"
        case "media_player": return "tv.fill"
        case "automation", "script", "scene": return "wand.and.stars"
        default: return "network"
        }
    }
}

struct CovenSettings: Codable {
    var haBaseURL: String = ""
    var haToken: String = ""
}