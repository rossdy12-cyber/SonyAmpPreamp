import SwiftUI

struct HomeAssistantTab: View {
    @EnvironmentObject var ha: HomeAssistantService
    @Binding var haBaseURL: String
    @Binding var haToken: String

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()
                VStack(spacing: 0) {
                    if haBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || haToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 44))
                                .foregroundColor(Theme.crimson)
                            Text("Bind the Grimoire")
                                .font(Theme.serif(22, weight: .semibold))
                                .foregroundColor(Theme.bone)
                            Text("Add your Home Assistant URL and Long-Lived Access Token in Rites to summon all your entities here.")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        if ha.isLoading {
                            HStack(spacing: 10) {
                                ProgressView().tint(Theme.crimsonBright)
                                Text("Summoning entities...")
                                    .font(Theme.serif(14))
                                    .foregroundColor(Theme.muted)
                            }
                            .padding(.vertical, 12)
                        }
                        if let err = ha.lastError {
                            Text(err)
                                .font(.footnote)
                                .foregroundColor(Theme.crimsonBright)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                        List {
                            ForEach(ha.entities) { entity in
                                HAEntityRow(entity: entity, baseURL: haBaseURL, token: haToken) {
                                    ha.fetchStates(baseURL: haBaseURL, token: haToken)
                                }
                                .listRowBackground(Theme.panel.opacity(0.9))
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Grimoire")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        ha.fetchStates(baseURL: haBaseURL, token: haToken)
                    }
                    .foregroundColor(Theme.crimsonBright)
                    .disabled(haBaseURL.isEmpty || haToken.isEmpty)
                }
            }
        }
        .onAppear {
            if !haBaseURL.isEmpty && !haToken.isEmpty && ha.entities.isEmpty {
                ha.fetchStates(baseURL: haBaseURL, token: haToken)
            }
        }
    }
}

struct HAEntityRow: View {
    let entity: HAEntity
    let baseURL: String
    let token: String
    let onDone: () -> Void
    @State private var busy = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entity.icon)
                .foregroundColor(entity.isOn ? Theme.crimsonBright : Theme.muted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(entity.friendlyName)
                    .font(Theme.serif(16, weight: .semibold))
                    .foregroundColor(Theme.bone)
                    .lineLimit(1)
                Text("\(entity.entityId) • \(entity.state)")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            if canToggle {
                Button {
                    toggle()
                } label: {
                    Image(systemName: entity.isOn ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 28))
                        .foregroundColor(entity.isOn ? Theme.crimsonBright : Theme.muted)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
    }

    private var canToggle: Bool {
        ["light", "switch", "fan", "cover", "lock", "automation", "script", "scene", "media_player"].contains(entity.domain)
    }

    private func toggle() {
        busy = true
        let service: String
        switch entity.domain {
        case "scene", "script":
            service = "turn_on"
        case "cover":
            service = entity.isOn ? "close_cover" : "open_cover"
        case "lock":
            service = entity.isOn ? "lock" : "unlock"
        case "media_player":
            service = "toggle"
        default:
            service = "toggle"
        }
        let haService = HomeAssistantService()
        haService.callService(baseURL: baseURL, token: token, domain: entity.domain, service: service, entityId: entity.entityId) { _ in
            DispatchQueue.main.async {
                busy = false
                onDone()
            }
        }
    }
}