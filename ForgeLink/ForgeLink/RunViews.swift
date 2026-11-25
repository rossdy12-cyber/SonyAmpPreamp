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
    @State private var reply = ""
    @State private var submitError: String?
    @FocusState private var replyFocused: Bool
    private var run: Run? { model.detail?.id == runID ? model.detail : model.runs.first { $0.id == runID } }
    private var conversationBusy: Bool { model.conversation.contains { $0.status == "running" } }
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
                            Label("This uses the existing TrueNAS DeepAI agent. Its reply appears when the turn completes; live tokens are not streamed.", systemImage: "info.circle").font(.caption).foregroundStyle(.cyan)
                        }
                        if run.isActive && run.agentId == "deepai" {
                            Label("Waiting for the full DeepAI response… Your task continues if you leave this screen.", systemImage: "clock").font(.caption).foregroundStyle(Forge.secondary)
                        }
                        if (run.responseLost == true || run.agentId == "deepai" && run.status == "failed" && run.output?.contains("connection failed") == true) && run.agentId == "deepai" {
                            Label("The DeepAI turn finished on TrueNAS, but its reply was lost when the connection timed out. It may have completed; check DeepAI Code before retrying to avoid duplicate work.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        } else if !run.isActive && (run.status == "failed" || run.status == "interrupted") && run.agentId == "deepai" {
                            Label("The task didn’t complete. Check Runs for the error before retrying.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                        if run.truncated { Text("Showing the most recent 512 KB of output.").font(.caption).foregroundStyle(.orange) }
                    }.padding(20)
                    Divider().overlay(.white.opacity(0.06))
                    if model.conversation.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView([.vertical, .horizontal]) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(run.output?.isEmpty == false ? run.output! : run.isActive ? (run.agentId == "deepai" ? "Waiting for DeepAI to finish its turn. It returns a complete reply, not a token-by-token stream.\n\nThe request was accepted by your TrueNAS DeepAI agent. Check the status below while it runs." : "Waiting for output…") : ((run.responseLost == true || run.agentId == "deepai" && run.output?.contains("connection failed") == true) ? "The connection timed out. The DeepAI turn may have completed on TrueNAS; check the existing DeepAI thread for its saved result before retrying to avoid duplicate work." : "No output was captured."))
                                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(red: 0.77, green: 0.87, blue: 0.82))
                                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    Color.clear.frame(height: 1).id("bottom")
                                }.padding(18).frame(minWidth: 280, alignment: .leading)
                            }
                            .onChange(of: run.revision) { _ in if autoFollow { proxy.scrollTo("bottom", anchor: .bottom) } }
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 16) {
                                    ForEach(model.conversation) { message in
                                        VStack(alignment: .leading, spacing: 7) {
                                            HStack {
                                                Text(message.agentId == "user" ? "YOU" : message.agentId.uppercased())
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.3)
                                                    .foregroundStyle(message.agentId == "user" ? Forge.mint : .cyan)
                                                Spacer()
                                                Text(message.status.capitalized).font(.system(size: 9, design: .monospaced)).foregroundStyle(Forge.secondary)
                                            }
                                            if message.agentId == "user" {
                                                Text(message.prompt).font(.system(size: 13)).foregroundStyle(.white).textSelection(.enabled)
                                            } else {
                                                Text(message.output.isEmpty ? (message.status == "running" ? "Working…" : "No response captured.") : message.output)
                                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(red: 0.77, green: 0.87, blue: 0.82))
                                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                            }
                                        }.padding(14).background(message.agentId == "user" ? Forge.mint.opacity(0.075) : Forge.surface, in: RoundedRectangle(cornerRadius: 14))
                                            .id(message.id)
                                    }
                                }.padding(16)
                            }
                            .onChange(of: model.conversation.last?.revision) { _ in if autoFollow, let last = model.conversation.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                            .onChange(of: model.conversation.count) { _ in if autoFollow, let last = model.conversation.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                        }
                    }
                    Divider()
                    if run.canContinue == true && !run.isActive && run.status == "succeeded" {
                        VStack(alignment: .leading, spacing: 8) {
                        if let submitError { Text(submitError).font(.caption).foregroundStyle(.orange) }
                        if conversationBusy { Label("Waiting for the current follow-up to finish…", systemImage: "clock").font(.caption).foregroundStyle(Forge.secondary) }
                        HStack(alignment: .bottom, spacing: 10) {
                            TextField("Reply to \(run.agentName)…", text: $reply, axis: .vertical)
                                .lineLimit(1...4).focused($replyFocused).submitLabel(.send)
                                .onSubmit { sendReply(from: run) }
                                .disabled(conversationBusy || model.isContinuing)
                                .padding(12).background(Forge.surface, in: RoundedRectangle(cornerRadius: 14))
                            Button { sendReply(from: run) } label: {
                                if model.isContinuing { ProgressView().frame(width: 42, height: 42) }
                                else { Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).frame(width: 42, height: 42) }
                            }.foregroundStyle(Forge.background).background(Forge.mint, in: Circle())
                                .disabled(conversationBusy || model.isContinuing || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.padding(14)
                        }
                    } else {
                        HStack {
                            Toggle("Follow output", isOn: $autoFollow).font(.caption).toggleStyle(.switch).fixedSize()
                            Spacer()
                            if run.isActive {
                                Button("Stop", role: .destructive) { confirmStop = true }.buttonStyle(.bordered)
                            } else {
                                Text(run.dateLabel).font(.caption2).foregroundStyle(Forge.secondary)
                            }
                        }.padding(16)
                    }
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
                        let stillRunning = model.conversation.contains { $0.status == "running" } || (model.runs.first(where: { $0.id == runID })?.isActive ?? false)
                        if !stillRunning { return }
                    }
                }
        }
    }
    private func sendReply(from run: Run) {
        let message = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        reply = ""
        replyFocused = false
        submitError = nil
        Task {
            if await model.continueChat(run, message: message) == nil { submitError = model.error ?? "Could not send reply." }
        }
    }
}
