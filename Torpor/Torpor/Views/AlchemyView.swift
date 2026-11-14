import SwiftUI

struct AlchemyView: View {
    @EnvironmentObject var store: SleepStore

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        kpiGridCard
                        qualityTrendCard
                        coughAndSnoreComparisonCard
                        factorCorrelationMatrixCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Alchemy & Trends")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var kpiGridCard: some View {
        HStack(spacing: 10) {
            kpiTile(
                title: "Avg Quality",
                value: "\(store.averageQualityScore)%",
                subtitle: "\(store.sessions.count) nights",
                color: Theme.bloodGlow
            )
            kpiTile(
                title: "Avg Slumber",
                value: "\(String(format: "%.1f", store.averageSleepHours))h",
                subtitle: "Target 7.5h",
                color: Theme.crimsonBright
            )
            kpiTile(
                title: "Snore Index",
                value: "\(store.averageSnoreScore)",
                subtitle: "\(store.totalRecordedClipsCount) clips",
                color: Theme.amber
            )
        }
    }

    private func kpiTile(title: String, value: String, subtitle: String, color: Color) -> some View {
        GothicCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(Theme.mono(10, weight: .bold))
                    .foregroundStyle(Theme.muted)
                Text(value)
                    .font(Theme.mono(22, weight: .bold))
                    .foregroundStyle(color)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var qualityTrendCard: some View {
        let recent = Array(store.sessions.prefix(7).reversed())
        return GothicCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("SLEEP QUALITY & SNORE SCORE TREND", systemImage: "chart.line.uptrend.xyaxis")
                    .font(Theme.serif(13, weight: .bold))
                    .foregroundStyle(Theme.crimsonBright)

                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(recent) { s in
                        VStack(spacing: 6) {
                            Text("\(s.sleepQualityScore)%")
                                .font(Theme.mono(10, weight: .bold))
                                .foregroundStyle(Theme.bone)

                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Theme.bg0)
                                    .frame(width: 28, height: 110)

                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        LinearGradient(
                                            colors: [Theme.bloodGlow, Theme.crimson],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 28, height: max(12, CGFloat(s.sleepQualityScore) * 1.1))
                            }

                            Text(s.startDate.formatted(.dateTime.weekday(.narrow)))
                                .font(Theme.mono(11, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var coughAndSnoreComparisonCard: some View {
        let recent = Array(store.sessions.prefix(7).reversed())
        return GothicCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("NIGHTLY COUGH vs. SNORE FREQUENCY", systemImage: "lungs.fill")
                    .font(Theme.serif(13, weight: .bold))
                    .foregroundStyle(Theme.crimsonBright)

                ForEach(recent) { s in
                    HStack(spacing: 10) {
                        Text(s.startDate.formatted(.dateTime.weekday(.abbreviated).day()))
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.bone)
                            .frame(width: 58, alignment: .leading)

                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DisturbanceCategory.cough.color)
                                .frame(width: max(8, CGFloat(s.coughCount) * 14.0), height: 12)
                            Text("\(s.coughCount) coughs")
                                .font(Theme.mono(10))
                                .foregroundStyle(DisturbanceCategory.cough.color)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DisturbanceCategory.snore.color)
                                .frame(width: max(8, CGFloat(s.snoreCount) * 10.0), height: 12)
                            Text("\(s.snoreCount) snores")
                                .font(Theme.mono(10))
                                .foregroundStyle(DisturbanceCategory.snore.color)
                        }
                    }
                }
            }
        }
    }

    private var factorCorrelationMatrixCard: some View {
        GothicCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("RITUAL FACTOR IMPACT ON COUGH & SNORE", systemImage: "sparkles")
                    .font(Theme.serif(13, weight: .bold))
                    .foregroundStyle(Theme.crimsonBright)

                Text("Compares your average cough + snore events on nights with each tag against your overall baseline.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                ForEach(store.factorImpacts) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.factor.icon)
                            .foregroundStyle(item.factor.isRemedy ? Theme.emerald : Theme.crimsonBright)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.factor.rawValue)
                                .font(Theme.serif(14, weight: .semibold))
                                .foregroundStyle(Theme.bone)
                            Text("\(item.nightsCount) nights • Avg \(String(format: "%.1f", item.avgCoughs)) coughs, \(String(format: "%.1f", item.avgSnores)) snores")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.muted)
                        }

                        Spacer()

                        let pct = item.deltaDisturbancesPercent
                        Text(pct <= 0 ? "\(pct)% quieter" : "+\(pct)% louder")
                            .font(Theme.mono(11, weight: .bold))
                            .foregroundStyle(pct <= 0 ? Theme.emerald : Theme.bloodGlow)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill((pct <= 0 ? Theme.emerald : Theme.bloodGlow).opacity(0.16))
                            )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct CovenSettingsView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var engine: SleepAudioEngine

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        GothicCard(glowing: true) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "shield.checkered")
                                        .font(.title2)
                                        .foregroundStyle(Theme.bloodGlow)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("TORPOR PRO SANCTUARY UNLOCKED")
                                            .font(Theme.serif(16, weight: .bold))
                                            .foregroundStyle(Theme.bone)
                                        Text("Unlimited Overnight Audio Clips • Cough/Snore AI Classifier • Smart Phase Alarm • CSV Export")
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }

                        GothicCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("ACOUSTIC RECORDING PARAMETERS", systemImage: "mic.badge.plus")
                                    .font(Theme.serif(14, weight: .bold))
                                    .foregroundStyle(Theme.crimsonBright)

                                HStack {
                                    Text("Clip Capture Length")
                                        .foregroundStyle(Theme.bone)
                                    Spacer()
                                    Picker("Clip Length", selection: $store.clipDurationSeconds) {
                                        Text("5 sec").tag(5)
                                        Text("8 sec").tag(8)
                                        Text("15 sec").tag(15)
                                        Text("30 sec").tag(30)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 210)
                                }

                                Divider().overlay(Theme.hairline)

                                HStack {
                                    Text("Trigger Sensitivity")
                                        .foregroundStyle(Theme.bone)
                                    Spacer()
                                    Picker("Sensitivity", selection: $store.sensitivityPreset) {
                                        ForEach(SensitivityPreset.allCases) { p in
                                            Text(p.rawValue).tag(p)
                                        }
                                    }
                                    .tint(Theme.crimsonBright)
                                }
                            }
                        }

                        GothicCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("DATA VAULT & CLINICAL EXPORT", systemImage: "externaldrive.fill.badge.timemachine")
                                    .font(Theme.serif(14, weight: .bold))
                                    .foregroundStyle(Theme.crimsonBright)

                                HStack {
                                    Text("Stored Sleep Sessions")
                                        .foregroundStyle(Theme.bone)
                                    Spacer()
                                    Text("\(store.sessions.count) nights (\(store.totalRecordedClipsCount) audio clips)")
                                        .font(Theme.mono(12, weight: .bold))
                                        .foregroundStyle(Theme.crimsonBright)
                                }

                                ShareLink(item: store.exportCSVReport()) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Export Full Sleep & Disturbance Report (.CSV)")
                                            .font(Theme.serif(14, weight: .bold))
                                    }
                                    .foregroundStyle(Theme.bone)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.crimson.opacity(0.45)))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.crimsonBright, lineWidth: 1))
                                }

                                Button {
                                    store.generateAdditionalDemoNight()
                                } label: {
                                    HStack {
                                        Image(systemName: "waveform.badge.plus")
                                        Text("Generate Additional Simulated Night")
                                            .font(Theme.serif(14, weight: .semibold))
                                    }
                                    .foregroundStyle(Theme.bone)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg0))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 1))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle("Coven Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
