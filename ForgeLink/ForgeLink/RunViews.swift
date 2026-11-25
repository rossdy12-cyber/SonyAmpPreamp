import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedRun: Run?
    @State private var filter = "All"
    private var filtered: [Run] { filter == "Active" ? model.runs.filter(\.isActive) : model.runs }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Filter runs", selection: $filter) {
                        Text("All runs").tag("All")
                        Text("Active").tag("Active")
                    }.pickerStyle(.segmented)
                    if filtered.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "terminal").font(.system(size: 40)).foregroundStyle(Forge.mint)
                            Text(filter == "Active" ? "Nothing running" : "A clean slate").font(.title3.bold())
                            Text("Send an agent task or run a saved command from Workspace. Results are kept on your bridge.").multilineTextAlignment(.center).foregroundStyle(Forge.secondary)
                        }.padding(.vertical, 60).padding(.horizontal, 16)
                    }
                    ForEach(filtered) { run in
                        Button { selectedRun = run } label: { RunRow(run: run) }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.background(Forge.background)
                .navigationTitle("Run history")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") } } }
                .refreshable { await model.refresh() }
                .sheet(item: $selectedRun) { RunDetailView(runID: $0.id) }
        }
    }
}

struct RunDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let runID: String
    @State private var confirmStop = false
    @State private var autoFollow = true
    private var run: Run? { model.detail?.id == runID ? model.detail : model.runs.first { $0.id == runID } }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let run {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(run.statusLabel, systemImage: run.isActive ? "waveform" : "circle.fill")
                                .font(.caption.bold()).foregroundStyle(Forge.statusColor(run.status))
                            Spacer()
                            if let exit = run.exitCode { Text(run.status == "dispatched" ? "HTTP \(exit)" : "exit \(exit)").font(.caption.monospaced()).foregroundStyle(Forge.secondary) }
                        }
                        Text(run.title).font(.headline).textSelection(.enabled)
                        Text("\(run.projectName) / \(run.agentName)").font(.caption.monospaced()).foregroundStyle(Forge.secondary)
                        if run.agentId == "deepai" {
                            Label("Webhook handoff only. Review progress and results in DeepAI Code.", systemImage: "info.circle").font(.caption).foregroundStyle(.cyan)
                        }
                        if run.truncated { Text("Showing the most recent 512 KB of output.").font(.caption).foregroundStyle(.orange) }
                    }.padding(20)
                    Divider().overlay(.white.opacity(0.06))
                    ScrollViewReader { proxy in
                        ScrollView([.vertical, .horizontal]) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(run.output?.isEmpty == false ? run.output! : run.isActive ? "Waiting for output…" : "No output was captured.")
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(red: 0.77, green: 0.87, blue: 0.82))
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                Color.clear.frame(height: 1).id("bottom")
                            }.padding(18).frame(minWidth: 280, alignment: .leading)
                        }
                        .onChange(of: run.revision) { _ in if autoFollow { proxy.scrollTo("bottom", anchor: .bottom) } }
                    }
                    Divider()
                    HStack {
                        Toggle("Follow output", isOn: $autoFollow).font(.caption).toggleStyle(.switch).fixedSize()
                        Spacer()
                        if run.isActive {
                            Button("Stop", role: .destructive) { confirmStop = true }.buttonStyle(.bordered)
                        } else {
                            Text(run.dateLabel).font(.caption2).foregroundStyle(Forge.secondary)
                        }
                    }.padding(16)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.background(Forge.background)
                .navigationTitle("Console").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let output = run?.output, !output.isEmpty { ShareLink(item: output) { Image(systemName: "square.and.arrow.up") } }
                    }
                }
                .confirmationDialog("Stop this run?", isPresented: $confirmStop, titleVisibility: .visible) {
                    Button("Stop process", role: .destructive) { Task { await model.cancel(runID) } }
                } message: { Text("This stops the CLI process and its children where supported. It does not undo changes already made. Dispatched DeepAI tasks must be stopped in DeepAI Code.") }
                .task(id: runID) {
                    await model.loadDetail(runID)
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                        if scenePhase == .active { await model.loadDetail(runID) }
                        if let run, !run.isActive { return }
                    }
                }
        }
    }
}
