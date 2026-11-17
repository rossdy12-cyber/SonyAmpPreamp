import SwiftUI
import CoreBluetooth

// MARK: - Models

struct OBDDevice: Identifiable, Hashable {
    let id: UUID
    var name: String
    var rssi: Int
    var likelyOBD: Bool
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting(String)
    case initializing
    case connected
}

struct OBDSensor: Identifiable {
    let id: String          // e.g. "010C"
    let name: String
    let unit: String
    let icon: String
    var value: Double? = nil
    var raw: String = "--"
}

// MARK: - PID catalogue

struct PIDSpec {
    let pid: String          // "010C"
    let name: String
    let unit: String
    let icon: String
    let bytesNeeded: Int
    let decode: ([UInt8]) -> Double?
}

let KTM_PID_SPECS: [PIDSpec] = [
    PIDSpec(pid: "010C", name: "Engine RPM",        unit: "rpm",  icon: "tachometer",           bytesNeeded: 2, decode: { b in b.count >= 2 ? Double((Int(b[0]) << 8 | Int(b[1]))) / 4.0 : nil }),
    PIDSpec(pid: "010D", name: "Road Speed",        unit: "km/h", icon: "speedometer",          bytesNeeded: 1, decode: { b in b.count >= 1 ? Double(b[0]) : nil }),
    PIDSpec(pid: "0105", name: "Coolant Temp",      unit: "°C",   icon: "thermometer.and.liquid.waves", bytesNeeded: 1, decode: { b in b.count >= 1 ? Double(b[0]) - 40 : nil }),
    PIDSpec(pid: "015C", name: "Oil Temp",          unit: "°C",   icon: "drop.degreesign",      bytesNeeded: 1, decode: { b in b.count >= 1 ? Double(b[0]) - 40 : nil }),
    PIDSpec(pid: "010F", name: "Intake Air Temp",   unit: "°C",   icon: "wind",                 bytesNeeded: 1, decode: { b in b.count >= 1 ? Double(b[0]) - 40 : nil }),
    PIDSpec(pid: "0111", name: "Throttle Position", unit: "%",    icon: "dial.max",             bytesNeeded: 1, decode: { b in b.count >= 1 ? Double(b[0]) * 100.0 / 255.0 : nil }),
    PIDSpec(pid: "0104", name: "Engine Load",       unit: "%",    icon: "gauge.with.needle",    bytesNeeded: 1, decode: { b in b.count >= 1 ? Double(b[0]) * 100.0 / 255.0 : nil }),
    PIDSpec(pid: "010B", name: "Intake MAP",        unit: "kPa",  icon: "wind.slash",           bytesNeeded: 1, decode: { b in b.count >= 1 ? Double(b[0]) : nil }),
    PIDSpec(pid: "010A", name: "Fuel Pressure",     unit: "kPa",  icon: "drop.fill",            bytesNeeded: 1, decode: { b in b.count >= 1 ? Double(b[0]) * 3.0 : nil }),
    PIDSpec(pid: "0106", name: "Short Fuel Trim",   unit: "%",    icon: "plus.slash.minus",     bytesNeeded: 1, decode: { b in b.count >= 1 ? (Double(b[0]) - 128) * 100.0 / 128.0 : nil }),
    PIDSpec(pid: "0107", name: "Long Fuel Trim",    unit: "%",    icon: "plus.slash.minus.circle", bytesNeeded: 1, decode: { b in b.count >= 1 ? (Double(b[0]) - 128) * 100.0 / 128.0 : nil }),
    PIDSpec(pid: "0110", name: "Air Flow (MAF)",    unit: "g/s",  icon: "fan.blades",           bytesNeeded: 2, decode: { b in b.count >= 2 ? Double((Int(b[0]) << 8 | Int(b[1]))) / 100.0 : nil }),
    PIDSpec(pid: "0142", name: "Module Voltage",    unit: "V",    icon: "bolt.car",             bytesNeeded: 2, decode: { b in b.count >= 2 ? Double((Int(b[0]) << 8 | Int(b[1]))) / 1000.0 : nil }),
    PIDSpec(pid: "0131", name: "Distance Since Clear", unit: "km", icon: "road.lanes",          bytesNeeded: 2, decode: { b in b.count >= 2 ? Double((Int(b[0]) << 8 | Int(b[1]))) : nil }),
]

// MARK: - Bluetooth / ELM327 engine

final class OBDEngine: NSObject, ObservableObject {
    static let shared = OBDEngine()

    // BLE state
    @Published var bleReady = false
    @Published var bleDenied = false
    @Published var isScanning = false
    @Published var discovered: [OBDDevice] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var adapterInfo: String = ""

