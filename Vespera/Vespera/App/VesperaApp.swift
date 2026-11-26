import SwiftUI

@main
struct VesperaApp: App {
    @StateObject private var engine = CPDS10Engine()

    init() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor.black
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor.black
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(red: 0.94, green: 0.90, blue: 0.86, alpha: 1.0)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }

    var body: some Scene {
        WindowGroup {
            VesperaRootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}

struct VesperaRootView: View {
    @EnvironmentObject var engine: CPDS10Engine
    @State private var selectedTab: Int = 0

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            if isLandscape || engine.showFullScreenDock {
                // Automatic Full-Screen StandBy Dock HUD when docked horizontally on SHARP CP-DS10 Qi2
                Qi2StandByDockView()
            } else {
                TabView(selection: $selectedTab) {
                    Qi2StandByDockView()
                        .tabItem {
                            Label("CP-DS10 Dock", systemImage: "dock.rectangle")
                        }
                        .tag(0)

                    SoundscapeAlchemyView()
                        .tabItem {
                            Label("Sleep Mixer", systemImage: "moon.stars.fill")
                        }
                        .tag(1)

                    NocturneMusicView()
                        .tabItem {
                            Label("Nocturne", systemImage: "music.quarternote.3")
                        }
                        .tag(2)

                    AcousticsAlarmView()
                        .tabItem {
                            Label("40W DSP & Dawn", systemImage: "hifispeaker.2.fill")
                        }
                        .tag(3)
                }
                .tint(VesperaTheme.ember)
            }
        }
    }
}
