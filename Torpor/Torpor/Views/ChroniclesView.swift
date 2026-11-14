import SwiftUI

struct ChroniclesView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var engine: SleepAudioEngine

    @State private var selectedSessionID: UUID?
    @State private var selectedCategoryFilter: DisturbanceCategory? = nil
    @State private var bookmarkedOnly: Bool = false

    private var activeSession: SleepSession? {
        if let id = selectedSessionID, let match = store.sessions.first(where: { $0.id == id }) {
            return match
        }
        return store.sessions.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        sessionSelectorStrip

                        if let session = activeSession {
                            scoreSummaryCard(session: session)
                            hypnogramCard(session: session)
                            decibelTimelineCard(session: session)
                            stageBreakdownCard(session: session)
                            audioClipVaultCard(session: session)
                        } else {
                            GothicCard {
                                VStack(spacing: 12) {
                                    Image(systemName: "moon.zzz.fill")
                                        .font(.largeTitle)
                                        .foregroundStyle(Theme.crimsonBright)
                                    Text("No Nocturnal Chronicles Recorded")
                                        .font(Theme.serif(18, weight: .bold))
                                        .foregroundStyle(Theme.bone)
                                    Button("Simulate Sample Night") {
                                        store.generateAdditionalDemoNight()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.crimsonBright)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Chronicles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.generateAdditionalDemoNight()
                        selectedSessionID = store.sessions.first?.id
                    } label: {
                        Label("Simulate Night", systemImage: "plus.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.crimsonBright)
                    }
                }
            }
        }
    }

    private var sessionSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.sessions) { session in
                    let isSelected = session.id == activeSession?.id
                    Button {
                        selectedSessionID = session.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .font(Theme.serif(13, weight: .bold))
                                .foregroundStyle(isSelected ? Theme.bone : Theme.muted)
                            HStack(spacing: 6) {
                                Text("\(session.sleepQualityScore)%")
                                    .font(Theme.mono(14, weight: .bold))
                                    .foregroundStyle(isSelected ? Theme.bloodGlow : Theme.bone)
                                Text("• \(session.durationFormatted)")
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.muted)
                            }
                            HStack(spacing: 6) {
                                Label("\(session.coughCount)", systemImage: "lungs.fill")
                                    .font(.caption2)
                                    .foregroundStyle(DisturbanceCategory.cough.color)
                                Label("\(session.snoreCount)", systemImage: "waveform.path.ecg")
                                    .font(.caption2)
                                    .foregroundStyle(DisturbanceCategory.snore.color)
                            }
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Theme.crimson.opacity(0.36) : Theme.panel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isSelected ? Theme.crimsonBright : Theme.hairline, lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                }
            }
        }
    }

    private func scoreSummaryCard(session: SleepSession) -> some View {
        GothicCard(glowing: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 18) {
                    // Circular Sleep Quality Gauge
                    ZStack {
                        Circle()
                            .stroke(Theme.bg0, lineWidth: 10)
                            .frame(width: 86, height: 86)
                        Circle()
                            .trim(from: 0, to: CGFloat(session.sleepQualityScore) / 100.0)
                            .stroke(
                                AngularGradient(
                                    colors: [Theme.crimson, Theme.bloodGlow, Theme.crimsonBright],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 86, height: 86)
                        VStack(spacing: 0) {
                            Text("\(session.sleepQualityScore)%")
                                .font(Theme.mono(21, weight: .bold))
                                .foregroundStyle(Theme.bone)
                            Text("QUALITY")
                                .font(Theme.mono(9, weight: .bold))
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(session.startDate.formatted(date: .omitted, time: .shortened)) – \(session.endDate.formatted(date: .omitted, time: .shortened))")
                                .font(Theme.serif(16, weight: .bold))
                                .foregroundStyle(Theme.bone)
                            Spacer()
                            Text(session.durationFormatted)
                                .font(Theme.mono(13, weight: .bold))
                                .foregroundStyle(Theme.crimsonBright)
                        }

                        HStack(spacing: 14) {
                            metricMini(title: "Snore Index", value: "\(session.snoreScore)", color: Theme.amber)
                            metricMini(title: "Snore Time", value: "\(String(format: "%.0f", session.snoreDurationMinutes))m", color: Theme.amber)
                            metricMini(title: "Peak Level", value: "\(String(format: "%.0f", session.peakDecibels)) dB", color: Theme.bloodGlow)
                        }

                        if !session.factors.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(session.factors) { f in
                                        HStack(spacing: 4) {
                                            Image(systemName: f.icon)
                                                .font(.system(size: 10))
                                            Text(f.rawValue)
                                                .font(.caption2.weight(.semibold))
                                        }
                                        .foregroundStyle(Theme.bone)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Theme.bg0))
                                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                                    }
                                }
                            }
                        }
                    }
                }

                if !session.notes.isEmpty {
                    Text("“\(session.notes)”")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func metricMini(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Theme.mono(14, weight: .bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
    }

    private func hypnogramCard(session: SleepSession) -> some View {
        GothicCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("SLEEP STAGE HYPNOGRAM", systemImage: "waveform.path.ecg.rectangle.fill")
                        .font(Theme.serif(13, weight: .bold))
                        .foregroundStyle(Theme.crimsonBright)
                    Spacer()
                    if session.wokeBySmartAlarm {
                        Label("Smart Phase Wake", systemImage: "bell.badge.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.emerald)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .trailing, spacing: 18) {
                        Text("Awake").font(Theme.mono(10)).foregroundStyle(SleepStage.awake.color)
                        Text("REM").font(Theme.mono(10)).foregroundStyle(SleepStage.rem.color)
                        Text("Light").font(Theme.mono(10)).foregroundStyle(SleepStage.light.color)
                        Text("Torpor").font(Theme.mono(10)).foregroundStyle(SleepStage.deepTorpor.color)
                    }
                    .padding(.vertical, 6)

                    HypnogramCanvasView(points: session.timeline)
                        .frame(height: 118)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg0.opacity(0.85)))
                }

                HStack {
                    Text(session.startDate.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    Text("Mid-Slumber")
                    Spacer()
                    Text(session.endDate.formatted(date: .omitted, time: .shortened))
                }
                .font(Theme.mono(10))
                .foregroundStyle(Theme.muted)
            }
        }
    }

    private func decibelTimelineCard(session: SleepSession) -> some View {
        GothicCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("OVERNIGHT DECIBEL & DISTURBANCE MAP", systemImage: "waveform")
                        .font(Theme.serif(13, weight: .bold))
                        .foregroundStyle(Theme.crimsonBright)
                    Spacer()
                    Text("Peak \(String(format: "%.1f", session.peakDecibels)) dB")
                        .font(Theme.mono(11, weight: .bold))
                        .foregroundStyle(Theme.bloodGlow)
                }

                DecibelTimelineCanvas(session: session)
                    .frame(height: 105)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg0.opacity(0.85)))

                HStack(spacing: 14) {
                    ForEach([DisturbanceCategory.cough, .snore, .talk, .gasp]) { cat in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(cat.color)
                                .frame(width: 7, height: 7)
                            Text(cat.shortLabel)
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
    }

    private func stageBreakdownCard(session: SleepSession) -> some View {
        GothicCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("ARCHITECTURE OF SLUMBER", systemImage: "moon.circle.fill")
                    .font(Theme.serif(13, weight: .bold))
                    .foregroundStyle(Theme.crimsonBright)

                ForEach([SleepStage.deepTorpor, .rem, .light, .awake]) { stage in
                    let pct = session.percentage(in: stage)
                    let mins = session.minutes(in: stage)
                    VStack(spacing: 4) {
                        HStack {
                            Text(stage.rawValue)
                                .font(Theme.serif(13, weight: .semibold))
                                .foregroundStyle(Theme.bone)
                            Spacer()
                            Text("\(mins)m (\(pct)%)")
                                .font(Theme.mono(12, weight: .bold))
                                .foregroundStyle(stage.color)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.bg0)
                                Capsule()
                                    .fill(stage.color)
                                    .frame(width: max(6, geo.size.width * CGFloat(pct) / 100.0))
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
    }

    private func audioClipVaultCard(session: SleepSession) -> some View {
        let filtered = session.events.filter { ev in
            if bookmarkedOnly && !ev.isBookmarked { return false }
            if let cat = selectedCategoryFilter, ev.category != cat { return false }
            return true
        }

        return GothicCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("RECORDED DISTURBANCE VAULT (\(filtered.count))", systemImage: "recordingtape")
                        .font(Theme.serif(13, weight: .bold))
                        .foregroundStyle(Theme.crimsonBright)
                    Spacer()
                    Button {
                        engine.cyclePlaybackRate()
                    } label: {
                        Text(String(format: "%.2gx", engine.playbackRate))
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.bone)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.bg0))
                            .overlay(Capsule().strokeBorder(Theme.crimsonBright, lineWidth: 1))
                    }
                }

                // Category Filter Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(
                            title: "All (\(session.events.count))",
                            active: selectedCategoryFilter == nil && !bookmarkedOnly
                        ) {
                            selectedCategoryFilter = nil
                            bookmarkedOnly = false
                        }

                        filterChip(
                            title: "★ Starred",
                            active: bookmarkedOnly
                        ) {
                            bookmarkedOnly.toggle()
                        }

                        ForEach([DisturbanceCategory.cough, .snore, .talk, .gasp]) { cat in
                            let count = session.events.filter { $0.category == cat }.count
                            filterChip(
                                title: "\(cat.shortLabel) (\(count))",
                                active: selectedCategoryFilter == cat
                            ) {
                                selectedCategoryFilter = (selectedCategoryFilter == cat) ? nil : cat
                            }
                        }
                    }
                }

                if filtered.isEmpty {
                    Text("No recorded clips match the selected filter.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 12)
                } else {
                    ForEach(filtered) { ev in
                        DisturbanceClipRow(sessionID: session.id, event: ev)
                    }
                }
            }
        }
    }

    private func filterChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(active ? Theme.bone : Theme.muted)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(active ? Theme.crimson.opacity(0.45) : Theme.bg0))
                .overlay(Capsule().strokeBorder(active ? Theme.crimsonBright : Theme.hairline, lineWidth: 1))
        }
    }
}

