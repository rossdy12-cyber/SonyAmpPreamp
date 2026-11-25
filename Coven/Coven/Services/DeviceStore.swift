import Foundation
import Combine

@MainActor
final class DeviceStore: ObservableObject {
    @Published var devices: [SmartDevice] = []
    @Published var rooms: [String] = ["Sanctum", "Crypt", "Chamber", "Vault"]

    private let fileURL: URL
    private let roomsURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("coven_devices.json")
        roomsURL = docs.appendingPathComponent("coven_rooms.json")
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([SmartDevice].self, from: data) {
            devices = decoded
        }
        if let data = try? Data(contentsOf: roomsURL),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            rooms = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(devices) {
            try? data.write(to: fileURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(rooms) {
            try? data.write(to: roomsURL, options: .atomic)
        }
    }

    func add(_ device: SmartDevice) {
        devices.append(device)
        ensureRoom(device.room)
        save()
    }

    func update(_ device: SmartDevice) {
        if let idx = devices.firstIndex(where: { $0.id == device.id }) {
            devices[idx] = device
            ensureRoom(device.room)
            save()
        }
    }

    func delete(_ device: SmartDevice) {
        devices.removeAll { $0.id == device.id }
        save()
    }

    func delete(at offsets: IndexSet, in room: String) {
        let roomDevices = devices.filter { $0.room == room }
        let ids = offsets.map { roomDevices[$0].id }
        devices.removeAll { ids.contains($0.id) }
        save()
    }

    func ensureRoom(_ room: String) {
        let trimmed = room.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !rooms.contains(trimmed) {
            rooms.append(trimmed)
            save()
        }
    }

    func devices(in room: String) -> [SmartDevice] {
        devices.filter { $0.room == room }
    }
}