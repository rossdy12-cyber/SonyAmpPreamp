import NetworkExtension
import CryptoKit
import Foundation
import Darwin

struct DirectPeerInfo {
    var vip: String
    var externalEndpoint: String
    var lanEndpoint: String
    var addr: sockaddr_in
    var verifiedAddr: sockaddr_in?
    var lastDirectPong: Date?
    var rttMs: Int?
    var role: String
    var subnets: [String]

    func isDirectActive(now: Date = Date()) -> Bool {
        guard verifiedAddr != nil, let last = lastDirectPong else { return false }
        return now.timeIntervalSince(last) < 28.0
    }
}

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let serverIP = "38.9.96.58"
    private let homeWanIP = "62.252.141.196"
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
    private var directRxPackets: UInt64 = 0
    private var directTxPackets: UInt64 = 0
    private var relayTxPackets: UInt64 = 0
    private var lastPongDate: Date?
    private var exitNodeEnabled: Bool = false
    private var clientVIP: String = "100.64.0.1"
    private var selfExternalEndpoint: String = "—"
    private var directPeers: [String: DirectPeerInfo] = [:]

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
            self.seedStaticPeers()
            self.sendHandshakePing()
            self.sendAllHolePunchPings()
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
            if cmd == "ping" || cmd == "punch" {
                ioQueue.async { [weak self] in
                    self?.sendHandshakePing()
                    self?.sendAllHolePunchPings()
                }
            }
        }
        ioQueue.async { [weak self] in
            guard let self = self else {
                completionHandler?(nil)
                return
            }
            let now = Date()
            var peersList: [[String: Any]] = []
            for vip in self.directPeers.keys.sorted() {
                guard let p = self.directPeers[vip] else { continue }
                let active = p.isDirectActive(now: now)
                peersList.append([
                    "vip": p.vip,
                    "endpoint": p.externalEndpoint,
                    "lanEndpoint": p.lanEndpoint,
                    "role": p.role,
                    "direct": active,
                    "rttMs": p.rttMs ?? -1,
                    "lastPongAgoSec": p.lastDirectPong.map { Int(now.timeIntervalSince($0)) } ?? -1,
                    "subnets": p.subnets
                ])
            }
            let activeDirectCount = peersList.filter { ($0["direct"] as? Bool) == true }.count
            let info: [String: Any] = [
                "running": self.isRunning,
                "version": "2.4.0",
                "p2pMode": "OPTION B · MULTI-PEER DIRECT UDP P2P",
                "clientVIP": self.clientVIP,
                "selfExternalEndpoint": self.selfExternalEndpoint,
                "rxBytes": self.rxBytes,
                "txBytes": self.txBytes,
                "directRxPackets": self.directRxPackets,
                "directTxPackets": self.directTxPackets,
                "relayTxPackets": self.relayTxPackets,
                "activeDirectPeers": activeDirectCount,
                "directPeers": peersList,
                "exitNodeEnabled": self.exitNodeEnabled,
                "lastPongAgoSec": self.lastPongDate.map { Int(now.timeIntervalSince($0)) } ?? -1
            ]
            let resp = try? JSONSerialization.data(withJSONObject: info)
            completionHandler?(resp)
        }
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
            NEIPv4Route(destinationAddress: serverIP, subnetMask: "255.255.255.255"),
            NEIPv4Route(destinationAddress: homeWanIP, subnetMask: "255.255.255.255")
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

    private func makeSockAddr(ip: String, port: UInt16) -> sockaddr_in? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        let ok = ip.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
        guard ok == 1 else { return nil }
        return addr
    }

    private func parseEndpoint(_ ep: String) -> (String, UInt16, sockaddr_in)? {
        let parts = ep.split(separator: ":")
        guard parts.count == 2,
              let port = UInt16(parts[1]),
              let sa = makeSockAddr(ip: String(parts[0]), port: port) else {
            return nil
        }
        return (String(parts[0]), port, sa)
    }

    private func endpointString(from addr: sockaddr_in) -> String {
        var a = addr.sin_addr
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &a, &buf, socklen_t(buf.count)) != nil else {
            return "unknown"
        }
        let ip = String(cString: buf)
        let port = UInt16(bigEndian: addr.sin_port)
        return "\(ip):\(port)"
    }

    private func seedStaticPeers() {
        // Seed TrueNAS (100.64.0.4) and Home LAN Gateway (100.64.0.2 at 62.252.141.196:41642) immediately
        if let tnAddr = makeSockAddr(ip: serverIP, port: serverPort) {
            directPeers["100.64.0.4"] = DirectPeerInfo(
                vip: "100.64.0.4",
                externalEndpoint: "\(serverIP):\(serverPort)",
                lanEndpoint: "",
                addr: tnAddr,
                verifiedAddr: tnAddr,
                lastDirectPong: Date(),
                rttMs: nil,
                role: "truenas-sanctum",
                subnets: ["100.64.0.4/32", "10.7.0.0/16"]
            )
        }
        if let homeAddr = makeSockAddr(ip: homeWanIP, port: serverPort) {
            directPeers["100.64.0.2"] = DirectPeerInfo(
                vip: "100.64.0.2",
                externalEndpoint: "\(homeWanIP):\(serverPort)",
                lanEndpoint: "192.168.0.116:41642",
                addr: homeAddr,
                verifiedAddr: nil,
                lastDirectPong: nil,
                rttMs: nil,
                role: "home-lan-p2p",
                subnets: ["192.168.0.0/24", "100.64.0.2/32", "100.64.0.3/32", "100.64.0.5/32", "100.64.0.8/32"]
            )
        }
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

        guard let addr = makeSockAddr(ip: serverIP, port: serverPort) else {
            Darwin.close(fd)
            return false
        }
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
        let now = Date()

        while true {
            var fromAddr = sockaddr_in()
            var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &fromAddr) { ptr -> Int in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    Darwin.recvfrom(udpSock, &buf, buf.count, 0, saPtr, &fromLen)
                }
            }
            if n <= 0 { break }
            let raw = Data(bytes: buf, count: n)
            guard let (ptype, pt) = decryptFrame(raw) else { continue }
            rxBytes &+= UInt64(pt.count)

            if ptype == 2 {
                // Keepalive Pong from TrueNAS
                lastPongDate = now
            } else if ptype == 4 {
                // P2P Rendezvous Peer Endpoint Table from TrueNAS
                handlePeerEndpointTable(pt, now: now)
            } else if ptype == 5, pt.count >= 12 {
                // Direct P2P UDP Hole-Punch Ping from another peer
                let senderVIP = "\(pt[8]).\(pt[9]).\(pt[10]).\(pt[11])"
                if senderVIP != clientVIP {
                    let epStr = endpointString(from: fromAddr)
                    if var existing = directPeers[senderVIP] {
                        existing.verifiedAddr = fromAddr
                        existing.externalEndpoint = epStr
                        existing.lastDirectPong = now
                        directPeers[senderVIP] = existing
                    } else {
                        directPeers[senderVIP] = DirectPeerInfo(
                            vip: senderVIP,
                            externalEndpoint: epStr,
                            lanEndpoint: "",
                            addr: fromAddr,
                            verifiedAddr: fromAddr,
                            lastDirectPong: now,
                            rttMs: nil,
                            role: "coven-peer",
                            subnets: ["\(senderVIP)/32"]
                        )
                    }
                    // Reply immediately with ptype == 6 (P2P_PUNCH_PONG) directly to fromAddr
                    var pongPayload = Data(pt.subdata(in: 0..<8))
                    var myInAddr = in_addr()
                    if clientVIP.withCString({ inet_pton(AF_INET, $0, &myInAddr) }) == 1 {
                        withUnsafeBytes(of: &myInAddr.s_addr) { pongPayload.append(contentsOf: $0) }
                    }
                    pongPayload.append(pt.subdata(in: 8..<12))
                    sendEncryptedPacket(type: 6, payload: pongPayload, to: fromAddr)
                }
            } else if ptype == 6, pt.count >= 12 {
                // Direct P2P UDP Hole-Punch Pong!
                var sentTsBE: UInt64 = 0
                _ = withUnsafeMutableBytes(of: &sentTsBE) { pt.copyBytes(to: $0, from: 0..<8) }
                let sentTsMs = UInt64(bigEndian: sentTsBE)
                let nowMs = UInt64(now.timeIntervalSince1970 * 1000)
                let rtt = max(1, Int(nowMs >= sentTsMs ? (nowMs - sentTsMs) : 1))
                let responderVIP = "\(pt[8]).\(pt[9]).\(pt[10]).\(pt[11])"
                let epStr = endpointString(from: fromAddr)

                if var existing = directPeers[responderVIP] {
                    existing.verifiedAddr = fromAddr
                    existing.externalEndpoint = epStr
                    existing.lastDirectPong = now
                    existing.rttMs = rtt
                    directPeers[responderVIP] = existing
                } else {
                    directPeers[responderVIP] = DirectPeerInfo(
                        vip: responderVIP,
                        externalEndpoint: epStr,
                        lanEndpoint: "",
                        addr: fromAddr,
                        verifiedAddr: fromAddr,
                        lastDirectPong: now,
                        rttMs: rtt,
                        role: responderVIP == "100.64.0.2" ? "home-lan-p2p" : "coven-peer",
                        subnets: ["\(responderVIP)/32"]
                    )
                }
                if responderVIP == "100.64.0.4" {
                    lastPongDate = now
                }
            } else if ptype == 3, pt.count >= 20 {
                let ver = pt[0] >> 4
                if ver == 4 {
                    let srcVIP = "\(pt[12]).\(pt[13]).\(pt[14]).\(pt[15])"
                    if var existing = directPeers[srcVIP],
                       fromAddr.sin_addr.s_addr == existing.verifiedAddr?.sin_addr.s_addr {
                        existing.lastDirectPong = now
                        directPeers[srcVIP] = existing
                    }
                    directRxPackets &+= 1
                }
                let family: Int32 = (ver == 6) ? AF_INET6 : AF_INET
                packets.append(pt)
                protos.append(NSNumber(value: family))
            }
        }

        if !packets.isEmpty {
            packetFlow.writePackets(packets, withProtocols: protos)
        }
    }

    private func handlePeerEndpointTable(_ data: Data, now: Date) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let ext = obj["ext"] as? String, !ext.isEmpty {
            selfExternalEndpoint = ext
        }
        guard let peersMap = obj["peers"] as? [String: [String: Any]] else { return }
        for (vip, pdict) in peersMap {
            if vip == clientVIP { continue }
            guard let epStr = pdict["ep"] as? String,
                  let (_, _, candidateAddr) = parseEndpoint(epStr) else { continue }
            let lanEp = (pdict["lan_ep"] as? String) ?? ""
            let role = (pdict["role"] as? String) ?? "coven-peer"
            let subnets = (pdict["subnets"] as? [String]) ?? ["\(vip)/32"]

            if var existing = directPeers[vip] {
                let epChanged = (existing.externalEndpoint != epStr)
                existing.externalEndpoint = epStr
                existing.lanEndpoint = lanEp
                existing.addr = candidateAddr
                existing.role = role
                existing.subnets = subnets
                if epChanged && vip != "100.64.0.4" {
                    existing.verifiedAddr = nil
                }
                directPeers[vip] = existing
                if epChanged || !existing.isDirectActive(now: now) {
                    sendPunchPing(toVIP: vip, addr: candidateAddr)
                }
            } else {
                let info = DirectPeerInfo(
                    vip: vip,
                    externalEndpoint: epStr,
                    lanEndpoint: lanEp,
                    addr: candidateAddr,
                    verifiedAddr: vip == "100.64.0.4" ? candidateAddr : nil,
                    lastDirectPong: vip == "100.64.0.4" ? now : nil,
                    rttMs: nil,
                    role: role,
                    subnets: subnets
                )
                directPeers[vip] = info
                sendPunchPing(toVIP: vip, addr: candidateAddr)
            }
        }
    }

    private func resolveDirectTargetVIP(forIPv4 pkt: Data) -> String? {
        guard pkt.count >= 20, (pkt[0] >> 4) == 4 else { return nil }
        let b0 = pkt[16], b1 = pkt[17], b2 = pkt[18], b3 = pkt[19]

        // MagicDNS (100.100.100.100) and SideStore TUN (10.7.0.0/16) -> TrueNAS (100.64.0.4)
        if b0 == 100 && b1 == 100 && b2 == 100 && b3 == 100 {
            return "100.64.0.4"
        }
        if b0 == 10 && b1 == 7 {
            return "100.64.0.4"
        }
        // Home LAN Subnet (192.168.0.0/24: Bedroom Apple TV .62, Cameras .41/.157, ASUS Router .116, PC .29) -> Home LAN P2P Gateway (100.64.0.2)
        if b0 == 192 && b1 == 168 && b2 == 0 {
            return "100.64.0.2"
        }
        // Headscale Mesh (100.64.0.X)
        if b0 == 100 && b1 == 64 && b2 == 0 {
            let exactVIP = "100.64.0.\(b3)"
            if let direct = directPeers[exactVIP], direct.isDirectActive() {
                return exactVIP
            }
            // Home nodes (100.64.0.2 ASUS Router, 100.64.0.3 Home PC, 100.64.0.5 Bedroom Apple TV, 100.64.0.8 Aether PC)
            if b3 == 2 || b3 == 3 || b3 == 5 || b3 == 8 {
                return "100.64.0.2"
            }
            return exactVIP
        }
        return nil
    }

    private func routeAndSendL3Packet(_ pkt: Data) {
        if let targetVIP = resolveDirectTargetVIP(forIPv4: pkt),
           let peer = directPeers[targetVIP],
           peer.isDirectActive(),
           let directAddr = peer.verifiedAddr {
            sendEncryptedPacket(type: 3, payload: pkt, to: directAddr)
            directTxPackets &+= 1
            return
        }
        // Automatic zero-drop fallback to TrueNAS Rendezvous & Core Tunnel (38.9.96.58:41642)
        sendEncryptedPacket(type: 3, payload: pkt, to: serverAddr)
        relayTxPackets &+= 1
    }

    private func startReadingFromPacketFlow() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self = self, self.isRunning else { return }
            self.ioQueue.async {
                for pkt in packets {
                    self.routeAndSendL3Packet(pkt)
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
            guard let self = self else { return }
            self.sendEncryptedPacket(type: 1, payload: payload, to: self.serverAddr)
        }
    }

    private func sendPunchPing(toVIP targetVIP: String, addr: sockaddr_in) {
        var ts = UInt64(Date().timeIntervalSince1970 * 1000).bigEndian
        var payload = Data(bytes: &ts, count: MemoryLayout<UInt64>.size)
        var myInAddr = in_addr()
        var targetInAddr = in_addr()
        guard clientVIP.withCString({ inet_pton(AF_INET, $0, &myInAddr) }) == 1,
              targetVIP.withCString({ inet_pton(AF_INET, $0, &targetInAddr) }) == 1 else {
            return
        }
        withUnsafeBytes(of: &myInAddr.s_addr) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: &targetInAddr.s_addr) { payload.append(contentsOf: $0) }
        sendEncryptedPacket(type: 5, payload: payload, to: addr)
    }

    private func sendAllHolePunchPings() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            for (vip, peer) in self.directPeers where vip != self.clientVIP {
                let targetAddr = peer.verifiedAddr ?? peer.addr
                self.sendPunchPing(toVIP: vip, addr: targetAddr)
            }
        }
    }

    private func startKeepaliveTimer() {
        let timer = DispatchSource.makeTimerSource(queue: ioQueue)
        timer.schedule(deadline: .now() + 3, repeating: 8)
        timer.setEventHandler { [weak self] in
            self?.sendHandshakePing()
            self?.sendAllHolePunchPings()
        }
        timer.resume()
        self.keepaliveTimer = timer
    }

    private func sendEncryptedPacket(type: UInt8, payload: Data, to targetAddr: sockaddr_in) {
        guard udpSock >= 0, let frame = encryptFrame(type: type, payload: payload) else { return }
        var addr = targetAddr
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
