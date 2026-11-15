import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: StudioStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .top) {
            StudioTheme.bgDeep.ignoresSafeArea()

            if store.isStealthLocked || scenePhase != .active {
                StealthDecoyView()
                    .transition(.opacity)
                    .zIndex(50)
            } else {
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
            }

            if let toast = store.toastMessage, !store.isStealthLocked {
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
        .animation(.easeInOut(duration: 0.2), value: store.isStealthLocked)
        .onChange(of: scenePhase) { newPhase in
            if newPhase != .active && store.requireStealthOnLaunch {
                store.lockStealthImmediately()
            }
        }
    }
}
