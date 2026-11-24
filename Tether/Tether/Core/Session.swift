import Foundation
import SwiftUI
import UIKit
import CoreLocation

/// Everything the screens need: who we are, the circle, places and events, plus the server calls.
@MainActor
final class Session: ObservableObject {
    static let shared = Session()

    @Published private(set) var signedIn: Bool = Credentials.token != nil
    @Published var me: Member?
    @Published var members: [Member] = []
    @Published var places: [Place] = []
    @Published var events: [TetherEvent] = []
    @Published var paused: Bool = Credentials.paused
    @Published var selectedTab: Int = 0
    /// Set to centre the map on a member (from the timeline, a notification or an event).
    @Published var focusMemberId: String?
    @Published var focusCoordinate: CLLocationCoordinate2D?
    /// Bumped on every focus request so the map can react even to the same member twice.
    @Published var focusTick: Int = 0
    /// Set to open the timeline for a member.
    @Published var timelineMemberId: String?
    @Published var sosActive = false
    @Published var sosAlert: TetherEvent?
    @Published var banner: String?

    private var pollTask: Task<Void, Never>?
    private var unauthorizedObserver: NSObjectProtocol?

    private init() {
        unauthorizedObserver = NotificationCenter.default.addObserver(
            forName: .tetherUnauthorized, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAuthFailure()
            }
        }
    }

    // MARK: Requests

    /// Runs a server call with our token; signs out if the server rejects it.
    func request<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [(String, String)] = [],
        json: Data? = nil,
        as type: T.Type
    ) async throws -> T {
        guard let api = Credentials.api else { throw APIError.unauthorized }
        do {
            return try await api.call(method, path, query: query, json: json, as: type)
        } catch APIError.unauthorized {
            handleAuthFailure()
            throw APIError.unauthorized
        }
    }

    func show(_ error: Error) {
        showMessage(error.localizedDescription)
    }

    func showMessage(_ text: String) {
        banner = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self?.banner == text { self?.banner = nil }
        }
    }

    // MARK: Joining and leaving

    func join(server: String, code: String, name: String, color: String) async throws {
        guard let base = APIClient.normalize(server) else { throw APIError.badURL }
        let client = APIClient(base: base, token: nil)
        let body = APIClient.json(["code": code, "name": name, "color": color])
        let response = try await client.call("POST", "/v1/join", json: body, as: JoinResponse.self)
        Credentials.serverURL = base.absoluteString
        Credentials.token = response.token
        Credentials.paused = false
        UserDefaults.standard.removeObject(forKey: "tether.lastEvent")
        me = response.member
        paused = false
        signedIn = true
        startServices()
        LocationEngine.shared.requestAlways()
    }

    /// Leaves the circle on the server, then signs out here.
    func leaveCircle() async {
        do {
            _ = try await request("DELETE", "/v1/me", as: OKResponse.self)
        } catch APIError.unauthorized {
            // Already signed out.
        } catch {
            show(error)
            return
        }
        signOutLocally()
    }

    func handleAuthFailure() {
        guard signedIn else { return }
        signOutLocally()
        showMessage("You've been signed out. Join the circle again.")
    }

    private func signOutLocally() {
        stopPolling()
        LocationEngine.shared.stop()
        Credentials.token = nil
        Credentials.paused = false
        UserDefaults.standard.removeObject(forKey: "tether.lastEvent")
        Task { await UploadQueue.shared.clear() }
        me = nil
        members = []
        places = []
        events = []
        paused = false
        sosActive = false
        sosAlert = nil
        selectedTab = 0
        signedIn = false
    }

    // MARK: Lifecycle

    /// Called when the app opens or becomes active while signed in.
    func startServices() {
        guard signedIn else { return }
        LocationEngine.shared.start()
        LocationEngine.shared.requestOneShot()
        Notifier.shared.registerForPushIfAllowed()
        startPolling()
        Task {
            await UploadQueue.shared.flush(force: true)
            await registerDevice()
        }
    }

    func startPolling() {
        guard signedIn, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                await self.refreshAll()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshAll() async {
        guard signedIn else { return }
        LocationEngine.shared.requestOneShot()
        await UploadQueue.shared.flush(force: true)
        await refreshMe()
        await refreshCircle()
        await refreshEvents(notify: false)
    }

    /// One pass for a background wake-up: upload what's queued, then look for new events.
    func backgroundSync() async {
        guard signedIn else { return }
        LocationEngine.shared.requestOneShot()
        await UploadQueue.shared.flush(force: true)
        await refreshCircle()
        await refreshEvents(notify: true)
    }

    // MARK: Data

    func refreshMe() async {
        do {
            let value = try await request("GET", "/v1/me", as: Member.self)
            me = value
            paused = value.paused
            Credentials.paused = value.paused
            if value.paused { LocationEngine.shared.stop() }
        } catch {
            // The circle refresh below reports connection problems.
        }
    }

    func refreshCircle() async {
        do {
            let circle = try await request("GET", "/v1/circle", as: CircleResponse.self)
            members = circle.members
            places = circle.places
            LocationEngine.shared.updatePlaces(circle.places)
        } catch APIError.unauthorized {
            // handled in request()
        } catch {
            // Keep showing the last known circle while offline.
        }
    }

    func refreshEvents(notify: Bool) async {
        let defaults = UserDefaults.standard
        let baseline: Int? = defaults.object(forKey: "tether.lastEvent") == nil ? nil : defaults.integer(forKey: "tether.lastEvent")
        let since = events.last?.id ?? 0
        do {
            let result = try await request(
                "GET", "/v1/events",
                query: [("since", String(since)), ("limit", "50")],
                as: EventsResponse.self
            )
            let known = Set(events.map { $0.id })
            let fresh = result.events.filter { !known.contains($0.id) }
            if !fresh.isEmpty {
                var merged = events + fresh
                merged.sort { $0.id < $1.id }
                if merged.count > 200 { merged.removeFirst(merged.count - 200) }
                events = merged
            }
            let newest = max(result.latestId, events.last?.id ?? 0)
            defaults.set(newest, forKey: "tether.lastEvent")
            if let baseline = baseline {
                for event in fresh where event.id > baseline && event.memberId != me?.id {
                    handleIncoming(event, notify: notify)
                }
            }
        } catch {
            // Offline: try again on the next poll.
        }
    }

    private func handleIncoming(_ event: TetherEvent, notify: Bool) {
        let active = UIApplication.shared.applicationState == .active
        if event.kind == "sos" && active {
            sosAlert = event
            return
        }
        if notify && !active && Credentials.localAlerts {
            Notifier.shared.notify(event)
        }
    }

    func registerDevice() async {
        guard signedIn, let token = Credentials.apnsToken else { return }
        let body = APIClient.json(["apns_token": token, "environment": "development"])
        do {
            _ = try await request("POST", "/v1/device", json: body, as: OKResponse.self)
        } catch {
            // Retried the next time the app starts.
        }
    }

    // MARK: Profile

    func updateProfile(name: String? = nil, color: String? = nil) async -> Bool {
        var body: [String: Any] = [:]
        if let name = name { body["name"] = name }
        if let color = color { body["color"] = color }
        do {
            me = try await request("PATCH", "/v1/me", json: APIClient.json(body), as: Member.self)
            await refreshCircle()
            return true
        } catch {
            show(error)
            return false
        }
    }

    func setPaused(_ value: Bool) async {
        do {
            let updated = try await request("PATCH", "/v1/me", json: APIClient.json(["paused": value]), as: Member.self)
            me = updated
            paused = updated.paused
            Credentials.paused = updated.paused
            if updated.paused {
                LocationEngine.shared.stop()
            } else {
                LocationEngine.shared.start()
            }
            await refreshCircle()
        } catch {
            paused = !value
            show(error)
        }
    }

    // MARK: Places

    func savePlace(id: String?, name: String, coordinate: CLLocationCoordinate2D, radius: Double, icon: String) async -> Bool {
        let body = APIClient.json([
            "name": name,
            "lat": coordinate.latitude,
            "lon": coordinate.longitude,
            "radius": radius,
            "icon": icon
        ])
        do {
            if let id = id {
                _ = try await request("PATCH", "/v1/places/\(id)", json: body, as: Place.self)
            } else {
                _ = try await request("POST", "/v1/places", json: body, as: Place.self)
            }
            await refreshCircle()
            return true
        } catch {
            show(error)
            return false
        }
    }

    func deletePlace(_ place: Place) async {
        do {
            _ = try await request("DELETE", "/v1/places/\(place.id)", as: OKResponse.self)
            places.removeAll { $0.id == place.id }
            await refreshCircle()
        } catch {
            show(error)
        }
    }

    // MARK: Check-in and SOS

    func checkIn(text: String) async {
        LocationEngine.shared.requestOneShot()
        await UploadQueue.shared.flush(force: true)
        var body: [String: Any] = [:]
        if !text.isEmpty { body["text"] = text }
        if let loc = LocationEngine.shared.lastLocation ?? CLLocationManager().location {
            body["lat"] = loc.coordinate.latitude
            body["lon"] = loc.coordinate.longitude
        }
        do {
            _ = try await request("POST", "/v1/checkin", json: APIClient.json(body), as: TetherEvent.self)
            showMessage("Checked in.")
            await refreshCircle()
            await refreshEvents(notify: false)
        } catch {
            show(error)
        }
    }

    func sendSOS() async {
        guard let loc = LocationEngine.shared.lastLocation ?? CLLocationManager().location else {
            showMessage("Can't send SOS yet: no location fix. Check location permission.")
            return
        }
        let body = APIClient.json([
            "lat": loc.coordinate.latitude,
            "lon": loc.coordinate.longitude,
            "text": "SOS"
        ])
        do {
            _ = try await request("POST", "/v1/sos", json: body, as: TetherEvent.self)
            sosActive = true
            LocationEngine.shared.requestOneShot()
            await refreshEvents(notify: false)
        } catch {
            show(error)
        }
    }

    func cancelSOS() async {
        do {
            _ = try await request("POST", "/v1/sos/cancel", json: APIClient.json([:]), as: OKResponse.self)
            sosActive = false
            showMessage("SOS cancelled.")
        } catch {
            show(error)
        }
    }

    // MARK: Helpers

    func member(withId id: String) -> Member? {
        members.first { $0.id == id }
    }

    func focus(onMember id: String) {
        focusCoordinate = nil
        focusMemberId = id
        focusTick += 1
        selectedTab = 0
    }

    func focus(on coordinate: CLLocationCoordinate2D) {
        focusMemberId = nil
        focusCoordinate = coordinate
        focusTick += 1
        selectedTab = 0
    }
}
