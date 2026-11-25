import SwiftUI

@main
struct CovenApp: App {
    @StateObject private var store = DeviceStore()
    @StateObject private var discovery = DiscoveryService()
    @StateObject private var ha = HomeAssistantService()

    init() {
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(discovery)
                .environmentObject(ha)
                .preferredColorScheme(.dark)
                .tint(Theme.crimsonBright)
        }
    }
}