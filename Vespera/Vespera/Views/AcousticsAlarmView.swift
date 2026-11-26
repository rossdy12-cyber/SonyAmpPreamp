import SwiftUI

struct AcousticsAlarmView: View {
    @EnvironmentObject var engine: CPDS10Engine

    var body: some View {
        NavigationStack {
            ZStack {
                CathedralBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // 1. SHARP CP-DS10 40W Twin-Neodymium 5-Band Parametric DSP EQ
                        dspEqualizerSection

                        // 2. Gentle Crimson Dawn Wake Alarm
                        crimsonDawnAlarmSection

                        // 3. Qi2 15W Auto-Dock & OLED Protection Settings
                        qi2AutomationSection

                        // 4. Navidrome Server Configuration
                        navidromeConfigSection
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("CP-DS10 DSP & Alarm")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var dspEqualizerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("SHARP CP-DS10 40W NEODYMIUM DSP EQ", systemImage: "slider.vertical.3")
                    .font(VesperaTheme.engraved(11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(VesperaTheme.ash)
                Spacer()
                Text("\(Int(engine.sleepFilterCutoffHz)) Hz LP")
                    .font(VesperaTheme.mono(11, weight: .bold))
                    .foregroundStyle(VesperaTheme.ember)
            }

            // Preset Selector Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CPDS10EQPreset.allCases.filter { $0 != .custom }) { preset in
                        let active = engine.eqPreset == preset
                        Button {
                            engine.eqPreset = preset
                        } label: {
                            Text(preset.title)
                                .font(VesperaTheme.engraved(12, weight: .semibold))
                                .foregroundStyle(active ? Color.black : VesperaTheme.bone)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(active ? VesperaTheme.ember : VesperaTheme.raised))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(engine.eqPreset.description)
                .font(VesperaTheme.engraved(12))
                .foregroundStyle(VesperaTheme.ash)

            // 5-Band Parametric Vertical/Horizontal Gain Controls
            VStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { idx in
                    HStack(spacing: 10) {
                        Text(CPDS10EQPreset.bandLabels[idx])
                            .font(VesperaTheme.mono(12, weight: .bold))
                            .foregroundStyle(VesperaTheme.bone)
                            .frame(width: 48, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { Double(engine.eqGains[idx]) },
                                set: { newVal in
                                    engine.eqGains[idx] = Float(newVal)
                                }
                            ),
                            in: -12.0...12.0,
                            step: 0.5
                        )
                        .tint(VesperaTheme.blood)

                        Text(String(format: "%+.1f dB", engine.eqGains[idx]))
                            .font(VesperaTheme.mono(11))
                            .foregroundStyle(engine.eqGains[idx] >= 0 ? VesperaTheme.ember : VesperaTheme.ash)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
            .padding(.top, 4)
        }
        .gothicCard(highlighted: true)
    }

    private var crimsonDawnAlarmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("GENTLE CRIMSON DAWN WAKE ALARM", systemImage: "sunrise.fill")
                    .font(VesperaTheme.engraved(11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(VesperaTheme.ash)
                Spacer()
                Toggle("", isOn: $engine.alarmEnabled)
                    .labelsHidden()
                    .tint(VesperaTheme.blood)
            }

            Text("15 minutes before wake time, Vespera gradually blooms your OLED display from #000000 pitch black to a warm Crimson Sunrise while gently fading in 528Hz harmonic cathedral chimes on the SHARP CP-DS10.")
                .font(VesperaTheme.engraved(12))
                .foregroundStyle(VesperaTheme.ash)

            HStack(spacing: 14) {
                Picker("Hour", selection: $engine.alarmHour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(String(format: "%02d", h)).tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 100)

                Text(":")
                    .font(VesperaTheme.gothic(28, weight: .bold))
                    .foregroundStyle(VesperaTheme.ember)

                Picker("Minute", selection: $engine.alarmMinute) {
                    ForEach(0..<60, id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 100)
            }

            HStack(spacing: 12) {
                Button {
                    if engine.isAlarmRinging {
                        engine.dismissDawnAlarm()
                    } else {
                        engine.triggerDawnAlarmNow()
                    }
                } label: {
                    HStack {
                        Image(systemName: engine.isAlarmRinging ? "bell.slash.fill" : "sunrise.fill")
                        Text(engine.isAlarmRinging ? "Stop Dawn Preview" : "Preview Crimson Dawn Chimes")
                            .font(VesperaTheme.mono(12, weight: .bold))
                    }
                    .foregroundStyle(VesperaTheme.bone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(engine.isAlarmRinging ? VesperaTheme.ember : VesperaTheme.crimson))
                }
            }
        }
        .gothicCard(highlighted: engine.alarmEnabled)
    }

    private var qi2AutomationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("SHARP CP-DS10 Qi2 DOCK AUTOMATION", systemImage: "bolt.shield.fill")
                .font(VesperaTheme.engraved(11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(VesperaTheme.ash)

            Toggle(isOn: $engine.autoDockOnQi2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Enter StandBy HUD on Qi2 15W Power")
                        .font(VesperaTheme.gothic(15, weight: .semibold))
                        .foregroundStyle(VesperaTheme.bone)
                    Text("Automatically opens the full-screen OLED clock when snapped onto the CP-DS10 magnetic pad")
                        .font(VesperaTheme.engraved(11))
                        .foregroundStyle(VesperaTheme.ash)
                }
            }
            .tint(VesperaTheme.blood)

            Toggle(isOn: $engine.autoPlayRitualOnDock) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Start Sleep Soundscape When Docked")
                        .font(VesperaTheme.gothic(15, weight: .semibold))
                        .foregroundStyle(VesperaTheme.bone)
                    Text("Begins playing your active sleep ritual immediately when charging begins")
                        .font(VesperaTheme.engraved(11))
                        .foregroundStyle(VesperaTheme.ash)
                }
            }
            .tint(VesperaTheme.blood)

            Toggle(isOn: $engine.redShiftNightVision) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pure Blood-Red Night Vision Filter")
                        .font(VesperaTheme.gothic(15, weight: .semibold))
                        .foregroundStyle(VesperaTheme.bone)
                    Text("Eliminates blue and green OLED subpixels to preserve melatonin in a dark room")
                        .font(VesperaTheme.engraved(11))
                        .foregroundStyle(VesperaTheme.ash)
                }
            }
            .tint(VesperaTheme.blood)
        }
        .gothicCard()
    }

    private var navidromeConfigSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("NOCTURNE / NAVIDROME SERVER", systemImage: "server.rack")
                .font(VesperaTheme.engraved(11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(VesperaTheme.ash)

            TextField("Navidrome URL", text: $engine.navURL)
                .font(VesperaTheme.mono(13))
                .foregroundStyle(VesperaTheme.bone)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(VesperaTheme.raised))

            HStack(spacing: 10) {
                TextField("Username", text: $engine.navUser)
                    .font(VesperaTheme.mono(13))
                    .foregroundStyle(VesperaTheme.bone)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(VesperaTheme.raised))

                SecureField("Password", text: $engine.navPass)
                    .font(VesperaTheme.mono(13))
                    .foregroundStyle(VesperaTheme.bone)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(VesperaTheme.raised))
            }

            Button {
                Task { await engine.loadNavidromeLibrary() }
            } label: {
                Text("Reconnect & Sync TrueNAS Library")
                    .font(VesperaTheme.mono(12, weight: .bold))
                    .foregroundStyle(VesperaTheme.bone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(VesperaTheme.crimson))
            }
        }
        .gothicCard()
    }
}
