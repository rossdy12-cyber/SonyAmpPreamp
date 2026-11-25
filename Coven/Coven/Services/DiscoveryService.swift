import Foundation
import Combine

final class DiscoveryService: NSObject, ObservableObject {
    @Published var services: [DiscoveredService] = []
    @Published var isScanning = false

    private var browsers: [NetServiceBrowser] = []
    private var resolving: [NetService] = []
    private let serviceTypes = ["_http._tcp.", "_https._tcp.", "_homekit._tcp.", "_hap._tcp.", "_googlecast._tcp.", "_shelly._tcp.", "_esphomelib._tcp.", "_home-assistant._tcp."]

    func startScan() {
        stopScan()
        DispatchQueue.main.async {
            self.services = []
            self.isScanning = true
        }
        for type in serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(browser)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.stopScan()
        }
    }

    func stopScan() {
        browsers.forEach { $0.stop() }
        browsers.removeAll()
        resolving.forEach { $0.stop() }
        resolving.removeAll()
        DispatchQueue.main.async {
            self.isScanning = false
        }
    }
}

extension DiscoveryService: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolving.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        DispatchQueue.main.async {
            self.isScanning = false
        }
    }
}

extension DiscoveryService: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
        let port = sender.port
        guard !host.isEmpty, port > 0 else { return }
        let found = DiscoveredService(name: sender.name, type: sender.type, host: host, port: port)
        DispatchQueue.main.async {
            if !self.services.contains(where: { $0.host == found.host && $0.port == found.port && $0.name == found.name }) {
                self.services.append(found)
                self.services.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        resolving.removeAll { $0 == sender }
    }
}