import SwiftUI
import UIKit

@main
struct AegisApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BrowserScreen()
                .gothicChrome()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                BrowserModel.shared.persistTabsPublic()
            }
        }
    }
}
