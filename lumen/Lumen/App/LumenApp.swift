import SwiftUI

@main
struct LumenApp: App {
    var body: some Scene {
        WindowGroup {
            CameraView()
                .preferredColorScheme(.dark)
                .tint(LumenTheme.accent)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
