import SwiftUI

struct Qi2StandByDockView: View {
    @EnvironmentObject var engine: CPDS10Engine
    @State private var currentDate = Date()
    @State private var showControls = true

    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var primaryTint: Color {
        engine.redShiftNightVision ? VesperaTheme.blood : VesperaTheme.bone
    }

    private var secondaryTint: Color {
        engine.redShiftNightVision ? VesperaTheme.crimson : VesperaTheme.ash
    }

    var body: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height
            ZStack {
                // True OLED #000000 background for zero light bleed in dark bedroom
                Color.black.ignoresSafeArea()

                // Gentle Crimson Dawn Wake Alarm Sunrise Bloom
                if engine.dawnBloomProgress > 0.01 {
                    RadialGradient(
                        colors: [
                            VesperaTheme.ember.opacity(0.55 * engine.dawnBloomProgress),
                            VesperaTheme.crimson.opacity(0.35 * engine.dawnBloomProgress),
                            Color.black
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: max(geo.size.width, geo.size.height) * 0.85
                    )
                    .ignoresSafeArea()
                }

                Group {
                    if isWide {
                        landscapeStandByLayout(size: geo.size)
                    } else {
                        portraitDockLayout(size: geo.size)
                    }
                }
                .offset(engine.pixelShiftOffset)
                .opacity(max(0.10, engine.oledBrightness))
            }
        }
        .onReceive(clockTimer) { now in
            currentDate = now
        }
        .statusBarHidden(engine.showFullScreenDock || engine.isLandscape)
    }

    // MARK: - Landscape StandBy Mode (Snapped Horizontally on SHARP CP-DS10 Qi2)

    private func landscapeStandByLayout(size: CGSize) -> some View {
        HStack(spacing: 24) {
            // Left Column: Giant OLED Gothic Timepiece + Alarm & Sleep Timer Badges
            VStack(alignment: .leading, spacing: 10) {
                hardwareTelemetryRow

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(timeString(currentDate))
                        .font(.system(size: min(size.height * 0.36, 118), weight: .bold, design: .serif))
                        .foregroundStyle(primaryTint)
                        .monospacedDigit()
                        .shadow(color: VesperaTheme.crimson.opacity(0.45), radius: 14)

                    Text(secondsString(currentDate))
                        .font(VesperaTheme.mono(22, weight: .medium))
                        .foregroundStyle(secondaryTint)
                }

                Text(dateString(currentDate).uppercased())
                    .font(VesperaTheme.engraved(13, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(secondaryTint)

                HStack(spacing: 12) {
                    if engine.alarmEnabled {
                        Label(String(format: "DAWN %02d:%02d", engine.alarmHour, engine.alarmMinute), systemImage: "sunrise.fill")
                            .font(VesperaTheme.mono(11))
                            .foregroundStyle(primaryTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().strokeBorder(VesperaTheme.blood.opacity(0.6), lineWidth: 1))
                    }
                    if engine.sleepTimerRemainingSeconds > 0 {
                        Label("FADE \(engine.sleepTimerFormatted) • \(Int(engine.sleepFilterCutoffHz))Hz", systemImage: "moon.zzz.fill")
                            .font(VesperaTheme.mono(11))
                            .foregroundStyle(VesperaTheme.ember)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(VesperaTheme.crimson.opacity(0.22)))
                    }
                }

                Spacer(minLength: 4)

                oledDimmerBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right Column: 40W Twin-Neodymium Visualizer + Active Music / Sleep Ritual Deck
            VStack(spacing: 12) {
                stereoVisualizerDeck
                dockNowPlayingCard
                quickSleepTimerRow
            }
            .frame(width: min(size.width * 0.46, 390))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    // MARK: - Portrait Bedside Dock Layout

    private func portraitDockLayout(size: CGSize) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                hardwareTelemetryRow

                if engine.isAlarmRinging {
                    alarmRingingBanner
                }

                // Giant Bedside Clock Card
                VStack(spacing: 6) {
                    Text(dateString(currentDate).uppercased())
                        .font(VesperaTheme.engraved(12, weight: .semibold))
                        .tracking(2.5)
                        .foregroundStyle(secondaryTint)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(timeString(currentDate))
                            .font(.system(size: 82, weight: .bold, design: .serif))
                            .foregroundStyle(primaryTint)
                            .monospacedDigit()
                            .shadow(color: VesperaTheme.crimson.opacity(0.45), radius: 14)

                        Text(secondsString(currentDate))
                            .font(VesperaTheme.mono(20))
                            .foregroundStyle(secondaryTint)
                    }

                    HStack(spacing: 10) {
                        Label(engine.eqPreset.title, systemImage: "hifispeaker.2.fill")
                            .font(VesperaTheme.engraved(11))
                            .foregroundStyle(secondaryTint)

                        if engine.alarmEnabled {
                            Text("•")
                                .foregroundStyle(secondaryTint)
                            Label(String(format: "Alarm %02d:%02d", engine.alarmHour, engine.alarmMinute), systemImage: "bell.fill")
                                .font(VesperaTheme.mono(11))
                                .foregroundStyle(primaryTint)
                        }
                    }
                }
                .padding(.vertical, 10)

                // 40W Twin-Driver Stereo Spectrum Visualizer
                stereoVisualizerDeck

                // Active Music & Soundscape Controls
                dockNowPlayingCard

                // Quick 1-Tap Sleep Ritual Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("SHARP CP-DS10 SLEEP RITUALS")
                        .font(VesperaTheme.engraved(11))
                        .tracking(1.8)
                        .foregroundStyle(secondaryTint)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(SleepRitualPreset.presets) { preset in
                                let active = engine.activePresetID == preset.id && engine.isSoundscapePlaying
                                Button {
                                    engine.applyRitualPreset(preset, autoPlay: true)
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: preset.icon)
                                            .font(.system(size: 13))
                                        Text(preset.name)
                                            .font(VesperaTheme.engraved(12, weight: .semibold))
                                    }
                                    .foregroundStyle(active ? VesperaTheme.bone : primaryTint)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(
                                        Capsule()
                                            .fill(active ? VesperaTheme.blood.opacity(0.45) : Color.white.opacity(0.03))
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(active ? VesperaTheme.ember : VesperaTheme.line, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Smart Fade-Out Sleep Timer Bar
                quickSleepTimerRow

                // OLED Night-Vision Dimmer & Red-Shift Controls
                oledDimmerBar
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
    }

    // MARK: - Subcomponents

    private var hardwareTelemetryRow: some View {
        HStack(spacing: 8) {
            // Qi2 15W Charging Status Pill
            HStack(spacing: 5) {
                Image(systemName: engine.isQi2Charging ? "bolt.circle.fill" : "battery.100")
                    .foregroundStyle(engine.isQi2Charging ? VesperaTheme.ember : secondaryTint)
                Text(engine.isQi2Charging ? "Qi2 15W • \(engine.batteryPercent)%" : "BAT \(engine.batteryPercent)%")
                    .font(VesperaTheme.mono(10, weight: .bold))
                    .foregroundStyle(primaryTint)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(VesperaTheme.crimson.opacity(0.18)))
            .overlay(Capsule().strokeBorder(VesperaTheme.blood.opacity(0.45), lineWidth: 1))

            // SHARP CP-DS10 40W Bluetooth 5.3 Speaker Route Pill
            HStack(spacing: 5) {
                Image(systemName: "hifispeaker.2.fill")
                    .foregroundStyle(VesperaTheme.blood)
                Text(engine.isBluetoothSpeakerActive ? "\(engine.audioRouteName) • 40W" : "CP-DS10 • \(engine.audioRouteName)")
                    .font(VesperaTheme.mono(10, weight: .semibold))
                    .foregroundStyle(primaryTint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.03)))
            .overlay(Capsule().strokeBorder(VesperaTheme.line, lineWidth: 1))

            Spacer()

            BluetoothRoutePickerButton()
                .frame(width: 28, height: 28)

            if engine.showFullScreenDock {
                Button {
                    withAnimation { engine.showFullScreenDock = false }
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(primaryTint)
                        .padding(7)
                        .background(Circle().fill(VesperaTheme.crimson.opacity(0.25)))
                }
            } else {
                Button {
                    withAnimation { engine.showFullScreenDock = true }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(primaryTint)
                        .padding(7)
                        .background(Circle().fill(VesperaTheme.crimson.opacity(0.25)))
                }
            }
        }
    }

    private var alarmRingingBanner: some View {
        HStack {
            Image(systemName: "sunrise.fill")
                .font(.system(size: 20))
                .foregroundStyle(VesperaTheme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("CRIMSON DAWN WAKE ALARM")
                    .font(VesperaTheme.engraved(13, weight: .bold))
                    .foregroundStyle(VesperaTheme.bone)
                Text("40W Harmonic Cathedral Chimes Active")
                    .font(VesperaTheme.engraved(11))
                    .foregroundStyle(VesperaTheme.ash)
            }
            Spacer()
            Button {
                engine.dismissDawnAlarm()
            } label: {
                Text("DISMISS")
                    .font(VesperaTheme.mono(12, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(VesperaTheme.ember))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(VesperaTheme.crimson.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(VesperaTheme.ember, lineWidth: 1.5))
    }

    private var stereoVisualizerDeck: some View {
        VStack(spacing: 6) {
            HStack {
                Text("L • 20W NEODYMIUM")
                    .font(VesperaTheme.mono(9))
                    .foregroundStyle(secondaryTint)
                Spacer()
                Text(engine.isSoundscapePlaying || engine.isMusicPlaying ? "40W STEREO ACTIVE" : "STANDBY")
                    .font(VesperaTheme.mono(9, weight: .bold))
                    .foregroundStyle(engine.isSoundscapePlaying || engine.isMusicPlaying ? VesperaTheme.ember : secondaryTint)
                Spacer()
                Text("20W NEODYMIUM • R")
                    .font(VesperaTheme.mono(9))
                    .foregroundStyle(secondaryTint)
            }

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<engine.spectrumBars.count, id: \.self) { idx in
                    let val = CGFloat(engine.spectrumBars[idx])
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [VesperaTheme.ember, VesperaTheme.blood, VesperaTheme.crimson.opacity(0.4)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(maxWidth: .infinity, minHeight: 4, maxHeight: max(5, 38 * val))
                        .animation(.easeOut(duration: 0.22), value: val)
                }
            }
            .frame(height: 40)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(VesperaTheme.line.opacity(0.75), lineWidth: 1))
    }

    private var dockNowPlayingCard: some View {
        VStack(spacing: 12) {
            // Top Row: Sleep Soundscape Toggle
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(engine.isSoundscapePlaying ? VesperaTheme.blood.opacity(0.32) : Color.white.opacity(0.04))
                        .frame(width: 44, height: 44)
                    Image(systemName: engine.isSoundscapePlaying ? "waveform.circle.fill" : "moon.stars.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(engine.isSoundscapePlaying ? VesperaTheme.ember : primaryTint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeSoundscapeSummary)
                        .font(VesperaTheme.gothic(15, weight: .semibold))
                        .foregroundStyle(primaryTint)
                        .lineLimit(1)
                    Text(engine.isSoundscapePlaying ? "44.1kHz Stereo Procedural Sanctuary" : "Tap play to start bedside sleep audio")
                        .font(VesperaTheme.engraved(11))
                        .foregroundStyle(secondaryTint)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    engine.toggleSoundscape()
                } label: {
                    Image(systemName: engine.isSoundscapePlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(engine.isSoundscapePlaying ? VesperaTheme.ember : primaryTint)
                }
            }

            Divider().background(VesperaTheme.line)

            // Bottom Row: Nocturne / Navidrome Music Streamer Deck
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(VesperaTheme.crimson.opacity(0.25))
                        .frame(width: 44, height: 44)
                    if let song = engine.currentSong, let url = engine.coverURL(for: song.coverArt) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "music.note").foregroundStyle(primaryTint)
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 18))
                            .foregroundStyle(primaryTint)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.currentSong?.title ?? "Nocturne Music Library")
                        .font(VesperaTheme.gothic(14, weight: .semibold))
                        .foregroundStyle(primaryTint)
                        .lineLimit(1)
                    Text(engine.currentSong?.artist ?? "\(engine.navAlbums.count) TrueNAS Albums Ready • Tap Play")
                        .font(VesperaTheme.engraved(11))
                        .foregroundStyle(secondaryTint)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 14) {
                    Button { engine.previousTrack() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(primaryTint)
                    }
                    Button { engine.toggleMusicPlayback() } label: {
                        Image(systemName: engine.isMusicPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(primaryTint)
                    }
                    Button { engine.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(primaryTint)
                    }
                }
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(VesperaTheme.blood.opacity(0.45), lineWidth: 1))
    }

    private var quickSleepTimerRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("SMART LOW-PASS SLEEP TIMER", systemImage: "timer")
                    .font(VesperaTheme.engraved(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(secondaryTint)
                Spacer()
                if engine.sleepTimerRemainingSeconds > 0 {
                    Text("Fading in \(engine.sleepTimerFormatted) (\(Int(engine.sleepFilterCutoffHz)) Hz)")
                        .font(VesperaTheme.mono(11, weight: .bold))
                        .foregroundStyle(VesperaTheme.ember)
                }
            }

            HStack(spacing: 8) {
                ForEach([0, 15, 30, 45, 60, 90], id: \.self) { mins in
                    let isSelected = (mins == 0 && engine.sleepTimerRemainingSeconds == 0) ||
                        (mins > 0 && engine.sleepTimerTotalSeconds == mins * 60 && engine.sleepTimerRemainingSeconds > 0)
                    Button {
                        engine.startSleepTimer(minutes: mins)
                    } label: {
                        Text(mins == 0 ? "OFF" : "\(mins)m")
                            .font(VesperaTheme.mono(11, weight: .bold))
                            .foregroundStyle(isSelected ? Color.black : primaryTint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? VesperaTheme.blood : Color.white.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(isSelected ? VesperaTheme.ember : VesperaTheme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var oledDimmerBar: some View {
        HStack(spacing: 12) {
            Button {
                engine.redShiftNightVision.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: engine.redShiftNightVision ? "eye.fill" : "eye")
                    Text(engine.redShiftNightVision ? "RED-SHIFT" : "BONE")
                        .font(VesperaTheme.mono(10, weight: .bold))
                }
                .foregroundStyle(engine.redShiftNightVision ? VesperaTheme.ember : VesperaTheme.bone)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().strokeBorder(VesperaTheme.blood, lineWidth: 1))
            }

            Image(systemName: "sun.min.fill")
                .font(.system(size: 12))
                .foregroundStyle(secondaryTint)

            Slider(value: $engine.oledBrightness, in: 0.12...1.0)
                .tint(VesperaTheme.blood)

            Image(systemName: "sun.max.fill")
                .font(.system(size: 14))
                .foregroundStyle(primaryTint)
        }
    }

    private var activeSoundscapeSummary: String {
        let active = SoundChannelID.allCases.filter { (engine.channelLevels[$0] ?? 0) > 0.05 }
        if active.isEmpty { return "Sleep Soundscape Mixer" }
        return active.map { $0.title }.joined(separator: " + ")
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func secondsString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = ":ss"
        return f.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: date)
    }
}