struct DisturbanceClipRow: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var engine: SleepAudioEngine
    let sessionID: UUID
    let event: DisturbanceEvent

    private var isPlaying: Bool {
        engine.playingEventID == event.id
    }

    private var clipFileURL: URL {
        let name = event.audioFileName ?? "clip_\(event.id.uuidString.prefix(8)).wav"
        return SynthesizedAudioGenerator.ensureDisturbanceClipWAV(
            fileName: name,
            category: event.category,
            durationSeconds: event.durationSeconds
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    engine.togglePlayClip(for: event)
                } label: {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(event.category.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: event.category.icon)
                            .font(.caption)
                            .foregroundStyle(event.category.color)
                        Text(event.category.rawValue)
                            .font(Theme.serif(15, weight: .bold))
                            .foregroundStyle(Theme.bone)
                        Text("• \(event.timestamp.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.muted)
                    }
                    Text("Peak \(String(format: "%.1f", event.peakDecibels)) dB • \(String(format: "%.1f", event.durationSeconds))s • \(Int(event.confidence * 100))% match")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                }

                Spacer()

                // Bookmark Star
                Button {
                    store.toggleBookmark(sessionID: sessionID, eventID: event.id)
                } label: {
                    Image(systemName: event.isBookmarked ? "star.fill" : "star")
                        .foregroundStyle(event.isBookmarked ? Theme.amber : Theme.muted)
                }

                // Reclassify & Share Menu
                Menu {
                    Section("Reclassify Acoustic Event") {
                        ForEach(DisturbanceCategory.allCases) { cat in
                            Button {
                                store.reclassifyEvent(sessionID: sessionID, eventID: event.id, newCategory: cat)
                            } label: {
                                Label(cat.rawValue, systemImage: cat.icon)
                            }
                        }
                    }
                    Section("Export") {
                        ShareLink(item: clipFileURL) {
                            Label("Share Audio Clip (.wav)", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.muted)
                }
            }

            // Interactive Waveform Bar Scrubber
            HStack(alignment: .center, spacing: 3) {
                let samples = event.waveformSamples.isEmpty ? Array(repeating: Float(0.4), count: 36) : event.waveformSamples
                ForEach(Array(samples.enumerated()), id: \.offset) { idx, amp in
                    let frac = Double(idx) / Double(max(1, samples.count - 1))
                    let highlighted = isPlaying && frac <= engine.playbackProgress
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(highlighted ? Theme.bloodGlow : event.category.color.opacity(0.55))
                        .frame(height: max(4, CGFloat(amp) * 34.0))
                }
            }
            .frame(height: 36)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bg0.opacity(0.75)))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isPlaying ? Theme.bloodGlow : Theme.hairline, lineWidth: isPlaying ? 1.3 : 1)
        )
    }
}

