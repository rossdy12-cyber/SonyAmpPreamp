import SwiftUI

struct SoundscapeAlchemyView: View {
    @EnvironmentObject var engine: CPDS10Engine

    var body: some View {
        NavigationStack {
            ZStack {
                CathedralBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Top Master Deck
                        masterSynthesizerCard

                        // 1-Tap Curated Sleep Rituals for SHARP CP-DS10
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CURATED CP-DS10 40W SLEEP RITUALS")
                                .font(VesperaTheme.engraved(11, weight: .bold))
                                .tracking(1.8)
                                .foregroundStyle(VesperaTheme.ash)

                            ForEach(SleepRitualPreset.presets) { preset in
                                let isSelected = engine.activePresetID == preset.id && engine.isSoundscapePlaying
                                Button {
                                    engine.applyRitualPreset(preset, autoPlay: true)
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(isSelected ? VesperaTheme.blood.opacity(0.35) : VesperaTheme.raised)
                                                .frame(width: 42, height: 42)
                                            Image(systemName: preset.icon)
                                                .font(.system(size: 18))
                                                .foregroundStyle(isSelected ? VesperaTheme.ember : VesperaTheme.blood)
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(preset.name)
                                                .font(VesperaTheme.gothic(16, weight: .semibold))
                                                .foregroundStyle(VesperaTheme.bone)
                                            Text(preset.subtitle)
                                                .font(VesperaTheme.engraved(12))
                                                .foregroundStyle(VesperaTheme.ash)
                                        }
                                        Spacer()
                                        Image(systemName: isSelected ? "waveform.circle.fill" : "play.circle")
                                            .font(.system(size: 22))
                                            .foregroundStyle(isSelected ? VesperaTheme.ember : VesperaTheme.ash)
                                    }
                                    .gothicCard(highlighted: isSelected)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // 8-Channel Procedural Stereo Layer Sliders
                        VStack(alignment: .leading, spacing: 12) {
                            Text("8-CHANNEL PROCEDURAL STEREO LAYERS")
                                .font(VesperaTheme.engraved(11, weight: .bold))
                                .tracking(1.8)
                                .foregroundStyle(VesperaTheme.ash)

                            ForEach(SoundChannelID.allCases) { channel in
                                channelSliderCard(channel)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Sleep Alchemy")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var masterSynthesizerCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("44.1kHz Stereo Sleep Engine")
                        .font(VesperaTheme.gothic(18, weight: .bold))
                        .foregroundStyle(VesperaTheme.bone)
                    Text("Real-time zero-loop synthesis • \(engine.eqPreset.title)")
                        .font(VesperaTheme.engraved(12))
                        .foregroundStyle(VesperaTheme.ash)
                }
                Spacer()
                Button {
                    engine.toggleSoundscape()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: engine.isSoundscapePlaying ? "pause.fill" : "play.fill")
                        Text(engine.isSoundscapePlaying ? "ACTIVE" : "START")
                            .font(VesperaTheme.mono(12, weight: .bold))
                    }
                    .foregroundStyle(VesperaTheme.bone)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(engine.isSoundscapePlaying ? VesperaTheme.blood : VesperaTheme.crimson))
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.1.fill")
                    .foregroundStyle(VesperaTheme.ash)
                Slider(
                    value: Binding(
                        get: { Double(engine.soundscapeMasterVolume) },
                        set: { engine.soundscapeMasterVolume = Float($0) }
                    ),
                    in: 0.0...1.0
                )
                .tint(VesperaTheme.blood)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(VesperaTheme.ember)
                Text("\(Int(engine.soundscapeMasterVolume * 100))%")
                    .font(VesperaTheme.mono(12))
                    .foregroundStyle(VesperaTheme.bone)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .gothicCard(highlighted: engine.isSoundscapePlaying)
    }

    private func channelSliderCard(_ channel: SoundChannelID) -> some View {
        let level = engine.channelLevels[channel] ?? 0.0
        let active = level > 0.02

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: channel.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(active ? VesperaTheme.ember : VesperaTheme.ash)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                        .font(VesperaTheme.gothic(15, weight: .semibold))
                        .foregroundStyle(VesperaTheme.bone)
                    Text(channel.subtitle)
                        .font(VesperaTheme.engraved(11))
                        .foregroundStyle(VesperaTheme.ash)
                }
                Spacer()
                Text("\(Int(level * 100))%")
                    .font(VesperaTheme.mono(12, weight: .bold))
                    .foregroundStyle(active ? VesperaTheme.ember : VesperaTheme.ash)
            }

            Slider(
                value: Binding(
                    get: { Double(level) },
                    set: { engine.setChannelLevel(channel, value: Float($0)) }
                ),
                in: 0.0...1.0
            )
            .tint(active ? VesperaTheme.blood : VesperaTheme.ash)
        }
        .gothicCard(highlighted: active && engine.isSoundscapePlaying)
    }
}