    // Live values
    @Published var rpm: Double? = nil
    @Published var speed: Double? = nil
    @Published var sensors: [OBDSensor] = KTM_PID_SPECS.map { OBDSensor(id: $0.pid, name: $0.name, unit: $0.unit, icon: $0.icon) }
    @Published var dtcCodes: [String] = []
    @Published var sessionMaxRPM: Double = 0
    @Published var sessionMaxSpeed: Double = 0
    @Published var supportedPIDs: Set<String> = []

    // Log
    @Published var logLines: [String] = []
    @Published var lastError: String? = nil

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var adapterServiceUUID: CBUUID?
    private var serviceForChar: CBService?

    // ELM command plumbing
    private let cmdQueue = DispatchQueue(label: "dukepulse.elm.queue", qos: .userInitiated)
    private let responseLock = NSLock()
    private var responseSemaphore = DispatchSemaphore(value: 0)
    private var responseBuffer = ""
    private var currentCommand = ""

    private var pollTimer: DispatchSourceTimer?
    private var pollIndex = 0

    // Standard OBD BLE services seen in the wild
    private let obdServiceNames: [(uuid: String, write: String, notify: String)] = [
        ("FFE0", "FFE1", "FFE1"),   // classic ELM327 mini / VEEPEAK OBD BLE
        ("FFF0", "FFF2", "FFF1"),   // Vgate iCar Pro BLE 4.0 / V-Link
        ("18F0", "2AF3", "2AF0"),   // some Anovie / KOBOBLE clones
        ("FFA0", "FFA1", "FFA1")    // rare generic
    ]

    private let knownOBDNameHints = ["OBD", "ELM", "V-LINK", "VLINK", "VGATE", "ICAR", "VEEPEAK", "OBDII", "OBD2", "OBDII", "KONNWEI", "ANCEL", "LELINK", "IOS-V", "Vgate", "IELECA"]

    // MARK: Setup

    func startBluetooth() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func appendLog(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        DispatchQueue.main.async { [weak self] in
            self?.logLines.append("[\(stamp)] \(line)")
            if let lines = self?.logLines, lines.count > 220 {
                self?.logLines.removeFirst(lines.count - 220)
            }
        }
    }

    // MARK: Scanning