struct HypnogramCanvasView: View {
    let points: [HypnogramPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let w = size.width
            let h = size.height
            let padY: CGFloat = 14

            // Horizontal guide lines for 4 stages
            for lvl in 0...3 {
                let y = padY + (1.0 - CGFloat(lvl) / 3.0) * (h - padY * 2)
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: w, y: y))
                context.stroke(grid, with: .color(Theme.hairline.opacity(0.35)), lineWidth: 0.7)
            }

            var path = Path()
            for (idx, pt) in points.enumerated() {
                let x = CGFloat(idx) / CGFloat(points.count - 1) * w
                let y = padY + (1.0 - CGFloat(pt.stage.chartLevel) / 3.0) * (h - padY * 2)
                if idx == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    let prevX = CGFloat(idx - 1) / CGFloat(points.count - 1) * w
                    let midX = (prevX + x) * 0.5
                    let prevY = padY + (1.0 - CGFloat(points[idx - 1].stage.chartLevel) / 3.0) * (h - padY * 2)
                    path.addCurve(
                        to: CGPoint(x: x, y: y),
                        control1: CGPoint(x: midX, y: prevY),
                        control2: CGPoint(x: midX, y: y)
                    )
                }
            }

            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [Theme.bloodGlow, Theme.crimsonBright, Theme.violet]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: h)
                ),
                lineWidth: 2.6
            )
        }
    }
}

