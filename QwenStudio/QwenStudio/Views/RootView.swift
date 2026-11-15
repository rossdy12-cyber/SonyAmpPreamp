import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: StudioStore

    var body: some View {
        ZStack(alignment: .top) {
            StudioTheme.bgDeep.ignoresSafeArea()

            TabView(selection: $store.selectedTab) {
                StudioCanvasView()
                    .tabItem {
                        Label("Studio", systemImage: "wand.and.stars")
                    }
                    .tag(0)

                PromptAlchemistView()
                    .tabItem {
                        Label("Alchemist", systemImage: "sparkles")
                    }
                    .tag(1)

                VaultGalleryView()
                    .tabItem {
                        Label("Vault", systemImage: "photo.on.rectangle.angled")
                    }
                    .tag(2)

                SettingsBridgeView()
                    .tabItem {
                        Label("GPU Link", systemImage: "bolt.horizontal.icloud.fill")
                    }
                    .tag(3)
            }
            .tint(StudioTheme.crimson)

            if let toast = store.toastMessage {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(StudioTheme.crimson.opacity(0.95))
                            .shadow(color: StudioTheme.crimson.opacity(0.5), radius: 10, y: 4)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.toastMessage)
    }
}
