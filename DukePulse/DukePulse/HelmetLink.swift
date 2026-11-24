import SwiftUI
import CoreBluetooth
import Combine

// ============================================================
//  HELM LINK — broadcasts DukePulse telemetry to the Helmet HUD
//  BLE peripheral (phone = beacon, helmet = client).
//  Wire format: 24 bytes, 6 little-endian floats:
//    [speed, rpm, coolant, throttle, battery, shiftAt]
// ============================================================

final class HelmetLink: NSObject, ObservableObject {
    static let shared = HelmetLink()

    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let hudCharUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    @Published var isBroadcasting = false
    @Published var statusText = "Helmet link OFF"
    @Published var redlineShift: Double = 8500   // rpm shift point for the LED bar
    @Published var connectedHelmets: Int = 0

    private var peripheral: CBPeripheralManager?
    private var hudCharacteristic: CBMutableCharacteristic?
    private var sendTimer: Timer?
    private var bluetoothOn = false

    private var cancellables = Set<AnyCancellable>()

    func start() {
        if peripheral == nil {
            peripheral = CBPeripheralManager(delegate: self, queue: .main)
        } else if bluetoothOn {
            advertise()
        }
    }

    func stop() {
        sendTimer?.invalidate(); sendTimer = nil
        peripheral?.stopAdvertising()
        isBroadcasting = false
        statusText = "Helmet link OFF"
        connectedHelmets = 0
    }

    private func advertise() {
        guard let p = peripheral else { return }
        let hudChar = CBMutableCharacteristic(
            type: Self.hudCharUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [hudChar]
        hudCharacteristic = hudChar

        p.removeAllServices()
        p.add(service)
    }

    /// Pack the 24-byte telemetry frame from the live OBD engine.
    private func makePacket(from engine: OBDEngine) -> Data {
        let speed = Float(engine.speed ?? 0)
        let rpm = Float(engine.rpm ?? 0)
        let coolant = Float(engine.sensors.first(where: { $0.id == "0105" })?.value ?? 0)
        let throttle = Float(engine.sensors.first(where: { $0.id == "0111" })?.value ?? 0)
        let battery = Float(engine.sensors.first(where: { $0.id == "0142" })?.value ?? 12.6)
        let shiftAt = Float(self.redlineShift)

        var bytes = [UInt8](repeating: 0, count: 24)
        for (i, val) in [speed, rpm, coolant, throttle, battery, shiftAt].enumerated() {
            var v = val
            withUnsafeBytes(of: &v) { raw in
                for (j, b) in raw.enumerated() { bytes[i * 4 + j] = b }
            }
        }
        return Data(bytes)
    }

    private func startBroadcasting() {
        sendTimer?.invalidate()
        sendTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, let char = self.hudCharacteristic, self.isBroadcasting else { return }
            let packet = self.makePacket(from: OBDEngine.shared)
            self.peripheral?.updateValue(packet, for: char, onSubscribedCentrals: nil)
        }
        isBroadcasting = true
        statusText = "Broadcasting to helmet…"
    }
}

// MARK: - CBPeripheralManagerDelegate

extension HelmetLink: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            bluetoothOn = true
            statusText = "Bluetooth ready — starting beacon"
            advertise()
        case .poweredOff:
            bluetoothOn = false
            stop()
            statusText = "Bluetooth is OFF"
        case .unauthorized:
            stop()
            statusText = "Bluetooth permission denied"
        default:
            statusText = "Bluetooth unavailable"
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if error == nil {
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
                CBAdvertisementDataLocalNameKey: "DukePulse"
            ])
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if error == nil {
            startBroadcasting()
        } else {
            statusText = "Advertise failed: \(error?.localizedDescription ?? "?")"
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        connectedHelmets += 1
        statusText = "Helmet linked ✓ (\(connectedHelmets) device\(connectedHelmets == 1 ? "" : "s"))"
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedHelmets = max(0, connectedHelmets - 1)
        statusText = connectedHelmets > 0 ? "Helmet linked ✓ (\(connectedHelmets))" : "Broadcasting to helmet…"
    }
}

// MARK: - HELM tab UI

struct HelmetView: View {
    @EnvironmentObject var engine: OBDEngine
    @ObservedObject private var link = HelmetLink.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Link status card
                    VStack(spacing: 10) {
                        HStack {
                            Circle()
                                .fill(link.isBroadcasting ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                            Text(link.isBroadcasting ? "HELMET LINK ACTIVE" : "HELMET LINK OFF")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        Text(link.statusText)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            if link.isBroadcasting { link.stop() } else { link.start() }
                        } label: {
                            Text(link.isBroadcasting ? "STOP HELMET LINK" : "START HELMET LINK")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(link.isBroadcasting ? Color.red.opacity(0.8) : Color(red: 0.75, green: 0.1, blue: 0.15))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .padding(16)
                    .background(Color(red: 0.08, green: 0.08, blue: 0.1))
                    .cornerRadius(12)

                    // Shift point
                    VStack(spacing: 10) {
                        HStack {
                            Text("SHIFT LIGHT POINT")
                                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .foregroundColor(Color(red: 0.85, green: 0.15, blue: 0.2))
                            Spacer()
                            Text("\(Int(link.redlineShift)) rpm")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        Slider(value: $link.redlineShift, in: 5000...11000, step: 250)
                            .tint(Color(red: 0.85, green: 0.15, blue: 0.2))
                        Text("KTM Duke 125 stock: ~8500. LED bar turns amber at 85%, red at 96% of this value.")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .padding(16)
                    .background(Color(red: 0.08, green: 0.08, blue: 0.1))
                    .cornerRadius(12)

                    // Live preview of what the helmet sees
                    VStack(spacing: 10) {
                        Text("HELMET DISPLAY PREVIEW")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(Color(red: 0.85, green: 0.15, blue: 0.2))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black)
                                .frame(height: 120)
                            VStack(spacing: 4) {
                                Text(engine.connectionState == .connected ? "LINK" : "SCANNING")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.gray)
                                Text(String(format: "%3.0f", engine.speed ?? 0))
                                    .font(.system(size: 44, weight: .black, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("km/h   " + String(format: "%.0fC", engine.sensors.first(where: { $0.id == "0105" })?.value ?? 0))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Color.white, lineWidth: 1)
                                            .frame(height: 8)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(shiftColor())
                                            .frame(width: geo.size.width * rpmFraction(), height: 8)
                                    }
                                }
                                .frame(height: 8)
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(red: 0.08, green: 0.08, blue: 0.1))
                    .cornerRadius(12)
                }
                .padding(16)
            }
            .background(Color(red: 0.03, green: 0.03, blue: 0.045).ignoresSafeArea())
            .navigationTitle("Helmet HUD")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func rpmFraction() -> CGFloat {
        let rpm = engine.rpm ?? 0
        return CGFloat(min(1.0, max(0, rpm / link.redlineShift)))
    }

    private func shiftColor() -> Color {
        let frac = Double(rpmFraction())
        if frac >= 0.96 { return .red }
        if frac >= 0.85 { return .orange }
        return Color.green.opacity(0.7)
    }
}