    func startScan() {
        guard let central = central, central.state == .poweredOn else {
            appendLog("Bluetooth not powered on — cannot scan.")
            return
        }
        discovered.removeAll()
        isScanning = true
        // Scan for OBD service UUIDs first, plus a general sweep for unnamed adapters
        let serviceUUIDs = obdServiceNames.map { CBUUID(string: $0.uuid) }
        central.scanForPeripherals(withServices: serviceUUIDs, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        appendLog("Scanning for OBD2 BLE readers…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self = self, self.isScanning, self.discovered.isEmpty else { return }
            // Fall back to a wide scan so oddly-implemented adapters still show up
            self.central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            self.appendLog("No dedicated OBD service found yet — widening scan to all BLE devices…")
        }
    }

    func stopScan() {
        central?.stopScan()
        isScanning = false
    }

    func connect(_ device: OBDDevice) {
        guard let central = central else { return }
        stopScan()
        connectionState = .connecting(device.name)
        appendLog("Connecting to \(device.name)…")
        if let p = central.retrievePeripherals(withIdentifiers: [device.id]).first {
            peripheral = p
            p.delegate = self
            central.connect(p, options: nil)
        } else {
            appendLog("Lost handle for device — re-scan and try again.")
            connectionState = .disconnected
        }
    }

    func disconnect() {
        stopPolling()
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        connectionState = .disconnected
        appendLog("Disconnected.")
    }

    // MARK: ELM command I/O

    private func sendRaw(_ command: String, timeout: TimeInterval) -> String {
        guard let peripheral = peripheral, let writeChar = writeChar else { return "" }
        responseLock.lock()
        responseBuffer = ""
        responseLock.unlock()
        currentCommand = command
        responseSemaphore = DispatchSemaphore(value: 0)

        let payload = Data("\(command)\r".utf8)
        if writeChar.properties.contains(.write) {
            peripheral.writeValue(payload, for: writeChar, type: .withResponse)
        } else if writeChar.properties.contains(.writeWithoutResponse) {
            peripheral.writeValue(payload, for: writeChar, type: .withoutResponse)
        } else {
            peripheral.writeValue(payload, for: writeChar, type: .withResponse)
        }

        _ = responseSemaphore.wait(timeout: .now() + timeout)
        responseLock.lock()
        let out = responseBuffer
        responseLock.unlock()
        return out
    }

    private func cleanResponse(_ raw: String) -> [String] {
        let scrubbed = raw
            .replacingOccurrences(of: "SEARCHING...", with: "")
            .replacingOccurrences(of: "STOPPED", with: "")
            .replacingOccurrences(of: ">", with: "")
        return scrubbed
            .split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func sendELM(_ command: String, timeout: TimeInterval = 3.0) -> [String] {
        let raw = sendRaw(command, timeout: timeout)
        return cleanResponse(raw)
    }

    // MARK: Init + polling

    private func initializeELM() {
        DispatchQueue.main.async { [weak self] in self?.connectionState = .initializing }
        appendLog("Initialising ELM327 adapter…")

        let initSequence: [(String, TimeInterval)] = [
            ("ATZ", 3.0),      // reset
            ("ATE0", 1.5),     // echo off
            ("ATL0", 1.5),     // linefeeds off
            ("ATS0", 1.5),     // spaces off
            ("ATH0", 1.5),     // headers off
            ("ATAT1", 1.5),    // adaptive timing
            ("ATSP0", 1.5)     // auto protocol (Duke 125 = ISO 15765-4 CAN 500k 11-bit)
        ]
        for (cmd, t) in initSequence {
            let lines = sendELM(cmd, timeout: t)
            appendLog("\(cmd) → \(lines.joined(separator: " | ").isEmpty ? "ok" : lines.joined(separator: " | "))")
            if cmd == "ATZ", let first = lines.first, first.uppercased().contains("ELM") {
                adapterInfo = first
            }
        }

        // Probe supported PIDs (0100 → bitfield of 01-20)
        let probe = sendELM("0100", timeout: 4.0)
        if let resp = probe.first(where: { $0.uppercased().contains("4100") }) {
            DispatchQueue.main.async { [weak self] in self?.parseSupportedPIDs(resp) }
        }

        // Identify the ECU protocol
        let desc = sendELM("ATDP", timeout: 2.0)
        if let d = desc.first { appendLog("Protocol: \(d)") }

        appendLog("ELM327 ready. Starting live polling…")
        DispatchQueue.main.async { [weak self] in
            self?.connectionState = .connected
        }
        startPolling()
    }

    private func parseSupportedPIDs(_ line: String) {
        let hex = line.uppercased().replacingOccurrences(of: " ", with: "")
        guard let range = hex.range(of: "4100") else { return }
        let bits = String(hex[range.upperBound...]).prefix(8)
        guard bits.count == 8, let value = UInt32(bits, radix: 16) else { return }
        var found: Set<String> = []
        for (i, spec) in KTM_PID_SPECS.enumerated() where i < 32 {
            let pidNum = UInt32(spec.pid.suffix(2), radix: 16) ?? 0
            if pidNum >= 1, pidNum <= 32 {
                let bit = UInt32(1) << (32 - pidNum)
                if value & bit != 0 { found.insert(spec.pid) }
            }
        }
        if !found.isEmpty { supportedPIDs = found }
    }

    private func startPolling() {
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: cmdQueue)
        timer.schedule(deadline: .now(), repeating: 0.4)
        timer.setEventHandler { [weak self] in
            self?.pollNextSensor()
        }
        timer.resume()
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func pollNextSensor() {
        guard connectionState == .connected else { return }
        let specs = KTM_PID_SPECS
        guard !specs.isEmpty else { return }
        pollIndex = (pollIndex + 1) % specs.count
        let spec = specs[pollIndex]
        let lines = sendELM(spec.pid, timeout: 2.2)
        guard let value = decodePIDResponse(pid: spec.pid, lines: lines, spec: spec) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let idx = self.sensors.firstIndex(where: { $0.id == spec.pid }) {
                self.sensors[idx].value = value
                switch spec.unit {
                case "rpm": self.sensors[idx].raw = String(Int(value))
                case "°C", "km/h", "kPa", "g/s": self.sensors[idx].raw = String(format: "%.0f", value)
                case "%": self.sensors[idx].raw = String(format: "%.1f", value)
                case "V": self.sensors[idx].raw = String(format: "%.2f", value)
                default: self.sensors[idx].raw = String(format: "%.0f", value)
                }
            }
            switch spec.pid {
            case "010C":
                self.rpm = value
                self.sessionMaxRPM = max(self.sessionMaxRPM, value)
            case "010D":
                self.speed = value
                self.sessionMaxSpeed = max(self.sessionMaxSpeed, value)
            default:
                break
            }
        }
    }

    private func decodePIDResponse(pid: String, lines: [String], spec: PIDSpec) -> Double? {
        // With echo/spaces off the happy path is "410C1AF8"; accept spaced variants too
        for line in lines {
            var hex = line.uppercased().replacingOccurrences(of: " ", with: "")
            if hex.hasPrefix(spec.pid.uppercased() + "41") { hex = String(hex.dropFirst(spec.pid.count)) }
            guard hex.hasPrefix("41" + spec.pid.suffix(2)) else { continue }
            let payload = String(hex.dropFirst(4))
            var bytes: [UInt8] = []
            var it = payload.startIndex
            while it < payload.endIndex, bytes.count < 8 {
                let next = payload.index(it, offsetBy: 2, limitedBy: payload.endIndex) ?? payload.endIndex
                if let b = UInt8(payload[it..<next], radix: 16) { bytes.append(b) }
                it = next
            }
            guard bytes.count >= spec.bytesNeeded else { continue }
            return spec.decode(bytes)
        }
        return nil
    }

    // MARK: Fault codes

    func readFaultCodes() {
        cmdQueue.async { [weak self] in
            guard let self = self else { return }
            self.appendLog("Requesting stored fault codes (mode 03)…")
            let lines = self.sendELM("03", timeout: 4.0)
            let codes = self.parseDTCResponse(lines: lines, prefix: "43")
            DispatchQueue.main.async {
                self.dtcCodes = codes
                self.appendLog(codes.isEmpty ? "No stored fault codes found ✓" : "Found \(codes.count) fault code(s)")
            }
        }
    }

    func clearFaultCodes() {
        cmdQueue.async { [weak self] in
            guard let self = self else { return }
            self.appendLog("Clearing fault codes (mode 04)…")
            _ = self.sendELM("04", timeout: 4.0)
            DispatchQueue.main.async {
                self.dtcCodes = []
                self.appendLog("Fault codes cleared ✓")
            }
        }
    }

    private func parseDTCResponse(lines: [String], prefix: String) -> [String] {
        var hex = lines
            .map { $0.uppercased().replacingOccurrences(of: " ", with: "") }
            .filter { $0.hasPrefix(prefix) }
            .joined()
        guard hex.hasPrefix(prefix) else { return [] }
        hex = String(hex.dropFirst(2))
        var bytes: [UInt8] = []
        var it = hex.startIndex
        while it < hex.endIndex {
            let next = hex.index(it, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let b = UInt8(hex[it..<next], radix: 16) { bytes.append(b) }
            it = next
        }
        var codes: [String] = []
        var i = 0
        while i + 1 < bytes.count {
            let pair = (UInt16(bytes[i]) << 8) | UInt16(bytes[i + 1])
            i += 2
            if pair == 0 { continue }
            let letterTable = ["P", "C", "B", "U"]
            let letter = letterTable[Int((pair >> 14) & 0x3)]
            let digit1 = Int((pair >> 12) & 0x3)
            let rest = String(pair & 0x0FFF, radix: 16).uppercased()
            let padded = rest.count < 3 ? String(repeating: "0", count: 3 - rest.count) + rest : rest
            codes.append("\(letter)\(digit1)\(padded)")
        }
        return Array(Set(codes)).sorted()
    }

    // MARK: Session

    func resetSessionStats() {
        sessionMaxRPM = 0
        sessionMaxSpeed = 0
    }
}

// MARK: - CBCentralManagerDelegate

extension OBDEngine: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            bleReady = true
            bleDenied = false
            appendLog("Bluetooth powered on.")
        case .poweredOff:
            bleReady = false
            appendLog("Bluetooth is off.")
        case .unauthorized:
            bleReady = false
            bleDenied = true
            appendLog("Bluetooth permission denied — enable it in iOS Settings.")
        case .unsupported:
            bleReady = false
            appendLog("Bluetooth LE unsupported on this device.")
        default:
            bleReady = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        if let idx = discovered.firstIndex(where: { $0.id == peripheral.identifier }) {
            discovered[idx].rssi = RSSI.intValue
            return
        }
        guard name != "Unknown" else { return }
        let serviceKeys = obdServiceNames.map { "\($0.uuid)" }
        let advertised = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map { $0.uuidString } ?? []
        let likely = knownOBDNameHints.contains { name.uppercased().contains($0) } || advertised.contains { s in serviceKeys.contains(s) }
        let device = OBDDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, likelyOBD: likely)
        discovered.append(device)
        discovered.sort { a, b in
            if a.likelyOBD != b.likelyOBD { return a.likelyOBD }
            return a.rssi > b.rssi
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appendLog("Connected — discovering services…")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        appendLog("Connection failed: \(error?.localizedDescription ?? "unknown error")")
        connectionState = .disconnected
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectionState == .connected || connectionState == .initializing {
            appendLog("Adapter disconnected (\(error?.localizedDescription ?? "normal"))")
            stopPolling()
            connectionState = .disconnected
        }
    }
}

