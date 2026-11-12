import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            TrueNASDirectPoolBrowserView()
                .tabItem {
                    Label("ZFS & Files", systemImage: "externaldrive.fill.badge.checkmark")
                }

            VaultPhotoPulseTabView()
                .tabItem {
                    Label("PhotoPulse", systemImage: "photo.on.rectangle.angled")
                }

            VaultScanOCRTabView()
                .tabItem {
                    Label("VaultScan", systemImage: "doc.viewfinder.fill")
                }

            PhotoVaultEnclaveTabView()
                .tabItem {
                    Label("Enclave", systemImage: "faceid")
                }

            LinkVaultReaderTabView()
                .tabItem {
                    Label("LinkVault", systemImage: "bookmark.square.fill")
                }
        }
        .tint(Color(red: 1.0, green: 0.302, blue: 0.427))
    }
}
