import SwiftUI

struct StealthDecoyView: View {
    @EnvironmentObject var store: StudioStore
    @State private var pingMs: Double = 12.4
    @State private var cpuLoad: Int = 14
    @State private var isRunningSweep: Bool = false
    @State private var portInput: String = ""
    @State private var sweepLog: [String] = [
        "[OK] en0 Wi-Fi link active (MTU 1500)",
        "[OK] utun3 Tailscale tunnel 100.85.127.42 reachable",
        "[OK] ZFS storage_pool scrub status: HEALTHY (0 errors)",
        "[OK] Kernel thermal pressure: NOMINAL (34.2°C)"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Secret Unlock Trigger: Long-press for 0.7s OR triple-tap this status header
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 9, height: 9)
                        Text("CoreDiag v2.1 • KERNEL OK")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Spacer()
                        Text("NODE: 100.85.127.42")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(14)
                    .background(Color(red: 0.08, green: 0.11, blue: 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onLongPressGesture(minimumDuration: 0.7) {
                        store.unlockWithBiometrics { _ in }
                    }
                    .onTapGesture(count: 3) {
                        store.unlockWithBiometrics { _ in }
                    }

                    // Telemetry Metric Cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricTile(title: "ICMP LATENCY", value: String(format: "%.1f ms", pingMs), subtitle: "Jitter: 0.8 ms", color: .cyan)
                        metricTile(title: "CPU CORE LOAD", value: "\(cpuLoad)%", subtitle: "6 Cores Idle", color: .green)
                        metricTile(title: "PACKET LOSS", value: "0.00%", subtitle: "512 / 512 frames", color: .mint)
                        metricTile(title: "MEMORY PAGES", value: "4.2 GB", subtitle: "Compressed: 310 MB", color: .blue)
                    }

                    // Sweep Log Console
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INTERFACE DIAGNOSTIC LOG")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(sweepLog, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color(red: 0.65, green: 0.88, blue: 0.75))
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(14)
                    .background(Color(red: 0.08, green: 0.11, blue: 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        runFakeSweep()
                    } label: {
                        HStack {
                            if isRunningSweep {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "waveform.path.ecg")
                            }
                            Text(isRunningSweep ? "Running ICMP Sweep..." : "Run Diagnostics Sweep")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.05, green: 0.45, blue: 0.68))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Discreet PIN / Port Override (Entering secret PIN e.g. 2070 unlocks immediately)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CUSTOM PROBE PORT / OVERRIDE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        HStack(spacing: 8) {
                            SecureField("Port (Default: 18998)", text: $portInput)
                                .keyboardType(.numbersAndPunctuation)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(9)
                                .background(Color.black.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onSubmit {
                                    checkPinOverride()
                                }
                            Button("Probe") {
                                checkPinOverride()
                            }
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(14)
                    .background(Color(red: 0.08, green: 0.11, blue: 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
            .background(Color(red: 0.04, green: 0.06, blue: 0.09).ignoresSafeArea())
            .navigationTitle("CoreDiag")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func metricTile(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
            Text(subtitle)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(red: 0.08, green: 0.11, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func runFakeSweep() {
        isRunningSweep = true
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            pingMs = Double.random(in: 10.8...15.9)
            cpuLoad = Int.random(in: 9...22)
            sweepLog.append("[OK] ICMP echo 64 bytes from 100.85.127.42: time=\(String(format: "%.1f", pingMs)) ms")
            if sweepLog.count > 7 {
                sweepLog.removeFirst()
            }
            isRunningSweep = false
        }
    }

    private func checkPinOverride() {
        if store.tryUnlockWithPin(portInput) {
            portInput = ""
        } else {
            sweepLog.append("[OK] Port \(portInput.isEmpty ? "18998" : portInput) SYN_ACK received (0.4 ms)")
            portInput = ""
        }
    }
}