// MARK: - CBPeripheralDelegate

extension OBDEngine: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, !services.isEmpty else {
            appendLog("No services on adapter.")
            return
        }
        let wanted = obdServiceNames.map { $0.uuid }
        for service in services {
            if wanted.contains(service.uuid.uuidString) {
                adapterServiceUUID = service.uuid
                serviceForChar = service
                appendLog("Found OBD service \(service.uuid.uuidString)")
                peripheral.discoverCharacteristics(nil, for: service)
                return
            }
        }
        // Fall back to first service that has writable characteristics
        if let first = services.first {
            adapterServiceUUID = first.uuid
            serviceForChar = first
            appendLog("Using fallback service \(first.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: first)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        let serviceName = service.uuid.uuidString
        let layout = obdServiceNames.first { $0.uuid == serviceName }

        var write: CBCharacteristic?
        var notify: CBCharacteristic?

        if let l = layout {
            write = chars.first { $0.uuid.uuidString == l.write }
            notify = chars.first { $0.uuid.uuidString == l.notify }
        }
        if write == nil {
            write = chars.first { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) }
        }
        if notify == nil {
            notify = chars.first { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
        }

        guard let w = write, let n = notify else {
            appendLog("Adapter service missing write/notify characteristics.")
            return
        }

        writeChar = w
        notifyChar = n
        appendLog("Write char \(w.uuid.uuidString), notify char \(n.uuid.uuidString) — subscribing…")
        peripheral.setNotifyValue(true, for: n)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            appendLog("Subscribe failed: \(error.localizedDescription)")
            return
        }
        appendLog("Subscribed ✓ — handshaking with ELM327…")
        cmdQueue.async { [weak self] in
            self?.initializeELM()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == notifyChar, let data = characteristic.value else { return }
        let chunk = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .isoLatin1) ?? ""
        guard !chunk.isEmpty else { return }

        responseLock.lock()
        responseBuffer += chunk
        let complete = responseBuffer.contains(">")
        let current = responseBuffer
        responseLock.unlock()

        if complete {
            responseSemaphore.signal()
        }
        if chunk.contains("NO DATA") || chunk.contains("UNABLE") || chunk.contains("ERROR") {
            appendLog("ELM: \(chunk.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        _ = current
    }
}

// MARK: - DTC descriptions

let DTC_DESCRIPTIONS: [String: String] = [
    "P0087": "Fuel rail pressure too low",
    "P0106": "MAP sensor range/performance",
    "P0107": "MAP sensor circuit low",
    "P0108": "MAP sensor circuit high",
    "P0111": "Intake air temp sensor range",
    "P0112": "IAT sensor circuit low",
    "P0113": "IAT sensor circuit high",
    "P0116": "Coolant temp sensor range",
    "P0117": "Coolant temp circuit low",
    "P0118": "Coolant temp circuit high",
    "P0121": "Throttle position sensor range",
    "P0122": "TPS circuit low",
    "P0123": "TPS circuit high",
    "P0130": "O2 sensor circuit (bank 1)",
    "P0131": "O2 sensor low voltage",
    "P0132": "O2 sensor high voltage",
    "P0133": "O2 sensor slow response",
    "P0134": "O2 sensor no activity",
    "P0171": "System too lean (bank 1)",
    "P0172": "System too rich (bank 1)",
    "P0217": "Engine over-temperature",
    "P0218": "Transmission over-temperature",
    "P0230": "Fuel pump primary circuit",
    "P0261": "Cylinder 1 injector low",
    "P0262": "Cylinder 1 injector high",
    "P0264": "Cylinder 2 injector low",
    "P0265": "Cylinder 2 injector high",
    "P0300": "Random/multiple misfire",
    "P0301": "Cylinder 1 misfire",
    "P0302": "Cylinder 2 misfire",
    "P0327": "Knock sensor circuit low",
    "P0335": "Crank position sensor A",
    "P0340": "Cam position sensor circuit",
    "P0500": "Vehicle speed sensor fault",
    "P0562": "System voltage low",
    "P0563": "System voltage high",
    "P0603": "ECU keep-alive memory error",
    "P0605": "ECU read-only memory error",
    "P0650": "MIL control circuit",
    "P0700": "Transmission control system",
    "C0010": "ABS hydraulic pump circuit",
    "C0031": "Left front wheel speed sensor",
    "C0034": "Right front wheel speed sensor",
    "C0040": "Left front wheel speed sensor",
    "U0100": "Lost comm with ECM/PCM",
    "U0121": "Lost comm with ABS module",
    "U0140": "Lost comm with body control module"
]

func describeDTC(_ code: String) -> String {
    if let known = DTC_DESCRIPTIONS[code] { return known }
    guard let first = code.first else { return "Unknown fault" }
    let area: String
    switch first {
    case "P": area = "Powertrain (engine/transmission)"
    case "C": area = "Chassis (ABS/suspension)"
    case "B": area = "Body (interior/comfort)"
    case "U": area = "Network (communication)"
    default: area = "Unknown system"
    }
    return "Manufacturer-specific — \(area)"
}

// MARK: - Root app

@main
struct DukePulseApp: App {
    @StateObject private var engine = OBDEngine.shared

    var body: some Scene {
        WindowGroup {
            DukePulseRootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}

struct DukePulseRootView: View {
    @EnvironmentObject var engine: OBDEngine
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            DashboardView().tabItem { Label("Dash", systemImage: "gauge.high") }.tag(0)
            SensorsView().tabItem { Label("Sensors", systemImage: "waveform.path.ecg") }.tag(1)
            DiagnosticsView().tabItem { Label("Faults", systemImage: "wrench.and.screwdriver") }.tag(2)
            ConnectView().tabItem { Label("Connect", systemImage: "antenna.radiowaves.left.and.right") }.tag(3)
        }
        .tint(Color(red: 1.0, green: 0.42, blue: 0.04))
        .onAppear { engine.startBluetooth() }
        .background(Color(red: 0.03, green: 0.03, blue: 0.045).ignoresSafeArea())
    }
}

// MARK: - Shared UI bits

struct KTMCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.07, green: 0.07, blue: 0.095))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
    }
}

