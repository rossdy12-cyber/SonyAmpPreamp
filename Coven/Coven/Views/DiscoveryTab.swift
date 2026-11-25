import SwiftUI

struct DiscoveryTab: View {
    @EnvironmentObject var discovery: DiscoveryService
    @EnvironmentObject var store: DeviceStore
    @State private var addedHosts: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()
                VStack(spacing: 0) {
                    if discovery.isScanning {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.crimsonBright)
                            Text("Scrying the local network...")
                                .font(Theme.serif(14, weight: .regular))
                                .foregroundColor(Theme.muted)
                        }
                        .padding(.vertical, 12)
                    }
                    if discovery.services.isEmpty && !discovery.isScanning {
                        VStack(spacing: 14) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 44))
                                .foregroundColor(Theme.crimson)
                            Text("No spirits detected")
                                .font(Theme.serif(20, weight: .semibold))
                                .foregroundColor(Theme.bone)
                            Text("Tap Scan to search for Bonjour/mDNS devices on your network. You can also add devices manually in the Coven tab.")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(discovery.services) { svc in
                                HStack(spacing: 12) {
                                    Image(systemName: "network")
                                        .foregroundColor(Theme.crimsonBright)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(svc.name)
                                            .font(Theme.serif(16, weight: .semibold))
                                            .foregroundColor(Theme.bone)
                                        Text("\(svc.host):\(svc.port)")
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.muted)
                                        Text(svc.type)
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.muted.opacity(0.8))
                                    }
                                    Spacer()
                                    let key = "\(svc.host):\(svc.port)"
                                    if addedHosts.contains(key) || store.devices.contains(where: { $0.host == svc.host && $0.port == String(svc.port) }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.crimsonBright)
                                    } else {
                                        Button("Add") {
                                            addDiscovered(svc)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(Theme.crimson)
                                    }
                                }
                                .listRowBackground(Theme.panel.opacity(0.9))
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Discovery")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(discovery.isScanning ? "Stop" : "Scan") {
                        if discovery.isScanning { discovery.stopScan() }
                        else { discovery.startScan() }
                    }
                    .foregroundColor(Theme.crimsonBright)
                }
            }
        }
        .onAppear {
            if discovery.services.isEmpty { discovery.startScan() }
        }
    }

    private func addDiscovered(_ svc: DiscoveredService) {
        let device = SmartDevice(
            name: svc.name,
            room: "Sanctum",
            kind: .generic,
            host: svc.host,
            port: String(svc.port),
            onURL: "",
            offURL: "",
            toggleURL: "",
            stateURL: "",
            notes: "Discovered via \(svc.type)"
        )
        store.add(device)
        addedHosts.insert("\(svc.host):\(svc.port)")
    }
}