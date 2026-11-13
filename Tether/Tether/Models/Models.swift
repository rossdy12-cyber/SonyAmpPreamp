import Foundation
import CoreLocation

// MARK: - Members and locations

struct MemberLocation: Codable, Equatable {
    var lat: Double
    var lon: Double
    var accuracy: Double?
    var speed: Double?
    var heading: Double?
    var altitude: Double?
    var battery: Double?
    var charging: Bool?
    var activity: String?
    var ts: Double
    var placeId: String?
    var placeName: String?

    enum CodingKeys: String, CodingKey {
        case lat, lon, accuracy, speed, heading, altitude, battery, charging, activity, ts
        case placeId = "place_id"
        case placeName = "place_name"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct Member: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var color: String
    var paused: Bool
    var pausedSince: Double?
    var location: MemberLocation?

    enum CodingKeys: String, CodingKey {
        case id, name, color, paused, location
        case pausedSince = "paused_since"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "?"
        color = (try? c.decode(String.self, forKey: .color)) ?? "DC143C"
        paused = (try? c.decode(Bool.self, forKey: .paused)) ?? false
        pausedSince = try? c.decode(Double.self, forKey: .pausedSince)
        location = try? c.decode(MemberLocation.self, forKey: .location)
    }

    var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

// MARK: - Places

struct Place: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
    var radius: Double
    var icon: String
    var createdBy: String?

    enum CodingKeys: String, CodingKey {
        case id, name, lat, lon, radius, icon
        case createdBy = "created_by"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? "Place"
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        radius = (try? c.decode(Double.self, forKey: .radius)) ?? 150
        icon = (try? c.decode(String.self, forKey: .icon)) ?? "pin"
        createdBy = try? c.decode(String.self, forKey: .createdBy)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static let icons: [String] = ["home", "work", "school", "gym", "shop", "heart", "pin"]
}

// MARK: - Events

struct TetherEvent: Codable, Identifiable, Equatable {
    var id: Int
    var ts: Double
    var memberId: String
    var memberName: String
    var kind: String
    var placeId: String?
    var placeName: String?
    var lat: Double?
    var lon: Double?
    var text: String

    enum CodingKeys: String, CodingKey {
        case id, ts, kind, lat, lon, text
        case memberId = "member_id"
        case memberName = "member_name"
        case placeId = "place_id"
        case placeName = "place_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        ts = (try? c.decode(Double.self, forKey: .ts)) ?? Date().timeIntervalSince1970
        memberId = (try? c.decode(String.self, forKey: .memberId)) ?? ""
        memberName = (try? c.decode(String.self, forKey: .memberName)) ?? "Someone"
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "other"
        placeId = try? c.decode(String.self, forKey: .placeId)
        placeName = try? c.decode(String.self, forKey: .placeName)
        lat = try? c.decode(Double.self, forKey: .lat)
        lon = try? c.decode(Double.self, forKey: .lon)
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
    }

    /// Short title, matching what the server puts in a push notification.
    var headline: String {
        switch kind {
        case "arrive": return "\(memberName) arrived at \(placeName ?? "a place")"
        case "leave": return "\(memberName) left \(placeName ?? "a place")"
        case "checkin": return "\(memberName) checked in"
        case "sos": return "SOS from \(memberName)"
        case "low_battery": return "\(memberName)'s battery is low"
        case "joined": return "\(memberName) joined the circle"
        default: return memberName
        }
    }

    var hasCoordinate: Bool { lat != nil && lon != nil }
}

// MARK: - Timeline

struct TimelineItem: Codable, Identifiable {
    var type: String
    var start: Double
    var end: Double
    var lat: Double?
    var lon: Double?
    var placeId: String?
    var placeName: String?
    var distance: Double?
    var maxSpeed: Double?
    var avgSpeed: Double?
    var mode: String?
    var points: [[Double]]?

    enum CodingKeys: String, CodingKey {
        case type, start, end, lat, lon, distance, mode, points
        case placeId = "place_id"
        case placeName = "place_name"
        case maxSpeed = "max_speed"
        case avgSpeed = "avg_speed"
    }

    var id: String { "\(type)-\(Int(start))" }
    var isStay: Bool { type == "stay" }
}

struct TimelineResponse: Codable {
    var memberId: String?
    var date: String?
    var items: [TimelineItem]
    var points: [[Double]]

    enum CodingKeys: String, CodingKey {
        case date, items, points
        case memberId = "member_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberId = try? c.decode(String.self, forKey: .memberId)
        date = try? c.decode(String.self, forKey: .date)
        items = (try? c.decode([TimelineItem].self, forKey: .items)) ?? []
        points = (try? c.decode([[Double]].self, forKey: .points)) ?? []
    }
}

/// [[lat, lon, ts], ...] -> coordinates.
func coordinates(from points: [[Double]]) -> [CLLocationCoordinate2D] {
    var result: [CLLocationCoordinate2D] = []
    for p in points where p.count >= 2 {
        result.append(CLLocationCoordinate2D(latitude: p[0], longitude: p[1]))
    }
    return result
}

// MARK: - Responses

struct JoinResponse: Codable {
    var token: String
    var member: Member
}

struct CircleResponse: Codable {
    var members: [Member]
    var places: [Place]
    var serverTime: Double?

    enum CodingKeys: String, CodingKey {
        case members, places
        case serverTime = "server_time"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        members = (try? c.decode([Member].self, forKey: .members)) ?? []
        places = (try? c.decode([Place].self, forKey: .places)) ?? []
        serverTime = try? c.decode(Double.self, forKey: .serverTime)
    }
}

struct PlacesResponse: Codable {
    var places: [Place]
}

struct EventsResponse: Codable {
    var events: [TetherEvent]
    var latestId: Int

    enum CodingKeys: String, CodingKey {
        case events
        case latestId = "latest_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = (try? c.decode([TetherEvent].self, forKey: .events)) ?? []
        latestId = (try? c.decode(Int.self, forKey: .latestId)) ?? 0
    }
}

struct DatesResponse: Codable {
    var dates: [String]
}

struct OKResponse: Codable {
    var ok: Bool?
}

struct UploadResponse: Codable {
    var ok: Bool?
    var stored: Int?
}

// MARK: - Upload bodies

struct LocationIn: Codable {
    var lat: Double
    var lon: Double
    var ts: Double
    var accuracy: Double?
    var speed: Double?
    var heading: Double?
    var altitude: Double?
    var battery: Double?
    var charging: Bool?
    var activity: String?
}

struct UploadBody: Codable {
    var points: [LocationIn]
}
