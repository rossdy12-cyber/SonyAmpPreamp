import SwiftUI

struct SiteRotationView: View {
    @EnvironmentObject private var store: GlucoStore
    @State private var selectedZone: BodySiteZone = .rightAbdomen
    @State private var selectedDevice: String = "Tandem Cannula"
    @State private var newReservoirUnits: String = "200"
    @State private var changeNote: String = ""
    @State private var showLogConfirmation: Bool = false

    private let deviceChoices = ["Tandem Cannula", "Dexcom G7 Sensor", "Cannula + 200U Cartridge"]

    var body: some View {
        NavigationStack {
            ZStack {
                GlucoTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        hardwareLifespanCard
                        bodySiteGridCard
                        logHardwareRotationCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Sites, Cannula & G7")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 1. Dexcom G7 & Tandem Cannula Lifespan Countdowns

    private var hardwareLifespanCard: some View {
        let g7Elapsed = store.sensorElapsedDays
        let g7Frac = min(1.0, max(0.0, g7Elapsed / 10.0))
        let g7RemHrs = Int(store.sensorRemainingHours.rounded())

        let canElapsed = store.cannulaElapsedDays
        let canFrac = min(1.0, max(0.0, canElapsed / 3.0))
        let canRemHrs = Int(store.cannulaRemainingHours.rounded())

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "timer.circle.fill")
                    .foregroundStyle(GlucoTheme.inRangeGreen)
                Text("SENSOR, CANNULA & CARTRIDGE LIFESPAN")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(GlucoTheme.textSecondary)
                Spacer()
            }

            // Dexcom G7 Sensor Progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Dexcom G7 Sensor (10d + 12h grace)", systemImage: "sensor.tag.radiowaves.forward.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Spacer()
                    Text(g7RemHrs > 0 ? "\(g7RemHrs / 24)d \(g7RemHrs % 24)h left" : "Replace Sensor")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(g7Elapsed > 9.0 ? GlucoTheme.highAmber : GlucoTheme.inRangeGreen)
                }

                ProgressView(value: g7Frac)
                    .tint(g7Elapsed > 9.0 ? GlucoTheme.highAmber : GlucoTheme.inRangeGreen)

                HStack {
                    Text("Started \(String(format: "%.1f days ago", g7Elapsed))")
                        .font(.system(size: 11))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    Spacer()
                    TextField("G7 Pairing Code / Lot", text: $store.sensorCodeNote)
                        .font(.system(size: 11, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(GlucoTheme.tandemCyan)
                }
            }
            .padding(12)
            .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 14))

            // Tandem Infusion Set / Cannula Progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Tandem AutoSoft / TruSteel Cannula (3d)", systemImage: "syringe.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Spacer()
                    Text(canRemHrs > 0 ? "\(canRemHrs)h left" : "Due for Change")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(canElapsed > 2.5 ? GlucoTheme.lowRed : GlucoTheme.tandemCyan)
                }

                ProgressView(value: canFrac)
                    .tint(canElapsed > 2.5 ? GlucoTheme.lowRed : GlucoTheme.tandemCyan)

                HStack {
                    Text("Active for \(String(format: "%.1f days", canElapsed)) (72h clinical target)")
                        .font(.system(size: 11))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    Spacer()
                    Text("Cartridge: \(Int(store.pumpStatus.reservoirUnits)) U")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GlucoTheme.controlIQPurple)
                }
            }
            .padding(12)
            .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    // MARK: - 2. 8-Zone Body-Site Rotation Grid

    private var bodySiteGridCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("8-Zone Body-Site Rotation Tracker")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Text("Green = Rested (≥7d) · Amber = Healing (3–6d) · Cyan = Active (<3d)")
                        .font(.system(size: 11))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(store.bodySites) { site in
                    let color = siteStatusColor(site)
                    let isSelected = (selectedZone == site.zone)
                    Button {
                        selectedZone = site.zone
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(site.zone.shortLabel)
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(GlucoTheme.textPrimary)
                                Spacer()
                                Circle()
                                    .fill(color)
                                    .frame(width: 9, height: 9)
                            }
                            Text(site.readinessStatus)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(color)
                            Text("\(site.lastDeviceType) · \(site.totalUses) uses")
                                .font(.system(size: 10))
                                .foregroundStyle(GlucoTheme.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(12)
                        .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isSelected ? GlucoTheme.inRangeGreen : color.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private func siteStatusColor(_ site: BodySiteRecord) -> Color {
        guard let d = site.daysSinceUse else { return GlucoTheme.inRangeGreen }
        if d < 3 { return GlucoTheme.tandemCyan }
        if d < 7 { return GlucoTheme.highAmber }
        return GlucoTheme.inRangeGreen
    }

    // MARK: - 3. Log New Cannula / Sensor Site Change

    private var logHardwareRotationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log New Site / Sensor Change")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GlucoTheme.textPrimary)

            Picker("Hardware", selection: $selectedDevice) {
                ForEach(deviceChoices, id: \.self) { dev in
                    Text(dev).tag(dev)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Selected Body Zone:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GlucoTheme.textSecondary)
                Spacer()
                Picker("Zone", selection: $selectedZone) {
                    ForEach(BodySiteZone.allCases) { z in
                        Text(z.rawValue).tag(z)
                    }
                }
                .tint(GlucoTheme.inRangeGreen)
            }

            if selectedDevice.contains("Cartridge") || selectedDevice.contains("Cannula") {
                HStack {
                    Text("Filled Cartridge Units (U):")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    Spacer()
                    TextField("200", text: $newReservoirUnits)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 80)
                        .padding(8)
                        .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(GlucoTheme.tandemCyan)
                }
            }

            TextField("Optional note (e.g. AutoSoft 90 6mm, primed 10U)", text: $changeNote)
                .font(.system(size: 13))
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(GlucoTheme.textPrimary)

            if showLogConfirmation {
                Text("Logged \(selectedDevice) at \(selectedZone.rawValue) & reset countdown timer!")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(GlucoTheme.inRangeGreen)
            }

            Button {
                let res = selectedDevice.contains("Sensor") ? nil : Double(newReservoirUnits)
                store.logHardwareChange(
                    deviceType: selectedDevice,
                    zone: selectedZone,
                    reservoirUnits: res,
                    note: changeNote
                )
                changeNote = ""
                showLogConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    Text("Start \(selectedDevice) at \(selectedZone.shortLabel)")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(GlucoTheme.inRangeGreen, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }
}
