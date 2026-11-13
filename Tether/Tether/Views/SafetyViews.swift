import SwiftUI

/// The bottom strip on the map: check in, SOS, and the "SOS sent" state.
struct SafetyBar: View {
    @EnvironmentObject var session: Session

    @State private var showCheckInSheet = false
    @State private var sending = false

    var body: some View {
        VStack(spacing: 10) {
            if session.sosActive {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color.white)
                    Text("SOS sent. Your circle has your location.")
                        .font(.subheadline)
                        .foregroundColor(Color.white)
                    Spacer()
                    Button("Cancel SOS") {
                        Task { await session.cancelSOS() }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.35))
                    .clipShape(Capsule())
                }
                .padding(12)
                .background(Theme.crimson)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        sending = true
                        await session.checkIn(text: "")
                        Haptics.success()
                        sending = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(sending ? "Sending..." : "I'm here")
                    }
                }
                .buttonStyle(CrimsonButtonStyle(filled: false))
                .disabled(sending)

                Button {
                    showCheckInSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Theme.crimsonBright)
                        .frame(width: 46, height: 46)
                        .background(Theme.panel.opacity(0.92))
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                        .clipShape(Circle())
                }

                SOSHoldButton()
            }
            .padding(10)
            .background(Theme.bg0.opacity(0.88))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .sheet(isPresented: $showCheckInSheet) {
            CheckInSheet()
                .presentationDetents([.height(260)])
                .presentationBackground(Theme.bg0)
        }
    }
}

/// Hold for three seconds to send an SOS. Letting go early cancels it.
struct SOSHoldButton: View {
    @EnvironmentObject var session: Session

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().fill(Theme.crimson)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)
            Text("SOS")
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(Color.white)
        }
        .frame(width: 62, height: 62)
        .onLongPressGesture(minimumDuration: 3, maximumDistance: 80, pressing: { pressing in
            if pressing {
                Haptics.tick()
                withAnimation(.linear(duration: 3)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }, perform: {
            Haptics.warning()
            Task { await session.sendSOS() }
        })
        .accessibilityLabel("SOS. Press and hold for three seconds.")
    }
}

/// A check-in with an optional note, such as "On my way".
struct CheckInSheet: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var sending = false

    var body: some View {
        ZStack {
            TetherBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("Check in")
                    .font(Theme.serif(24))
                    .foregroundColor(Theme.bone)
                TetherField(title: "Optional note", text: $text, capitalization: .sentences)
                Button {
                    Task {
                        sending = true
                        await session.checkIn(text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                        sending = false
                        dismiss()
                    }
                } label: {
                    Text(sending ? "Sending..." : "Send check-in")
                }
                .buttonStyle(CrimsonButtonStyle())
                .disabled(sending)
                Spacer()
            }
            .padding(20)
        }
    }
}
