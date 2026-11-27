import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var sync: SyncManager

    @State private var showConnect = false
    @State private var showSettings = false
    @State private var showActivity = false
    @State private var expandedMachines: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                if store.machines.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(store.machines) { machine in
                        machineSection(machine)
                    }
                }
            }
            .screenBackground()
            .listStyle(.insetGrouped)
            .navigationTitle("DuoSync")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showActivity = true
                    } label: {
                        Image(systemName: "text.alignleft")
                    }
                    .accessibilityLabel("Activity")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showConnect = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Connect a PC")
                }
            }
            .refreshable {
                await sync.syncAll()
            }
            .safeAreaInset(edge: .bottom) { statusBar }
            .sheet(isPresented: $showConnect) {
                ConnectView()
                    .environmentObject(store)
                    .environmentObject(sync)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(store)
                    .environmentObject(sync)
            }
            .sheet(isPresented: $showActivity) {
                ActivityView()
                    .environmentObject(store)
            }
            .toast(message: $store.lastMessage)
        }
    }

    // MARK: - Sections

    private func machineSection(_ machine: Machine) -> some View {
        let pairs = store.pairs(for: machine.id)
        return Section {
            if pairs.isEmpty {
                HStack(spacing: 10) {
                    StatusDot(state: .idle)
                    Text("No folders paired yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.panel)
            } else {
                ForEach(pairs) { pair in
                    NavigationLink {
                        PairFilesView(pairID: pair.id)
                            .environmentObject(store)
                            .environmentObject(sync)
                    } label: {
                        PairRow(pair: pair, machine: machine, isRunning: sync.isRunning(pair.id))
                            .environmentObject(sync)
                    }
                    .listRowBackground(Theme.panel)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.removePair(pair.id)
                        } label: {
                            Label("Unpair", systemImage: "link.badge.plus")
                        }
                        Button {
                            Task { await sync.sync(pairID: pair.id) }
                        } label: {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .tint(Theme.accent)
                    }
                }
            }
        } header: {
            machineHeader(machine)
        }
    }

    private func machineHeader(_ machine: Machine) -> some View {
        HStack(spacing: 8) {
            StatusDot(state: machine.lastSeen == nil ? .error : .ok)
            Text(machine.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(machine.displayAddress)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }

    // MARK: - Chrome

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
                Text("Nothing connected yet")
                    .font(.headline)
            }
            Text("Add the PC running DuoSync, paste its pairing token, and pick the folders you want on this iPhone.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Button {
                showConnect = true
            } label: {
                Label("Connect a PC", systemImage: "plus.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.white)
            }
            Text("Both devices need to be signed into the same tailnet.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .card()
        .padding(.vertical, 8)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if sync.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
                Text("Syncing…")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Text(lastLine)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                Task { await sync.syncAll() }
            } label: {
                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .disabled(sync.isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.line), alignment: .top)
    }

    private var lastLine: String {
        guard let newest = store.pairs.compactMap(\.lastSync).max() else { return "Not synced yet" }
        return "Last sync \(relativeTime(newest))"
    }
}

// MARK: - Pair row

struct PairRow: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var sync: SyncManager

    let pair: Pair
    let machine: Machine
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(pair.shareName)
                    .font(.system(size: 15, weight: .semibold))
                if pair.mode != .twoWay {
                    Pill(text: pair.mode.label, tint: pair.mode == .pull ? Theme.warn : Theme.accent)
                }
                if pair.remoteReadOnly {
                    Pill(text: "read-only", tint: Theme.warn)
                }
                Spacer()
                if isRunning {
                    ProgressView().controlSize(.mini).tint(Theme.accent)
                }
            }
            HStack(spacing: 6) {
                Text(store.folderURL(for: pair).lastPathComponent)
                    .font(.system(size: 11, design: .monospaced))
                Text("⇄")
                    .font(.system(size: 11))
                Text(pair.shareName)
                    .font(.system(size: 11, design: .monospaced))
            }
            .foregroundStyle(Theme.muted)

            if let error = pair.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.err)
                    .lineLimit(2)
            } else {
                Text(pair.lastSync == nil ? "Not synced yet" : "\(pair.lastSummary ?? "Up to date") · \(relativeTime(pair.lastSync))")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Toast

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.panelRaised, in: Capsule())
                    .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                    .padding(.bottom, 74)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { self.message = nil }
                    .task(id: message) {
                        dismissTask?.cancel()
                        dismissTask = Task {
                            try? await Task.sleep(nanoseconds: 3_500_000_000)
                            if !Task.isCancelled { self.message = nil }
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: message)
    }
}

extension View {
    func toast(message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