struct DecibelTimelineCanvas: View {
    let session: SleepSession

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let start = session.startDate.timeIntervalSince1970
            let span = max(60.0, session.endDate.timeIntervalSince1970 - start)

            // Ambient floor curve from timeline
            if session.timeline.count > 1 {
                var dbPath = Path()
                for (i, pt) in session.timeline.enumerated() {
                    let x = CGFloat(i) / CGFloat(session.timeline.count - 1) * w
                    let norm = max(0.05, min(0.95, (pt.decibels - 28.0) / 55.0))
                    let y = h - CGFloat(norm) * (h - 16) - 6
                    if i == 0 {
                        dbPath.move(to: CGPoint(x: x, y: y))
                    } else {
                        dbPath.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(dbPath, with: .color(Theme.crimson.opacity(0.6)), lineWidth: 1.5)
            }

            // Plot vertical spike pins for every cough/snore/talk/gasp event
            for ev in session.events {
                let rel = max(0.02, min(0.98, (ev.timestamp.timeIntervalSince1970 - start) / span))
                let x = CGFloat(rel) * w
                let norm = max(0.2, min(0.95, (ev.peakDecibels - 30.0) / 55.0))
                let topY = h - CGFloat(norm) * (h - 14) - 4

                var spike = Path()
                spike.move(to: CGPoint(x: x, y: h - 4))
                spike.addLine(to: CGPoint(x: x, y: topY))
                context.stroke(spike, with: .color(ev.category.color), lineWidth: 2.4)

                let dot = CGRect(x: x - 3.5, y: topY - 3.5, width: 7, height: 7)
                context.fill(Path(ellipseIn: dot), with: .color(ev.category.color))
            }
        }
    }
}
