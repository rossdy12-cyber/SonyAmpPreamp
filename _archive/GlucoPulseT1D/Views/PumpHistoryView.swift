import SwiftUI
import WebKit

struct PumpHistoryView: View {
    @EnvironmentObject private var store: GlucoStore
    @State private var showQuickLogSheet = false
    @State private var showTrueNASPortalSheet = false
    @State private var showSickDaySheet = false
    @State private var logType: PumpEventType = .mealBolus
    @State private var insulinText: String = ""
    @State private var carbsText: String = ""
    @State private var basalText: String = ""
    @State private var ketoneText: String = ""
    @State private var noteText: String = ""

    private var trueNASPortalURL: URL {
        var host = "100.85.127.42"
        if let u = URL(string: store.nightscoutURL), let h = u.host, !h.isEmpty {
            host = h
        }
        return URL(string: "http://\(host):1338") ?? URL(string: "http://100.85.127.42:1338")!
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlucoTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        hypoRescueCard
                        sickDayAndKetoneCard
                        trueNASSyncPortalBanner
                        bleScannerCard
                        pumpLogCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Logbook, Rescue & BLE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showQuickLogSheet = true
                    } label: {
                        Label("Log Event", systemImage: "plus.circle.fill")
                            .foregroundStyle(GlucoTheme.tandemCyan)
                    }
                }
            }
            .sheet(isPresented: $showQuickLogSheet) {
                quickLogSheet
            }
            .sheet(isPresented: $showTrueNASPortalSheet) {
                trueNASPortalSheet
            }
            .sheet(isPresented: $showSickDaySheet) {
                SickDayKetoneSheet()
            }
        }
    }

    // MARK: - 1. 15/15 Hypo Rescue Card

    private var hypoRescueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.heart.fill")
                    .foregroundStyle(GlucoTheme.lowRed)
                Text("15/15 HYPO RESCUE PROTOCOL")
                    .font(.system(size: 11, weight: .heavy, design: .serif))
                    .tracking(0.8)
                    .foregroundStyle(GlucoTheme.lowRed)
                Spacer()
                if store.hypoRescueEndTime != nil {
                    let mins = store.hypoRescueRemainingSeconds / 60
                    let secs = store.hypoRescueRemainingSeconds % 60
                    Text(String(format: "Re-check in %02d:%02d", mins, secs))
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(GlucoTheme.urgentRed, in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            Text("Tap a fast-acting treatment below to log 15g glucose and start an automatic 15-minute BG re-check timer & notification:")
                .font(.system(size: 12))
                .foregroundStyle(GlucoTheme.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                hypoButton(title: "Lift Shot (60ml)", carbs: 15, subtitle: "15g pure glucose")
                hypoButton(title: "4 Jelly Babies", carbs: 16, subtitle: "16g fast sugar")
                hypoButton(title: "5 Dextro Tablets", carbs: 15, subtitle: "15g dextrose")
                hypoButton(title: "Lucozade (170ml)", carbs: 15, subtitle: "15g glucose drink")
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.lowRed.opacity(0.45), lineWidth: 1.5))
    }

    private func hypoButton(title: String, carbs: Int, subtitle: String) -> some View {
        Button {
            store.startHypoRescue(carbsGrams: carbs, treatmentName: title)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GlucoTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(GlucoTheme.lowRed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - 2. NHS / DAFNE Sick-Day & Ketone Advisor Banner

    private var sickDayAndKetoneCard: some View {
        Button {
            showSickDaySheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(GlucoTheme.highAmber)
                    .frame(width: 40, height: 40)
                    .background(GlucoTheme.highAmber.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Blood Ketones & NHS / DAFNE Sick-Day Advisor")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Text("Calculate 10% / 20% TDD ketone correction doses & log blood ketones")
                        .font(.system(size: 11))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GlucoTheme.highAmber)
            }
            .padding(14)
            .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(GlucoTheme.highAmber.opacity(0.4), lineWidth: 1))
        }
    }

    // MARK: - 3. TrueNAS Sync Portal Banner

    private var trueNASSyncPortalBanner: some View {
        Button {
            showTrueNASPortalSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(GlucoTheme.inRangeGreen)
                    .frame(width: 42, height: 42)
                    .background(GlucoTheme.inRangeGreen.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("TrueNAS G7 + Tandem Sync Portal")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Text("Configure Dexcom Share & Tandem Source directly on TrueNAS")
                        .font(.system(size: 11))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(GlucoTheme.tandemCyan)
            }
            .padding(14)
            .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(GlucoTheme.tandemCyan.opacity(0.4), lineWidth: 1))
        }
    }

    private var trueNASPortalSheet: some View {
        NavigationStack {
            TrueNASPortalWebView(url: trueNASPortalURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("TrueNAS Sync Portal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Link(destination: trueNASPortalURL) {
                            Label("Safari", systemImage: "safari")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showTrueNASPortalSheet = false
                            Task { await store.refreshAll() }
                        }
                        .fontWeight(.bold)
                    }
                }
        }
    }

    // MARK: - 4. BLE Proximity Radar Card

    private var bleScannerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(GlucoTheme.tandemCyan)
                        Text("BLE PROXIMITY RADAR")
                            .font(.system(size: 11, weight: .heavy, design: .serif))
                            .tracking(0.8)
                            .foregroundStyle(GlucoTheme.textSecondary)
                    }
                    Text("Detects nearby Dexcom G7 & Tandem t:slim X2 BLE advertisements")
                        .font(.system(size: 12))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
                Spacer()
                Button {
                    store.toggleBLEScan()
                } label: {
                    Text(store.bleScanning ? "Stop" : "Scan BLE")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(store.bleScanning ? GlucoTheme.lowRed : GlucoTheme.tandemCyan, in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            if store.bleDevices.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(GlucoTheme.textSecondary)
                    Text(store.bleScanning ? "Listening for DXCM / t:slim X2 Bluetooth LE packets..." : "Tap 'Scan BLE' to check proximity & RSSI signal strength.")
                        .font(.system(size: 12))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(store.bleDevices) { dev in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dev.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(GlucoTheme.textPrimary)
                            Text(dev.category)
                                .font(.system(size: 11))
                                .foregroundStyle(GlucoTheme.tandemCyan)
                        }
                        Spacer()
                        Text("\(dev.rssi) dBm")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(GlucoTheme.inRangeGreen)
                    }
                    .padding(10)
                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    // MARK: - 5. Full Clinical & Pump Event Log

    private var pumpLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Control-IQ & Clinical Treatment Log")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GlucoTheme.textPrimary)
                Spacer()
                Button("+ Quick Entry") {
                    showQuickLogSheet = true
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(GlucoTheme.tandemCyan)
            }

            ForEach(store.pumpEvents) { ev in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: ev.type.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(iconColor(for: ev.type))
                        .frame(width: 34, height: 34)
                        .background(iconColor(for: ev.type).opacity(0.15), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(ev.type.rawValue)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(GlucoTheme.textPrimary)
                            Spacer()
                            Text(timeAgo(ev.timestamp))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(GlucoTheme.textSecondary)
                        }

                        HStack(spacing: 8) {
                            if let ins = ev.insulinUnits {
                                badge(text: String(format: "%.2f U", ins), color: GlucoTheme.tandemCyan)
                            }
                            if let carbs = ev.carbsGrams {
                                badge(text: "\(carbs)g carbs", color: GlucoTheme.inRangeGreen)
                            }
                            if let rate = ev.basalRate {
                                badge(text: String(format: "%.2f U/hr", rate), color: GlucoTheme.controlIQPurple)
                            }
                            if let ket = ev.ketoneMmol {
                                badge(text: String(format: "%.1f mmol/L ketones", ket), color: GlucoTheme.highAmber)
                            }
                        }

                        if let note = ev.note, !note.isEmpty {
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundStyle(GlucoTheme.textSecondary)
                        }
                    }
                }
                .padding(12)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var quickLogSheet: some View {
        NavigationStack {
            Form {
                Section("Event Type") {
                    Picker("Type", selection: $logType) {
                        ForEach(PumpEventType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                }
                Section("Details") {
                    TextField("Bolus Insulin (Units, e.g. 3.5)", text: $insulinText)
                        .keyboardType(.decimalPad)
                    TextField("Carbs (grams, e.g. 45)", text: $carbsText)
                        .keyboardType(.numberPad)
                    TextField("Basal Rate (U/hr, e.g. 0.95)", text: $basalText)
                        .keyboardType(.decimalPad)
                    TextField("Blood Ketones (mmol/L, e.g. 0.4)", text: $ketoneText)
                        .keyboardType(.decimalPad)
                    TextField("Note (optional)", text: $noteText)
                }
            }
            .navigationTitle("Log Clinical Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showQuickLogSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.logPumpEvent(
                            type: logType,
                            insulin: Double(insulinText),
                            carbs: Int(carbsText),
                            basal: Double(basalText),
                            ketoneMmol: Double(ketoneText),
                            note: noteText.isEmpty ? nil : noteText
                        )
                        insulinText = ""
                        carbsText = ""
                        basalText = ""
                        ketoneText = ""
                        noteText = ""
                        showQuickLogSheet = false
                    }
                }
            }
        }
    }

    private func iconColor(for type: PumpEventType) -> Color {
        switch type {
        case .mealBolus:        return GlucoTheme.inRangeGreen
        case .autoCorrection:   return GlucoTheme.controlIQPurple
        case .manualCorrection: return GlucoTheme.tandemCyan
        case .basalModulation:  return GlucoTheme.controlIQPurple
        case .basalSuspend:     return GlucoTheme.lowRed
        case .carbs:            return GlucoTheme.highAmber
        case .hypoRescue:       return GlucoTheme.urgentRed
        case .ketoneCheck:      return GlucoTheme.highAmber
        case .exercise:         return GlucoTheme.inRangeGreen
        case .siteChange:       return GlucoTheme.tandemCyan
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private func timeAgo(_ date: Date) -> String {
        let mins = max(1, Int(Date().timeIntervalSince(date) / 60))
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h \(mins % 60)m ago"
    }
}

// MARK: - NHS / DAFNE Sick-Day & Blood Ketone Advisor Sheet

struct SickDayKetoneSheet: View {
    @EnvironmentObject private var store: GlucoStore
    @Environment(\.dismiss) private var dismiss
    @State private var ketoneInput: String = "0.8"

    private var ketoneVal: Double {
        Double(ketoneInput.replacingOccurrences(of: ",", with: ".")) ?? 0.0
    }

    private var currentBgMmol: Double {
        store.latestReading?.mmolL ?? 14.2
    }

    private var advice: SickDayAdvice {
        store.evaluateSickDayProtocol(ketonesMmol: ketoneVal, bgMmol: currentBgMmol)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlucoTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Blood Ketone Reading (mmol/L)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(GlucoTheme.textSecondary)

                            HStack(spacing: 12) {
                                TextField("0.8", text: $ketoneInput)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 32, weight: .black, design: .serif))
                                    .foregroundStyle(advice.severityColor)
                                    .padding(12)
                                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 14))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Daily Dose (TDD)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(GlucoTheme.textSecondary)
                                    Text("\(Int(store.tddUnits)) U / day")
                                        .font(.system(size: 18, weight: .heavy, design: .serif))
                                        .foregroundStyle(GlucoTheme.tandemCyan)
                                    Text("10% = \(String(format: "%.1fU", store.tddUnits * 0.1)) · 20% = \(String(format: "%.1fU", store.tddUnits * 0.2))")
                                        .font(.system(size: 11))
                                        .foregroundStyle(GlucoTheme.textSecondary)
                                }
                            }

                            HStack(spacing: 8) {
                                ForEach(["0.3", "0.8", "1.2", "1.8", "2.6", "3.2"], id: \.self) { k in
                                    Button(k) { ketoneInput = k }
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(ketoneInput == k ? advice.severityColor.opacity(0.25) : GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(GlucoTheme.textPrimary)
                                }
                            }
                        }
                        .padding(16)
                        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))

                        VStack(alignment: .leading, spacing: 12) {
                            Text(advice.severityTitle)
                                .font(.system(size: 13, weight: .heavy, design: .serif))
                                .foregroundStyle(advice.severityColor)

                            Text(advice.headline)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(GlucoTheme.textPrimary)

                            ForEach(advice.steps, id: \.self) { step in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .foregroundStyle(advice.severityColor)
                                        .padding(.top, 2)
                                    Text(step)
                                        .font(.system(size: 13))
                                        .foregroundStyle(GlucoTheme.textPrimary)
                                }
                            }

                            Button {
                                store.logPumpEvent(
                                    type: .ketoneCheck,
                                    insulin: advice.recommendedRapidDoseUnits > 0 ? advice.recommendedRapidDoseUnits : nil,
                                    carbs: nil,
                                    basal: nil,
                                    ketoneMmol: ketoneVal,
                                    note: "Blood Ketones: \(String(format: "%.1f", ketoneVal)) mmol/L (\(advice.severityTitle))"
                                )
                                dismiss()
                            } label: {
                                Text(advice.recommendedRapidDoseUnits > 0
                                     ? "Log \(String(format: "%.1f", ketoneVal)) mmol/L Ketones & \(String(format: "%.1f U", advice.recommendedRapidDoseUnits)) Sick-Day Dose"
                                     : "Log \(String(format: "%.1f", ketoneVal)) mmol/L Ketone Check")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(advice.severityColor, in: RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(16)
                        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(advice.severityColor.opacity(0.5), lineWidth: 1.5))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sick-Day & Ketone Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TrueNASPortalWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
