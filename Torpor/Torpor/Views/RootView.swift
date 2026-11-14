import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var engine: SleepAudioEngine
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                SanctumView(switchToChronicles: { selectedTab = 1 })
                    .tabItem {
                        Label("Sanctum", systemImage: "moon.zzz.fill")
                    }
                    .tag(0)

                ChroniclesView()
                    .tabItem {
                        Label("Chronicles", systemImage: "waveform.badge.magnifyingglass")
                    }
                    .tag(1)

                AlchemyView()
                    .tabItem {
                        Label("Alchemy", systemImage: "chart.xyaxis.line")
                    }
                    .tag(2)

                CovenSettingsView()
                    .tabItem {
                        Label("Coven", systemImage: "slider.horizontal.3")
                    }
                    .tag(3)
            }
            .tint(Theme.crimsonBright)

            if engine.isSmartAlarmRinging {
                SmartAlarmRingingOverlay()
                    .transition(.opacity)
            }
        }
    }
}

struct SmartAlarmRingingOverlay: View {
    @EnvironmentObject var store: SleepStore
    @EnvironmentObject var engine: SleepAudioEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            GothicCard(glowing: true) {
                VStack(spacing: 18) {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(Theme.bloodGlow)

                    Text("SMART PHASE AWAKENING")
                        .font(Theme.serif(22, weight: .bold))
                        .foregroundStyle(Theme.bone)

                    Text("Optimal light-slumber phase detected inside your \(store.wakeWindowFormatted) wake window.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 14) {
                        Button {
                            engine.stopSmartAlarm()
                        } label: {
                            Text("Snooze 9m")
                                .font(Theme.serif(15, weight: .semibold))
                                .foregroundStyle(Theme.bone)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Theme.crimsonBright, lineWidth: 1.2)
                                )
                        }

                        Button {
                            engine.stopSmartAlarm()
                            if let session = engine.stopOvernightSession(
                                factors: Array(store.selectedFactors),
                                notes: store.sessionNotesDraft
                            ) {
                                store.addSession(session)
                                store.sessionNotesDraft = ""
                            }
                        } label: {
                            Text("Rise & Save Night")
                                .font(Theme.serif(15, weight: .bold))
                                .foregroundStyle(Theme.bone)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.crimsonBright)
                                )
                        }
                    }
                }
                .padding(8)
            }
            .padding(24)
        }
    }
}
