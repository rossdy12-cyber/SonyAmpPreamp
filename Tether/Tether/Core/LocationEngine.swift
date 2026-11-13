import Foundation
import CoreLocation
import CoreMotion
import UIKit

enum SharingMode: String, CaseIterable, Identifiable {
    case precise
    case saver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .precise: return "Precise"
        case .saver: return "Battery saver"
        }
    }

    var detail: String {
        switch self {
        case .precise: return "Best accuracy while you move (updates about every 25 m). Uses more battery."
        case .saver: return "Updates about every 100 m using significant-change and visit wake-ups. Lighter on battery."
        }
    }
}

/// Collects the phone's location in the background and hands it to the upload queue.
/// Everything here runs on the main actor; CoreLocation callbacks hop onto it.
@MainActor
final class LocationEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationEngine()

    @Published var authStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var activity: String = "unknown"
    @Published var running = false
    @Published var mode: SharingMode = .precise {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "tether.mode")
            if started { applyMode() }
        }
    }

    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private var started = false
    private var wantsAlways = false
    private var forceNext = false
    private var lowPower = false
    private var stationarySince: Date?
    private var placesSignature = ""

    private override init() {
        super.init()
        manager.delegate = self
        authStatus = manager.authorizationStatus
        if let saved = UserDefaults.standard.string(forKey: "tether.mode"), let m = SharingMode(rawValue: saved) {
            mode = m
        }
    }

    var hasAlways: Bool { authStatus == .authorizedAlways }
    var canTrack: Bool { authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse }

    // MARK: Start / stop

    /// Starts tracking if we are signed in, not paused and allowed to. Safe to call repeatedly.
    func start() {
        guard Credentials.token != nil, !Credentials.paused else { return }

        UIDevice.current.isBatteryMonitoringEnabled = true
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        manager.activityType = .otherNavigation

        authStatus = manager.authorizationStatus
        if authStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }
        guard canTrack else { return }
        if started { return }

        started = true
        running = true
        applyMode()
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
        startMotion()
    }

    func stop() {
        started = false
        running = false
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        motion.stopActivityUpdates()
        for region in manager.monitoredRegions where region.identifier.hasPrefix("tether.place.") {
            manager.stopMonitoring(for: region)
        }
        placesSignature = ""
        lowPower = false
        stationarySince = nil
    }

    /// Ask for "While Using", then "Always" (iOS only shows the second prompt after the first).
    func requestAlways() {
        switch manager.authorizationStatus {
        case .notDetermined:
            wantsAlways = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// Takes one fresh fix and uploads it straight away (used by background refresh and region events).
    func requestOneShot() {
        guard canTrack else { return }
        forceNext = true
        manager.requestLocation()
    }

    private func applyMode() {
        switch mode {
        case .precise:
            if lowPower {
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                manager.distanceFilter = 100
            } else {
                manager.desiredAccuracy = kCLLocationAccuracyBest
                manager.distanceFilter = 25
            }
        case .saver:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 100
        }
        manager.startUpdatingLocation()
    }

    // MARK: Places (region monitoring)

    /// Watches up to 20 of the circle's places so arriving or leaving wakes the app and uploads at once.
    func updatePlaces(_ places: [Place]) {
        guard started, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        let signature = places
            .map { "\($0.id):\($0.lat):\($0.lon):\($0.radius)" }
            .sorted()
            .joined(separator: "|")
        if signature == placesSignature { return }
        placesSignature = signature

        for region in manager.monitoredRegions where region.identifier.hasPrefix("tether.place.") {
            manager.stopMonitoring(for: region)
        }

        let reference = lastLocation
        let ordered = places.sorted { a, b in
            guard let ref = reference else { return a.name < b.name }
            let da = CLLocation(latitude: a.lat, longitude: a.lon).distance(from: ref)
            let db = CLLocation(latitude: b.lat, longitude: b.lon).distance(from: ref)
            return da < db
        }

        let maxRadius = manager.maximumRegionMonitoringDistance > 0 ? manager.maximumRegionMonitoringDistance : 2000
        for place in ordered.prefix(20) {
            let radius = min(max(place.radius, 100), maxRadius)
            let region = CLCircularRegion(center: place.coordinate, radius: radius, identifier: "tether.place." + place.id)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    // MARK: Motion

    private func startMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        motion.startActivityUpdates(to: OperationQueue.main) { [weak self] reading in
            guard let reading = reading else { return }
            Task { @MainActor in
                self?.handleActivity(reading)
            }
        }
    }

    private func handleActivity(_ reading: CMMotionActivity) {
        var label = "unknown"
        if reading.automotive {
            label = "driving"
        } else if reading.cycling {
            label = "cycling"
        } else if reading.running {
            label = "running"
        } else if reading.walking {
            label = "walking"
        } else if reading.stationary {
            label = "still"
        }
        if label == "unknown" { return }
        activity = label

        if label == "still" {
            if stationarySince == nil {
                let since = Date()
                stationarySince = since
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 300_000_000_000)
                    guard let self = self else { return }
                    if self.stationarySince == since && !self.lowPower && self.started {
                        self.lowPower = true
                        self.applyMode()
                    }
                }
            }
        } else {
            stationarySince = nil
            if lowPower {
                lowPower = false
                if started { applyMode() }
            }
        }
    }

    // MARK: Building points

    private func handle(_ loc: CLLocation, force: Bool) {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 1000 else { return }
        enqueue(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            ts: loc.timestamp.timeIntervalSince1970,
            accuracy: loc.horizontalAccuracy,
            speed: loc.speed >= 0 ? loc.speed : nil,
            heading: loc.course >= 0 ? loc.course : nil,
            altitude: loc.verticalAccuracy >= 0 ? loc.altitude : nil,
            force: force
        )
    }

    private func enqueue(lat: Double, lon: Double, ts: Double, accuracy: Double?, speed: Double?,
                         heading: Double?, altitude: Double?, force: Bool) {
        guard !Credentials.paused else { return }
        let level = UIDevice.current.batteryLevel
        let state = UIDevice.current.batteryState
        let point = LocationIn(
            lat: lat,
            lon: lon,
            ts: ts,
            accuracy: accuracy,
            speed: speed,
            heading: heading,
            altitude: altitude,
            battery: level >= 0 ? Double(level) : nil,
            charging: state == .charging || state == .full,
            activity: activity
        )
        let application = UIApplication.shared
        var taskId = UIBackgroundTaskIdentifier.invalid
        taskId = application.beginBackgroundTask(withName: "tether-upload") {
            application.endBackgroundTask(taskId)
        }
        Task {
            await UploadQueue.shared.add(point, force: force)
            application.endBackgroundTask(taskId)
        }
    }

    // MARK: CLLocationManagerDelegate (CoreLocation calls these off the actor, so hop back)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authStatus = manager.authorizationStatus
            if self.wantsAlways && self.authStatus == .authorizedWhenInUse {
                self.wantsAlways = false
                manager.requestAlwaysAuthorization()
            }
            if self.canTrack && !self.started {
                self.start()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let force = self.forceNext
            self.forceNext = false
            for loc in locations {
                self.handle(loc, force: force)
            }
            if let last = locations.last {
                self.lastLocation = last
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            var when = Date()
            if visit.departureDate != Date.distantFuture {
                when = visit.departureDate
            } else if visit.arrivalDate != Date.distantPast {
                when = visit.arrivalDate
            }
            let accuracy = visit.horizontalAccuracy > 0 ? visit.horizontalAccuracy : nil
            self.enqueue(
                lat: visit.coordinate.latitude,
                lon: visit.coordinate.longitude,
                ts: when.timeIntervalSince1970,
                accuracy: accuracy,
                speed: nil,
                heading: nil,
                altitude: nil,
                force: true
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            self.requestOneShot()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            self.requestOneShot()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // requestLocation() reports failures here; ongoing updates simply continue.
    }
}