let ktmOrange = Color(red: 1.0, green: 0.42, blue: 0.04)

struct ConnectionBadge: View {
    @EnvironmentObject var engine: OBDEngine

    var text: String {
        switch engine.connectionState {
        case .disconnected: return "Not connected"
        case .connecting(let n): return "Connecting \(n)…"
        case .initializing: return "Initialising ELM327…"
        case .connected: return "Live • \(engine.adapterInfo.isEmpty ? "ELM327" : engine.adapterInfo)"
        }
    }

    var color: Color {
        switch engine.connectionState {
        case .connected: return .green
        case .disconnected: return .gray
        default: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Tab 1: Dashboard

struct DashboardView: View {
    @EnvironmentObject var engine: OBDEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        ConnectionBadge()
                        Spacer()
                        Button {
                            engine.resetSessionStats()
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle")
                                .font(.title3)
                        }
                    }
                    .padding(.horizontal, 4)

                    if engine.connectionState != .connected {
                        NotConnectedCard()
                    } else {
                        RPMSpeedGauges()
                        EngineHealthTiles()
                        SessionStatsCard()
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.03, green: 0.03, blue: 0.045).ignoresSafeArea())
            .navigationTitle("DukePulse")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct NotConnectedCard: View {
    @EnvironmentObject var engine: OBDEngine

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "motorcycle")
                .font(.system(size: 52))
                .foregroundStyle(ktmOrange)
            Text("No OBD2 reader connected")
                .font(.headline)
            Text("Plug your Bluetooth ELM327 reader into the Duke 125's 4-pin diagnostic connector under the seat, ignition ON, then connect from the Connect tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink(destination: ConnectView()) {
                Label("Find my reader", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(ktmOrange))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.095))
        )
    }
}

