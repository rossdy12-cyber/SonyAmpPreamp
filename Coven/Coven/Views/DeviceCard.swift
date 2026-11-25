import SwiftUI

struct DeviceCard: View {
    @EnvironmentObject var store: DeviceStore
    let device: SmartDevice
    let onTap: () -> Void
    @State private var isSending = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(device.isOn ? Theme.crimson.opacity(0.25) : Color.black.opacity(0.25))
                        .frame(width: 52, height: 52)
                    Image(systemName: device.kind.icon)
                        .font(.system(size: 22))
                        .foregroundColor(device.isOn ? Theme.crimsonBright : Theme.muted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name.isEmpty ? "Unnamed Device" : device.name)
                        .font(Theme.serif(17, weight: .semibold))
                        .foregroundColor(Theme.bone)
                        .lineLimit(1)
                    Text("\(device.room) • \(device.displayAddress)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }

                Spacer()

                if device.kind == .switchDevice || device.kind == .light || device.kind == .generic {
                    Button {
                        quickToggle()
                    } label: {
                        Image(systemName: device.isOn ? "power.circle.fill" : "power.circle")
                            .font(.system(size: 30))
                            .foregroundColor(device.isOn ? Theme.crimsonBright : Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundColor(Theme.muted)
                }
            }
            .padding(14)
            .background(Theme.panel.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func quickToggle() {
        let targetOn = !device.isOn
        let raw = targetOn ? (device.onURL.isEmpty ? device.toggleURL : device.onURL) : (device.offURL.isEmpty ? device.toggleURL : device.offURL)
        let url = NetworkService.normalizeURL(raw, host: device.host, port: device.port)
        guard !url.isEmpty else { return }
        isSending = true
        NetworkService.sendRequest(urlString: url) { result in
            DispatchQueue.main.async {
                isSending = false
                if case .success = result {
                    var updated = device
                    updated.isOn = targetOn
                    updated.lastSeen = Date()
                    store.update(updated)
                }
            }
        }
    }
}