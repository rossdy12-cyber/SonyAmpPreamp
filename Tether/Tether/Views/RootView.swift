import SwiftUI
import CoreLocation

struct RootView: View {
    @EnvironmentObject var session: Session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TetherBackground()
            if session.signedIn {
                MainTabs()
            } else {
                OnboardingView()
            }
        }
        .overlay(alignment: .top) {
            BannerView()
        }
        .onAppear {
            session.startServices()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                session.startServices()
            case .background:
                session.stopPolling()
                BackgroundSync.schedule()
            default:
                break
            }
        }
        .alert(
            "SOS alert",
            isPresented: Binding(
                get: { session.sosAlert != nil },
                set: { shown in if !shown { session.sosAlert = nil } }
            ),
            presenting: session.sosAlert
        ) { event in
            if let lat = event.lat, let lon = event.lon {
                Button("Show on map") {
                    session.focus(on: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
            }
            Button("Dismiss", role: .cancel) { }
        } message: { event in
            Text("\(event.memberName) needs help. \(event.text)")
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var session: Session

    var body: some View {
        TabView(selection: $session.selectedTab) {
            MapTab()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(0)
            PlacesView()
                .tabItem { Label("Places", systemImage: "mappin.and.ellipse") }
                .tag(1)
            HistoryView()
                .tabItem { Label("Timeline", systemImage: "clock.arrow.circlepath") }
                .tag(2)
            ActivityView()
                .tabItem { Label("Activity", systemImage: "bell.fill") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .tint(Theme.crimsonBright)
    }
}

/// A small message that slides in at the top (errors, "Checked in", and so on).
struct BannerView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        if let text = session.banner {
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.bone)
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Theme.panel)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.crimsonBright.opacity(0.7), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 8)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: session.banner)
        }
    }
}