struct GaugeRing: View {
    let label: String
    let value: String
    let unit: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.07), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0.02, fraction))))
                    .stroke(
                        AngularGradient(colors: [color.opacity(0.45), color], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 128, height: 128)
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}

struct RPMSpeedGauges: View {
    @EnvironmentObject var engine: OBDEngine

    var body: some View {
        HStack(spacing: 14) {
            GaugeRing(
                label: "ENGINE RPM",
                value: engine.rpm.map { String(Int($0)) } ?? "--",
                unit: "rpm",
                fraction: (engine.rpm ?? 0) / 10500.0,
                color: (engine.rpm ?? 0) > 9200 ? Color.red : ktmOrange
            )
            GaugeRing(
                label: "SPEED",
                value: engine.speed.map { String(Int($0)) } ?? "--",
                unit: "km/h",
                fraction: (engine.speed ?? 0) / 160.0,
                color: .cyan
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.095))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

struct EngineHealthTiles: View {
    @EnvironmentObject var engine: OBDEngine

    var coolant: Double? { engine.sensors.first { $0.id == "0105" }?.value }
    var oil: Double? { engine.sensors.first { $0.id == "015C" }?.value }
    var throttle: Double? { engine.sensors.first { $0.id == "0111" }?.value }
    var voltage: Double? { engine.sensors.first { $0.id == "0142" }?.value }

    var coolantColor: Color {
        guard let c = coolant else { return .gray }
        if c >= 110 { return .red }
        if c >= 98 { return .orange }
        return .green
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            EngineTile(title: "Coolant", value: coolant.map { "\(Int($0))°C" } ?? "--",
                       sub: coolant.map { $0 >= 110 ? "OVERHEATING" : ($0 >= 98 ? "Running hot" : "Normal") } ?? "waiting…",
                       icon: "thermometer.and.liquid.waves", tint: coolantColor)
            EngineTile(title: "Oil Temp", value: oil.map { "\(Int($0))°C" } ?? "--",
                       sub: oil.map { $0 >= 130 ? "Very hot" : "OK" } ?? "waiting…",
                       icon: "drop.degreesign", tint: oil.map { $0 >= 130 ? Color.red : Color.green } ?? .gray)
            EngineTile(title: "Throttle", value: throttle.map { "\(Int($0))%" } ?? "--",
                       sub: throttle.map { $0 >= 95 ? "Wide open" : "Position" } ?? "waiting…",
                       icon: "dial.max", tint: ktmOrange)
            EngineTile(title: "Battery", value: voltage.map { String(format: "%.1fV", $0) } ?? "--",
                       sub: voltage.map { $0 < 12.2 ? "Low — charge it" : ($0 > 15 ? "Over-charge" : "Charging OK") } ?? "waiting…",
                       icon: "bolt.car", tint: voltage.map { $0 < 12.2 ? Color.orange : Color.green } ?? .gray)
        }
    }
}

struct EngineTile: View {
    let title: String
    let value: String
    let sub: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).font(.caption).foregroundStyle(tint)
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.heavy).monospacedDigit())
                .foregroundStyle(.white)
            Text(sub)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.095))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

