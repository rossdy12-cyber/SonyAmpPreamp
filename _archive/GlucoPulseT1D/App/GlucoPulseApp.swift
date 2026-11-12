import SwiftUI

@main
struct GlucoPulseApp: App {
    @StateObject private var store = GlucoStore()
    @StateObject private var carbStore = CarbPrepStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(carbStore)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject private var store: GlucoStore
    @EnvironmentObject private var carbStore: CarbPrepStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "waveform.path.ecg.rectangle")
                }
                .tag(0)

            BolusCalculatorView()
                .tabItem {
                    Label("Bolus & IOB", systemImage: "SyringeFill".isEmpty ? "drop.halffull" : "cross.vial.fill")
                }
                .tag(1)

            CarbPrepView()
                .tabItem {
                    Label("Carbs & Prep", systemImage: "fork.knife.circle.fill")
                }
                .tag(2)

            PumpHistoryView()
                .tabItem {
                    Label("Log & Rescue", systemImage: "heart.text.square.fill")
                }
                .tag(3)

            SiteRotationView()
                .tabItem {
                    Label("Sites & G7", systemImage: "sensor.tag.radiowaves.forward.fill")
                }
                .tag(4)

            AnalyticsAndSettingsView()
                .tabItem {
                    Label("AGP & Setup", systemImage: "chart.xyaxis.line")
                }
                .tag(5)
        }
        .tint(GlucoTheme.tint)
    }
}
