import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var discovery: DiscoveryService
    @EnvironmentObject var ha: HomeAssistantService
    @AppStorage("coven.haBaseURL") private var haBaseURL = ""
    @AppStorage("coven.haToken") private var haToken = ""

    @State private var selectedTab = 0
    @State private var showAdd = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            GothicBackground()
            TabView(selection: $selectedTab) {
                DevicesTab(showAdd: $showAdd, showSettings: $showSettings)
                    .tabItem { Label("Coven", systemImage: "house.fill") }
                    .tag(0)

                DiscoveryTab()
                    .tabItem { Label("Discover", systemImage: "dot.radiowaves.left.and.right") }
                    .tag(1)

                HomeAssistantTab(haBaseURL: $haBaseURL, haToken: $haToken)
                    .tabItem { Label("Grimoire", systemImage: "wand.and.stars") }
                    .tag(2)

                SettingsTab(haBaseURL: $haBaseURL, haToken: $haToken)
                    .tabItem { Label("Rites", systemImage: "gearshape.fill") }
                    .tag(3)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddDeviceView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsTab(haBaseURL: $haBaseURL, haToken: $haToken)
                .environmentObject(store)
                .environmentObject(ha)
        }
    }
}