struct SessionStatsCard: View {
    @EnvironmentObject var engine: OBDEngine

    var body: some View {
        KTMCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SESSION PEAKS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ktmOrange)
                    Text("Max \(Int(engine.sessionMaxRPM)) rpm • \(Int(engine.sessionMaxSpeed)) km/h")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(ktmOrange)
            }
        }
    }
}

// MARK: - Tab 2: Sensors

struct SensorsView: View {
    @EnvironmentObject var engine: OBDEngine

    var body: some View {
        NavigationStack {
            List {
                if engine.connectionState != .connected {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text("Connect an OBD2 reader to see live sensor data.")
                                .font(.footnote)
                        }
                    }
                }
                Section("Live ECU data (KTM Duke 125)") {
                    ForEach(engine.sensors) { sensor in
                        HStack {
                            Image(systemName: sensor.icon)
                                .frame(width: 30)
                                .foregroundStyle(ktmOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sensor.name)
                                    .font(.subheadline.weight(.semibold))
                                if engine.supportedPIDs.isEmpty == false,
                                   engine.supportedPIDs.contains(sensor.id) == false {
                                    Text("not supported by ECU")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Text(sensor.value == nil ? "--" : formatSensorValue(sensor))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(sensor.value == nil ? Color.gray : Color.white)
                            Text(sensor.unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .leading)
                        }
                        .listRowBackground(Color(red: 0.07, green: 0.07, blue: 0.095))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.03, green: 0.03, blue: 0.045))
            .navigationTitle("Sensors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { ConnectionBadge() }
            }
        }
    }

    private func formatSensorValue(_ s: OBDSensor) -> String {
        switch s.unit {
        case "%", "V": return String(format: "%.1f", s.value ?? 0)
        default: return String(format: "%.0f", s.value ?? 0)
        }
    }
}

// MARK: - Tab 3: Diagnostics

