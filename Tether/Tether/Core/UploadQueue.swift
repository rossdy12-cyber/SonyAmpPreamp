import Foundation

/// Location points waiting to be uploaded. Saved to disk after every change so nothing is lost
/// when the phone is offline or the app is killed; sent oldest-first in batches with backoff.
actor UploadQueue {
    static let shared = UploadQueue()

    private var points: [LocationIn] = []
    private var loaded = false
    private var flushing = false
    private var failures = 0
    private var nextAttempt = Date.distantPast
    private var lastFlush = Date.distantPast
    private var delayedScheduled = false

    private let maxPoints = 5000
    private let minInterval: TimeInterval = 10

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("tether-queue.json")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([LocationIn].self, from: data) {
            points = stored
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(points) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    var pendingCount: Int {
        load()
        return points.count
    }

    /// Adds a point and uploads soon (at most once every 10 s, or at once when `force` is set).
    func add(_ point: LocationIn, force: Bool) async {
        load()
        points.append(point)
        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }
        save()

        if force || Date().timeIntervalSince(lastFlush) >= minInterval {
            await flush(force: force)
        } else if !delayedScheduled {
            delayedScheduled = true
            Task { [self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await self.delayedFlush()
            }
        }
    }

    private func delayedFlush() async {
        delayedScheduled = false
        await flush(force: false)
    }

    /// Uploads everything waiting. `force` ignores the retry backoff.
    func flush(force: Bool = false) async {
        load()
        guard !flushing, !points.isEmpty else { return }
        if !force && Date() < nextAttempt { return }
        guard let api = Credentials.api, !Credentials.paused else { return }

        flushing = true
        defer { flushing = false }

        while !points.isEmpty {
            let batch = Array(points.prefix(200)).sorted { $0.ts < $1.ts }
            let sent = min(batch.count, points.count)
            guard let body = APIClient.encode(UploadBody(points: batch)) else {
                points.removeFirst(sent)
                save()
                continue
            }
            do {
                _ = try await api.call("POST", "/v1/location", json: body, as: UploadResponse.self, timeout: 25)
                points.removeFirst(min(sent, points.count))
                save()
                failures = 0
                lastFlush = Date()
            } catch APIError.unauthorized {
                NotificationCenter.default.post(name: .tetherUnauthorized, object: nil)
                return
            } catch APIError.server(let status, _, _) where status == 422 || status == 413 {
                // The server will never accept this batch; drop it rather than retry forever.
                points.removeFirst(min(sent, points.count))
                save()
            } catch {
                failures += 1
                let wait = min(300.0, 5.0 * pow(2.0, Double(min(failures, 6))))
                nextAttempt = Date().addingTimeInterval(wait)
                return
            }
        }
    }

    func clear() {
        points.removeAll()
        loaded = true
        failures = 0
        nextAttempt = Date.distantPast
        try? FileManager.default.removeItem(at: fileURL)
    }
}
