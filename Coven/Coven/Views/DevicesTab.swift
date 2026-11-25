import SwiftUI

struct DevicesTab: View {
    @EnvironmentObject var store: DeviceStore
    @Binding var showAdd: Bool
    @Binding var showSettings: Bool
    @State private var selectedRoom: String = "All"
    @State private var selectedDevice: SmartDevice? = nil

    private var roomOptions: [String] {
        ["All"] + store.rooms
    }

    private var filteredDevices: [SmartDevice] {
        if selectedRoom == "All" { return store.devices }
        return store.devices.filter { $0.room == selectedRoom }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GothicBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        roomPicker
                        if filteredDevices.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredDevices) { device in
                                    DeviceCard(device: device) {
                                        selectedDevice = device
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedDevice) { device in
                DeviceDetailView(device: device)
                    .environmentObject(store)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("COVEN")
                    .font(Theme.serif(32, weight: .bold))
                    .foregroundColor(Theme.bone)
                Text("Command your dark domain")
                    .font(Theme.serif(14, weight: .regular))
                    .foregroundColor(Theme.muted)
            }
            Spacer()
            Button { showAdd = true } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.crimsonBright)
            }
        }
    }

    private var roomPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(roomOptions, id: \.self) { room in
                    Button {
                        selectedRoom = room
                    } label: {
                        Text(room)
                            .font(Theme.serif(14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedRoom == room ? Theme.crimson : Theme.panel)
                            .foregroundColor(selectedRoom == room ? .white : Theme.bone)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Theme.hairline, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 44))
                .foregroundColor(Theme.crimson)
            Text("No devices in this chamber")
                .font(Theme.serif(20, weight: .semibold))
                .foregroundColor(Theme.bone)
            Text("Add a device manually, discover devices on your network, or connect Home Assistant in the Grimoire tab.")
                .font(.system(size: 14))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
            Button { showAdd = true } label: {
                Label("Add Device", systemImage: "plus")
                    .font(Theme.serif(15, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Theme.crimson)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}