struct DiagnosticsView: View {
    @EnvironmentObject var engine: OBDEngine
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Button {
                            engine.readFaultCodes()
                        } label: {
                            Label("Read Codes", systemImage: "doc.text.magnifyingglass")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(ktmOrange))
                        }
                        .disabled(engine.connectionState != .connected)

                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label("Clear Codes", systemImage: "trash")
                                .font(.subheadline.weight(.bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Capsule().stroke(Color.red, lineWidth: 1.5))
                        }
                        .disabled(engine.connectionState != .connected || engine.dtcCodes.isEmpty)
                        .confirmationDialog(
                            "Clear all stored fault codes from the ECU?",
                            isPresented: $confirmClear,
                            titleVisibility: .visible
                        ) {
                            Button("Clear codes", role: .destructive) { engine.clearFaultCodes() }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This erases stored DTCs and the freeze frame. Only clear codes after fixing the fault.")
                        }
                        Spacer()
                    }

                    if engine.dtcCodes.isEmpty {
                        KTMCard {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.seal")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.green)
                                Text("No fault codes loaded")
                                    .font(.headline)
                                Text("Tap Read Codes with the bike's ignition ON to scan the ECU for stored DTCs.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                    } else {
                        ForEach(engine.dtcCodes, id: \.self) { code in
                            HStack(alignment: .top, spacing: 12) {
                                Text(code)
                                    .font(.title3.weight(.heavy).monospacedDigit())
                                    .foregroundStyle(code.hasPrefix("P") ? ktmOrange : .orange)
                                    .frame(width: 84, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(describeDTC(code))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(dtcSystemHint(code))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(red: 0.07, green: 0.07, blue: 0.095))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }

                    CommandLogCard()
                }
                .padding(16)
            }
            .background(Color(red: 0.03, green: 0.03, blue: 0.045).ignoresSafeArea())
            .navigationTitle("Faults")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func dtcSystemHint(_ code: String) -> String {
        switch code.prefix(1) {
        case "P": return "Powertrain — engine / fueling / ignition"
        case "C": return "Chassis — ABS, wheels, suspension"
        case "B": return "Body — comfort / dash systems"
        case "U": return "Network — module communication"
        default: return "Unknown"
        }
    }
}

struct CommandLogCard: View {
    @EnvironmentObject var engine: OBDEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADAPTER LOG")
                .font(.caption.weight(.bold))
                .foregroundStyle(ktmOrange)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(engine.logLines.suffix(40).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

// MARK: - Tab 4: Connect

struct ConnectView: View {
    @EnvironmentObject var engine: OBDEngine
    @State private var autoScanDone = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    connectionHeader

                    if engine.bleDenied {
                        KTMCard {
                            VStack(spacing: 8) {
                                Image(systemName: "lock.badge.clock").font(.title).foregroundStyle(.orange)
                                Text("Bluetooth permission needed").font(.headline)
                                Text("Allow Bluetooth access for DukePulse in iOS Settings → Privacy → Bluetooth.")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    if engine.connectionState == .connected || engine.connectionState == .initializing || engine.connectionState != .disconnected {
                        disconnectCard
                    } else {
                        deviceList
                        scanHelpCard
                    }
                }
                .padding(16)
            }
            .background(Color(red: 0.03, green: 0.03, blue: 0.045).ignoresSafeArea())
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                engine.startBluetooth()
                if !autoScanDone {
                    autoScanDone = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak engine] in
                        guard let engine = engine, !engine.isScanning else { return }
                        engine.startScan()
                    }
                }
            }
            .onDisappear { engine.stopScan() }
        }
    }

    private var connectionHeader: some View {
        KTMCard {
            VStack(spacing: 10) {
                Image(systemName: engine.connectionState == .connected ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(engine.connectionState == .connected ? Color.green : .gray)
                Text(engine.connectionState == .connected ? "Connected to \(engine.adapterInfo.isEmpty ? "ELM327 reader" : engine.adapterInfo)" : "Duke 125 diagnostic link")
                    .font(.headline)
                ConnectionBadge()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var disconnectCard: some View {
        KTMCard {
            Button(role: .destructive) {
                engine.disconnect()
            } label: {
                Label("Disconnect reader", systemImage: "xmark.circle")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(engine.isScanning ? "SCANNING…" : "NEARBY READERS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ktmOrange)
                Spacer()
                Button {
                    if engine.isScanning { engine.stopScan() } else { engine.startScan() }
                } label: {
                    Text(engine.isScanning ? "Stop" : "Scan")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(engine.isScanning ? Color.gray.opacity(0.3) : ktmOrange))
                        .foregroundStyle(engine.isScanning ? Color.white : Color.black)
                }
                if engine.isScanning {
                    ProgressView().controlSize(.small)
                }
            }

            if engine.discovered.isEmpty {
                KTMCard {
                    VStack(spacing: 8) {
                        ProgressView().tint(ktmOrange)
                        Text("Looking for ELM327 / Vgate / OBDII readers…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                ForEach(engine.discovered) { device in
                    Button {
                        engine.connect(device)
                    } label: {
                        HStack {
                            Image(systemName: device.likelyOBD ? "car.obd" : "flipphone")
                                .font(.title3)
                                .foregroundStyle(device.likelyOBD ? ktmOrange : .gray)
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                if device.likelyOBD {
                                    Text("OBD2 reader detected")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(ktmOrange)
                                }
                            }
                            Spacer()
                            Text("\(max(0, device.rssi)) dBm")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(red: 0.07, green: 0.07, blue: 0.095))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(device.likelyOBD ? ktmOrange.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
    }

    private var scanHelpCard: some View {
        KTMCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("HOW TO CONNECT")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(ktmOrange)
                VStack(alignment: .leading, spacing: 6) {
                    howToStep("1", "Plug the ELM327 reader into the 4-pin diagnostic connector under the Duke 125 seat / side panel.")
                    howToStep("2", "Turn the ignition ON (engine can be off) — the reader's LED should light up.")
                    howToStep("3", "Keep the reader within ~2 m for pairing, then tap it in the list above.")
                    howToStep("4", "DukePulse auto-detects the CAN protocol and starts live polling.")
                }
            }
        }
    }

    private func howToStep(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(Circle().fill(ktmOrange))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
