import SwiftUI

struct SanctumView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var engine: SleepAudioEngine
    var switchToChronicles: () -> Void

    @State private var showAlarmPicker: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        headerBanner
                        liveAcousticMonitorCard

                        if engine.isRecordingOvernight {
                            activeOvernightSessionCard
                        } else {
                            smartPhaseAlarmCard
                            windDownSoundscapeCard
                            preSleepFactorsCard
                            sensitivityCalibrationCard
                        }

                        primaryActionButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Torpor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(engine.isRecordingOvernight ? Theme.bloodGlow : Theme.emerald)
                            .frame(width: 8, height: 8)
                        Text(engine.isRecordingOvernight ? "RECORDING" : "PRO ARMED")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.bone)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.panelElevated))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
            }
            .sheet(isPresented: $showAlarmPicker) {
                AlarmTimeSheet()
                    .environmentObject(store)
                    .presentationDetents([.medium])
            }
        }
    }

    private var headerBanner: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.crimson.opacity(0.45), Theme.panel],
                            center: .center,
                            startRadius: 2,
                            endRadius: 28
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(Circle().strokeBorder(Theme.crimsonBright, lineWidth: 1.3))

                Image(systemName: engine.isRecordingOvernight ? "waveform.circle.fill" : "moon.stars.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.bloodGlow)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(engine.isRecordingOvernight ? "NOCTURNAL VIGIL ACTIVE" : "NOCTURNAL ACOUSTIC SANCTUM")
                    .font(Theme.serif(17, weight: .bold))
                    .foregroundStyle(Theme.bone)
                Text(
                    engine.isRecordingOvernight
                    ? "Screen-lock safe • Capturing coughs, snores & sleep stages"
                    : "Cough, Snore, Apnea & Sleep Cycle Pro Analyzer"
                )
                .font(.caption)
                .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var liveAcousticMonitorCard: some View {
        GothicCard(glowing: engine.isRecordingOvernight) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LIVE ACOUSTIC SPECTRUM")
                            .font(Theme.serif(13, weight: .bold))
                            .foregroundStyle(Theme.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(String(format: "%.1f dB", engine.currentDecibels))
                                .font(Theme.mono(28, weight: .bold))
                                .foregroundStyle(Theme.bone)
                            Text("Floor \(String(format: "%.0f", engine.ambientFloorDecibels)) dB • Trigger +\(String(format: "%.1f", store.sensitivityPreset.thresholdDeltaDb)) dB")
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    if engine.isCapturingClipNow {
                        Label("CLIPPING", systemImage: "record.circle.fill")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(Theme.bloodGlow)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.crimson.opacity(0.28)))
                    } else {
                        Text(engine.currentSleepStage.rawValue.uppercased())
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(engine.currentSleepStage.color)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.bg0))
                            .overlay(Capsule().strokeBorder(engine.currentSleepStage.color.opacity(0.5), lineWidth: 1))
                    }
                }

                // 48-bar Crimson Spectrum Visualizer
                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(engine.liveSpectrumBars.enumerated()), id: \.offset) { _, val in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        val > 0.48 ? Theme.bloodGlow : Theme.crimsonBright,
                                        Theme.crimson.opacity(0.55)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(6, CGFloat(val) * 76.0))
                    }
                }
                .frame(height: 78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.bg0.opacity(0.75))
                )
            }
        }
    }

    private var activeOvernightSessionCard: some View {
        VStack(spacing: 16) {
            GothicCard(glowing: true) {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ELAPSED SLUMBER")
                                .font(Theme.serif(12, weight: .bold))
                                .foregroundStyle(Theme.muted)
                            Text(formatElapsed(engine.elapsedSeconds))
                                .font(Theme.mono(34, weight: .bold))
                                .foregroundStyle(Theme.bone)
                        }
                        Spacer()
                        if store.smartAlarmEnabled {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("SMART ALARM WINDOW")
                                    .font(Theme.serif(11, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                Text(store.wakeWindowFormatted)
                                    .font(Theme.mono(15, weight: .bold))
                                    .foregroundStyle(Theme.crimsonBright)
                            }
                        }
                    }

                    Divider().overlay(Theme.hairline)

                    // Live Event Counters
                    HStack(spacing: 10) {
                        liveCounterPill(
                            label: "Coughs",
                            count: engine.activeEvents.filter { $0.category == .cough }.count,
                            color: DisturbanceCategory.cough.color,
                            icon: DisturbanceCategory.cough.icon
                        )
                        liveCounterPill(
                            label: "Snores",
                            count: engine.activeEvents.filter { $0.category == .snore }.count,
                            color: DisturbanceCategory.snore.color,
                            icon: DisturbanceCategory.snore.icon
                        )
                        liveCounterPill(
                            label: "Talks",
                            count: engine.activeEvents.filter { $0.category == .talk }.count,
                            color: DisturbanceCategory.talk.color,
                            icon: DisturbanceCategory.talk.icon
                        )
                        liveCounterPill(
                            label: "Gasps",
                            count: engine.activeEvents.filter { $0.category == .gasp }.count,
                            color: DisturbanceCategory.gasp.color,
                            icon: DisturbanceCategory.gasp.icon
                        )
                    }

                    // Instant Test Disturbance Trigger Buttons
                    VStack(alignment: .leading, spacing: 8) {
                        Text("INSTANT TEST CAPTURE (SYNTHESIZES & RECORDS REAL CLIP)")
                            .font(Theme.mono(10, weight: .bold))
                            .foregroundStyle(Theme.muted)
                        HStack(spacing: 8) {
                            ForEach([DisturbanceCategory.cough, .snore, .talk, .gasp]) { cat in
                                Button {
                                    engine.injectTestDisturbance(category: cat)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: cat.icon)
                                            .font(.caption2)
                                        Text("+ \(cat.shortLabel)")
                                            .font(Theme.mono(11, weight: .bold))
                                    }
                                    .foregroundStyle(Theme.bone)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(cat.color.opacity(0.22))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9)
                                            .strokeBorder(cat.color.opacity(0.65), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }

                    if !engine.activeEvents.isEmpty {
                        Divider().overlay(Theme.hairline)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RECENT CAPTURED CLIPS THIS NIGHT (\(engine.activeEvents.count))")
                                .font(Theme.serif(12, weight: .bold))
                                .foregroundStyle(Theme.muted)

                            ForEach(engine.activeEvents.prefix(4)) { ev in
                                HStack {
                                    Image(systemName: ev.category.icon)
                                        .foregroundStyle(ev.category.color)
                                    Text(ev.category.rawValue)
                                        .font(Theme.serif(14, weight: .semibold))
                                        .foregroundStyle(Theme.bone)
                                    Spacer()
                                    Text("\(String(format: "%.1f", ev.peakDecibels)) dB • \(String(format: "%.1f", ev.durationSeconds))s")
                                        .font(Theme.mono(12))
                                        .foregroundStyle(Theme.muted)
                                    Button {
                                        engine.togglePlayClip(for: ev)
                                    } label: {
                                        Image(systemName: engine.playingEventID == ev.id ? "stop.circle.fill" : "play.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(Theme.crimsonBright)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
    }

    private func liveCounterPill(label: String, count: Int, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text("\(count)")
                    .font(Theme.mono(18, weight: .bold))
                    .foregroundStyle(Theme.bone)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg0.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }

    private var smartPhaseAlarmCard: some View {
        GothicCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("SMART PHASE ALARM", systemImage: "alarm.waves.left.and.right.fill")
                        .font(Theme.serif(14, weight: .bold))
                        .foregroundStyle(Theme.crimsonBright)
                    Spacer()
                    Toggle("", isOn: $store.smartAlarmEnabled)
                        .labelsHidden()
                        .tint(Theme.crimsonBright)
                }

                if store.smartAlarmEnabled {
                    HStack(alignment: .center) {
                        Button {
                            showAlarmPicker = true
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.alarmTimeFormatted)
                                    .font(Theme.mono(32, weight: .bold))
                                    .foregroundStyle(Theme.bone)
                                Text("Wake Window: \(store.wakeWindowFormatted)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 6) {
                            Picker("Window", selection: $store.wakeWindowMinutes) {
                                Text("15m").tag(15)
                                Text("20m").tag(20)
                                Text("30m").tag(30)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 155)

                            Button {
                                if engine.isSmartAlarmRinging {
                                    engine.stopSmartAlarm()
                                } else {
                                    engine.triggerSmartAlarm()
                                }
                            } label: {
                                Label("Preview Chime", systemImage: "bell.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.crimsonBright)
                            }
                        }
                    }
                } else {
                    Text("Alarm disabled — Torpor will silently record sleep stages and acoustic events until you wake.")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var windDownSoundscapeCard: some View {
        GothicCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("NOCTURNAL WIND-DOWN SOUNDSCAPE", systemImage: "moon.zzz.fill")
                        .font(Theme.serif(14, weight: .bold))
                        .foregroundStyle(Theme.crimsonBright)
                    Spacer()
                    if engine.isPlayingWindDown {
                        Button("Stop Preview") {
                            engine.stopWindDown()
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Theme.bloodGlow)
                    } else if store.windDownSound != .off {
                        Button("Preview") {
                            engine.startWindDown(sound: store.windDownSound, durationMinutes: store.windDownMinutes)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(Theme.crimsonBright)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(WindDownSound.allCases) { snd in
                            let selected = store.windDownSound == snd
                            Button {
                                store.windDownSound = snd
                                if engine.isPlayingWindDown {
                                    if snd == .off {
                                        engine.stopWindDown()
                                    } else {
                                        engine.startWindDown(sound: snd, durationMinutes: store.windDownMinutes)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: snd.icon)
                                    Text(snd.rawValue)
                                        .font(Theme.serif(13, weight: .semibold))
                                }
                                .foregroundStyle(selected ? Theme.bone : Theme.muted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selected ? Theme.crimson.opacity(0.42) : Theme.bg0)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(selected ? Theme.crimsonBright : Theme.hairline, lineWidth: 1)
                                )
                            }
                        }
                    }
                }

                if store.windDownSound != .off {
                    HStack {
                        Text(store.windDownSound.subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Picker("Auto-Fade", selection: $store.windDownMinutes) {
                            Text("15m").tag(15)
                            Text("20m").tag(20)
                            Text("45m").tag(45)
                            Text("60m").tag(60)
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.crimsonBright)
                    }
                }
            }
        }
    }

    private var preSleepFactorsCard: some View {
        GothicCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("PRE-SLEEP RITUAL TAGS", systemImage: "sparkles")
                        .font(Theme.serif(14, weight: .bold))
                        .foregroundStyle(Theme.crimsonBright)
                    Spacer()
                    Text("\(store.selectedFactors.count) active")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 102), spacing: 8)], spacing: 8) {
                    ForEach(PreSleepFactor.allCases) { factor in
                        let isSel = store.selectedFactors.contains(factor)
                        Button {
                            store.toggleFactor(factor)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: factor.icon)
                                    .font(.caption)
                                Text(factor.rawValue)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSel ? Theme.bone : Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(isSel ? (factor.isRemedy ? Theme.emerald.opacity(0.26) : Theme.crimson.opacity(0.38)) : Theme.bg0)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(
                                        isSel ? (factor.isRemedy ? Theme.emerald : Theme.crimsonBright) : Theme.hairline,
                                        lineWidth: 1
                                    )
                            )
                        }
                    }
                }
            }
        }
    }

    private var sensitivityCalibrationCard: some View {
        GothicCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("COUGH & SNORE TRIGGER SENSITIVITY", systemImage: "waveform.badge.mic")
                    .font(Theme.serif(14, weight: .bold))
                    .foregroundStyle(Theme.crimsonBright)

                Picker("Sensitivity", selection: $store.sensitivityPreset) {
                    ForEach(SensitivityPreset.allCases) { preset in
                        Text(preset.rawValue.components(separatedBy: " ").first ?? preset.rawValue)
                            .tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Text(store.sensitivityPreset.description)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var primaryActionButton: some View {
        VStack(spacing: 12) {
            if engine.isRecordingOvernight {
                HStack(spacing: 12) {
                    Button {
                        engine.togglePauseOvernight()
                    } label: {
                        HStack {
                            Image(systemName: engine.isPaused ? "play.fill" : "pause.fill")
                            Text(engine.isPaused ? "Resume Vigil" : "Pause")
                        }
                        .font(Theme.serif(16, weight: .semibold))
                        .foregroundStyle(Theme.bone)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Theme.panelElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Theme.crimsonBright, lineWidth: 1.2)
                        )
                    }

                    Button {
                        if let completed = engine.stopOvernightSession(
                            factors: Array(store.selectedFactors),
                            notes: store.sessionNotesDraft
                        ) {
                            store.addSession(completed)
                            store.sessionNotesDraft = ""
                            switchToChronicles()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                            Text("Awaken & Save Night")
                        }
                        .font(Theme.serif(16, weight: .bold))
                        .foregroundStyle(Theme.bone)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [Theme.crimsonBright, Theme.crimson],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Theme.crimsonBright.opacity(0.45), radius: 10, x: 0, y: 4)
                    }
                }
            } else {
                Button {
                    Task {
                        await engine.startOvernightSession(
                            sensitivity: store.sensitivityPreset,
                            windDownSound: store.windDownSound,
                            windDownMinutes: store.windDownMinutes
                        )
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.title3)
                        Text("ENTER TORPOR (START OVERNIGHT TRACKING)")
                            .font(Theme.serif(16, weight: .bold))
                    }
                    .foregroundStyle(Theme.bone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.crimsonBright, Theme.crimson],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Theme.bloodGlow.opacity(0.8), lineWidth: 1.2)
                    )
                    .shadow(color: Theme.crimsonBright.opacity(0.5), radius: 14, x: 0, y: 6)
                }
            }
        }
    }

    private func formatElapsed(_ sec: TimeInterval) -> String {
        let total = Int(max(0, sec))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

struct AlarmTimeSheet: View {
    @EnvironmentObject var store: SleepStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()
                VStack(spacing: 20) {
                    Text("Select Target Awakening Time")
                        .font(Theme.serif(20, weight: .bold))
                        .foregroundStyle(Theme.bone)

                    HStack(spacing: 16) {
                        Picker("Hour", selection: $store.alarmHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 90)

                        Text(":")
                            .font(Theme.mono(28, weight: .bold))
                            .foregroundStyle(Theme.crimsonBright)

                        Picker("Minute", selection: $store.alarmMinute) {
                            ForEach(0..<60, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 90)
                    }

                    Text("Smart Phase Window: \(store.wakeWindowFormatted)")
                        .font(Theme.mono(14))
                        .foregroundStyle(Theme.muted)

                    Button {
                        dismiss()
                    } label: {
                        Text("Confirm Awakening Time")
                            .font(Theme.serif(16, weight: .bold))
                            .foregroundStyle(Theme.bone)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.crimsonBright))
                    }
                    .padding(.horizontal, 24)
                }
                .padding()
            }
        }
    }
}
