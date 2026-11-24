import NetworkExtension
import CryptoKit
import Foundation
import Darwin

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let serverIP = "38.9.96.58"
    private let serverPort: UInt16 = 41642
    private let symmetricKey: SymmetricKey = {
        let secret = Data("bm-sanctum-7f9a3e2c8b41d0e5a6f1c9b2d8e4a7f0".utf8)
        return SymmetricKey(data: SHA256.hash(data: secret))
    }()

    private let ioQueue = DispatchQueue(label: "com.ross.bloodmesh.tunnel.io", qos: .userInteractive)
    private var udpSock: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var keepaliveTimer: DispatchSourceTimer?
    private var serverAddr = sockaddr_in()

    private var isRunning = false
    private var rxBytes: UInt64 = 0
    private var txBytes: UInt64 = 0
    private var lastPongDate: Date?
    private var exitNodeEnabled: Bool = false
    private var clientVIP: String = "100.64.0.1"

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let proto = protocolConfiguration as? NETunnelProviderProtocol
        let cfg = proto?.providerConfiguration
        if let optExit = options?["exitNode"] as? NSNumber {
            exitNodeEnabled = optExit.boolValue
        } else if let cfgExit = cfg?["exitNodeEnabled"] as? Bool {
            exitNodeEnabled = cfgExit
        } else {
            exitNodeEnabled = false
        }

        if let optVIP = options?["clientVIP"] as? NSString {
            clientVIP = String(optVIP)
        } else if let cfgVIP = cfg?["clientVIP"] as? String, !cfgVIP.isEmpty {
            clientVIP = cfgVIP
        } else {
            clientVIP = "100.64.0.1"
        }

        let settings = buildNetworkSettings(exitNode: exitNodeEnabled, vip: clientVIP)
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completionHandler(error)
                return
            }
            if !self.setupUDPSocket() {
                let err = NSError(domain: "com.ross.bloodmesh.tunnel", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize UDP socket to 38.9.96.58:41642"])
                completionHandler(err)
                return
            }
            self.isRunning = true
            self.sendHandshakePing()
            self.startKeepaliveTimer()
            self.startReadingFromPacketFlow()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        isRunning = false
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        readSource?.cancel()
        readSource = nil
        if udpSock >= 0 {
            Darwin.close(udpSock)
            udpSock = -1
        }
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if let msg = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
           let cmd = msg["cmd"] as? String {
            if cmd == "ping" {
                sendHandshakePing()
            }
        }
        let info: [String: Any] = [
            "running": isRunning,
            "rxBytes": rxBytes,
            "txBytes": txBytes,
            "exitNodeEnabled": exitNodeEnabled,
            "lastPongAgoSec": lastPongDate.map { Int(Date().timeIntervalSince($0)) } ?? -1
        ]
        let resp = try? JSONSerialization.data(withJSONObject: info)
        completionHandler?(resp)
    }

    private func buildNetworkSettings(exitNode: Bool, vip: String) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: serverIP)
        settings.mtu = 1280

        let ipv4 = NEIPv4Settings(addresses: [vip], subnetMasks: ["255.192.0.0"])
        var included: [NEIPv4Route] = [
            NEIPv4Route(destinationAddress: "100.64.0.0", subnetMask: "255.192.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.255.0"),
            NEIPv4Route(destinationAddress: "10.7.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "100.100.100.100", subnetMask: "255.255.255.255")
        ]
        if exitNode {
            included.append(NEIPv4Route.default())
        }
        ipv4.includedRoutes = included
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: serverIP, subnetMask: "255.255.255.255")
        ]
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["100.100.100.100", "1.1.1.1"])
        dns.searchDomains = ["mesh.internal"]
        if exitNode {
            dns.matchDomains = [""]
        } else {
            dns.matchDomains = ["mesh.internal"]
            dns.matchDomainsNoSearch = false
        }
        settings.dnsSettings = dns
        return settings
    }

    private func setupUDPSocket() -> Bool {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var sndBuf: Int32 = 512 * 1024
        var rcvBuf: Int32 = 512 * 1024
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sndBuf, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvBuf, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = serverPort.bigEndian
        _ = serverIP.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        self.serverAddr = addr
        self.udpSock = fd

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        src.setEventHandler { [weak self] in
            self?.drainUDPSocket()
        }
        src.resume()
        self.readSource = src
        return true
    }

    private func drainUDPSocket() {
        guard udpSock >= 0 else { return }
        var buf = [UInt8](repeating: 0, count: 65535)
        var packets: [Data] = []
        var protos: [NSNumber] = []

        while true {
            let n = Darwin.recv(udpSock, &buf, buf.count, 0)
            if n <= 0 { break }
            let raw = Data(bytes: buf, count: n)
            guard let (ptype, pt) = decryptFrame(raw) else { continue }
            rxBytes &+= UInt64(pt.count)
            if ptype == 2 {
                lastPongDate = Date()
            } else if ptype == 3, pt.count >= 20 {
                let ver = pt[0] >> 4
                let family: Int32 = (ver == 6) ? AF_INET6 : AF_INET
                packets.append(pt)
                protos.append(NSNumber(value: family))
            }
        }

        if !packets.isEmpty {
            packetFlow.writePackets(packets, withProtocols: protos)
        }
    }

    private func startReadingFromPacketFlow() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self = self, self.isRunning else { return }
            self.ioQueue.async {
                for pkt in packets {
                    self.sendEncryptedPacket(type: 3, payload: pkt)
                    self.txBytes &+= UInt64(pkt.count)
                }
            }
            if self.isRunning {
                self.startReadingFromPacketFlow()
            }
        }
    }

    private func sendHandshakePing() {
        var ts = UInt64(Date().timeIntervalSince1970 * 1000).bigEndian
        var payload = Data(bytes: &ts, count: MemoryLayout<UInt64>.size)
        var inAddr = in_addr()
        if clientVIP.withCString({ inet_pton(AF_INET, $0, &inAddr) }) == 1 {
            withUnsafeBytes(of: &inAddr.s_addr) { payload.append(contentsOf: $0) }
        }
        ioQueue.async { [weak self] in
            self?.sendEncryptedPacket(type: 1, payload: payload)
        }
    }

    private func startKeepaliveTimer() {
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + 10, repeating: 12)
        timer.setEventHandler { [weak self] in
            self?.sendHandshakePing()
        }
        timer.resume()
        self.keepaliveTimer = timer
    }

    private func sendEncryptedPacket(type: UInt8, payload: Data) {
        guard udpSock >= 0, let frame = encryptFrame(type: type, payload: payload) else { return }
        var addr = serverAddr
        frame.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    _ = Darwin.sendto(udpSock, base, frame.count, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func encryptFrame(type: UInt8, payload: Data) -> Data? {
        guard let sealed = try? ChaChaPoly.seal(payload, using: symmetricKey) else { return nil }
        var out = Data(capacity: 3 + sealed.combined.count)
        out.append(0x42) // 'B'
        out.append(0x4D) // 'M'
        out.append(type)
        out.append(sealed.combined)
        return out
    }

    private func decryptFrame(_ frame: Data) -> (UInt8, Data)? {
        guard frame.count >= 31, frame[0] == 0x42, frame[1] == 0x4D else { return nil }
        let ptype = frame[2]
        let combined = frame.subdata(in: 3..<frame.count)
        guard let box = try? ChaChaPoly.SealedBox(combined: combined),
              let pt = try? ChaChaPoly.open(box, using: symmetricKey) else {
            return nil
        }
        return (ptype, pt)
    }
}
