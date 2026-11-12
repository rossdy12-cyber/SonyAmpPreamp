import SwiftUI
import Charts

struct AnalyticsAndSettingsView: View {
    @EnvironmentObject private var store: GlucoStore
    @State private var selectedSection: Int = 0 // 0 = Clinical AGP Report, 1 = Therapy & Ratios, 2 = Cloud Sources
    @State private var syncFeedback: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GlucoTheme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    Picker("Section", selection: $selectedSection) {
                        Text("AGP & HbA1c").tag(0)
                        Text("ICR & ISF").tag(1)
                        Text("Cloud & Sync").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    ScrollView {
                        VStack(spacing: 16) {
                            if selectedSection == 0 {
                                clinicalMetricsCard
                                fiveTierTirCard
                                agpModalDayChartCard
                                exportReportCard
                            } else if selectedSection == 1 {
                                insulinParamsCard
                                timeOfDayBlocksEditorCard
                            } else {
                                dexcomShareCard
                                nightscoutCard
                                libreAndHealthKitCard
                                alertsAndThresholdsCard
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationTitle("AGP Report & Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 1. Clinical AGP & Glycaemic Metrics Card

    private var clinicalMetricsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "waveform.path.ecg.text.clipboard.fill")
                    .foregroundStyle(GlucoTheme.tandemCyan)
                Text("AMBULATORY GLUCOSE PROFILE (AGP) SUMMARY")
                    .font(.system(size: 11, weight: .heavy, design: .serif))
                    .tracking(0.8)
                    .foregroundStyle(GlucoTheme.textSecondary)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                agpTile(title: "GMI (eA1c)", value: store.gmiPercent, sub: "\(store.estimatedIfccMmolMol) mmol/mol", color: GlucoTheme.tandemCyan)
                agpTile(title: "Mean Glucose", value: "\(store.formatGlucose(store.averageMgdL))", sub: store.unit.rawValue, color: GlucoTheme.textPrimary)
                agpTile(title: "Glycaemic CV%", value: String(format: "%.1f%%", store.cvPercent), sub: store.cvPercent <= 36.0 ? "Target ≤36% ✓" : "Target ≤36%", color: store.cvPercent <= 36.0 ? GlucoTheme.inRangeGreen : GlucoTheme.highAmber)
                agpTile(title: "Time In Range", value: "\(store.timeInRangePercent)%", sub: "3.9–10.0 mmol/L", color: GlucoTheme.inRangeGreen)
                agpTile(title: "Tight Range", value: "\(store.tightRangePercent)%", sub: "3.9–7.8 mmol/L", color: GlucoTheme.controlIQPurple)
                agpTile(title: "Std Dev (SD)", value: store.standardDeviationFormatted, sub: "Variability", color: GlucoTheme.highAmber)
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private func agpTile(title: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(GlucoTheme.textSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 18, weight: .black, design: .serif))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(sub)
                .font(.system(size: 10))
                .foregroundStyle(GlucoTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private var fiveTierTirCard: some View {
        let vHigh = store.veryHighPercent
        let highOnly = max(0, store.timeAboveRangePercent - vHigh)
        let tir = store.timeInRangePercent
        let vLow = store.veryLowPercent
        let lowOnly = max(0, store.timeBelowRangePercent - vLow)

        return VStack(alignment: .leading, spacing: 10) {
            Text("International Consensus 5-Tier Time in Range")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(GlucoTheme.textPrimary)

            tirRow(label: "Very High (>13.9 mmol/L / >250 mg/dL)", pct: vHigh, target: "Target <5%", color: GlucoTheme.lowRed)
            tirRow(label: "High (10.1–13.9 mmol/L / 181–250 mg/dL)", pct: highOnly, target: "Target <25%", color: GlucoTheme.highAmber)
            tirRow(label: "In Range (3.9–10.0 mmol/L / 70–180 mg/dL)", pct: tir, target: "Target >70%", color: GlucoTheme.inRangeGreen)
            tirRow(label: "Low (3.0–3.8 mmol/L / 54–69 mg/dL)", pct: lowOnly, target: "Target <4%", color: GlucoTheme.lowRed)
            tirRow(label: "Very Low (<3.0 mmol/L / <54 mg/dL)", pct: vLow, target: "Target <1%", color: GlucoTheme.urgentRed)
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private func tirRow(label: String, pct: Int, target: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GlucoTheme.textPrimary)
            Spacer()
            Text(target)
                .font(.system(size: 10))
                .foregroundStyle(GlucoTheme.textSecondary)
            Text("\(pct)%")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .frame(width: 42, alignment: .trailing)
                .foregroundStyle(color)
        }
    }

    private var agpModalDayChartCard: some View {
        let buckets = store.agpHourlyQuartiles
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("24-Hour AGP Modal Day (Median + 25–75% IQR Band)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GlucoTheme.textPrimary)
                Text("Hourly glucose percentiles across 00:00–23:00 (\(store.unit.rawValue))")
                    .font(.system(size: 11))
                    .foregroundStyle(GlucoTheme.textSecondary)
            }

            Chart(buckets) { b in
                AreaMark(
                    x: .value("Hour", b.hour),
                    yStart: .value("P10", b.p10),
                    yEnd: .value("P90", b.p90)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(GlucoTheme.tandemCyan.opacity(0.12))

                AreaMark(
                    x: .value("Hour", b.hour),
                    yStart: .value("P25", b.p25),
                    yEnd: .value("P75", b.p75)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(GlucoTheme.inRangeGreen.opacity(0.26))

                LineMark(
                    x: .value("Hour", b.hour),
                    y: .value("Median", b.p50)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(GlucoTheme.inRangeGreen)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            .chartXScale(domain: 0...23)
            .frame(height: 190)
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var exportReportCard: some View {
        let csv = store.exportClinicalCSV()
        return ShareLink(item: csv, preview: SharePreview("GlucoPulse Clinical AGP & Logbook CSV")) {
            HStack {
                Image(systemName: "square.and.arrow.up.fill")
                Text("Export Clinical AGP & Logbook CSV Report")
                    .fontWeight(.bold)
            }
            .font(.system(size: 13))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(GlucoTheme.tandemCyan, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.black)
        }
    }

    // MARK: - 2. Therapy Profile & ICR / ISF Editor

    private var insulinParamsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Core Insulin Action & Total Daily Dose")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GlucoTheme.textPrimary)

            HStack {
                Text("Duration of Insulin Action (DIA):")
                    .font(.system(size: 13))
                    .foregroundStyle(GlucoTheme.textSecondary)
                Spacer()
                Stepper(value: $store.diaHours, in: 2.5...6.0, step: 0.5) {
                    Text(String(format: "%.1f hours", store.diaHours))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GlucoTheme.tandemCyan)
                }
            }

            HStack {
                Text("Typical Total Daily Dose (TDD):")
                    .font(.system(size: 13))
                    .foregroundStyle(GlucoTheme.textSecondary)
                Spacer()
                Stepper(value: $store.tddUnits, in: 10.0...150.0, step: 1.0) {
                    Text("\(Int(store.tddUnits)) U/day")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GlucoTheme.inRangeGreen)
                }
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var timeOfDayBlocksEditorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Time-of-Day ICR, ISF & Target BG")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(GlucoTheme.textPrimary)

            ForEach($store.therapyBlocks) { $block in
                VStack(alignment: .leading, spacing: 8) {
                    Text(block.label)
                        .font(.system(size: 13, weight: .heavy, design: .serif))
                        .foregroundStyle(GlucoTheme.tandemCyan)

                    HStack {
                        Text("Carb Ratio (ICR):")
                            .font(.system(size: 12))
                            .foregroundStyle(GlucoTheme.textSecondary)
                        Spacer()
                        Stepper(value: $block.icrGramsPerUnit, in: 3.0...30.0, step: 0.5) {
                            Text("1U : \(String(format: "%.1fg", block.icrGramsPerUnit))")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(GlucoTheme.inRangeGreen)
                        }
                    }

                    HStack {
                        Text("Correction Factor (ISF):")
                            .font(.system(size: 12))
                            .foregroundStyle(GlucoTheme.textSecondary)
                        Spacer()
                        Stepper(value: $block.isfMmolPerUnit, in: 0.5...10.0, step: 0.1) {
                            Text("1U : \(String(format: "%.1f mmol/L", block.isfMmolPerUnit))")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(GlucoTheme.textPrimary)
                        }
                    }

                    HStack {
                        Text("Target Glucose:")
                            .font(.system(size: 12))
                            .foregroundStyle(GlucoTheme.textSecondary)
                        Spacer()
                        Stepper(value: $block.targetMmol, in: 4.5...8.5, step: 0.2) {
                            Text(String(format: "%.1f mmol/L", block.targetMmol))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(GlucoTheme.controlIQPurple)
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

    // MARK: - 3. Cloud Sources & Alerts Setup

    private var dexcomShareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Dexcom G7 Share Cloud", systemImage: "sensor.tag.radiowaves.forward.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(GlucoTheme.inRangeGreen)

            TextField("Dexcom Username / Email / +44 Phone", text: $store.dexcomUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(GlucoTheme.textPrimary)

            SecureField("Dexcom Password", text: $store.dexcomPassword)
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(GlucoTheme.textPrimary)

            Picker("Region", selection: $store.dexcomRegion) {
                ForEach(DexcomRegion.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .tint(GlucoTheme.tandemCyan)

            if !store.dexcomDiagnostic.isEmpty {
                Text(store.dexcomDiagnostic)
                    .font(.system(size: 11))
                    .foregroundStyle(GlucoTheme.highAmber)
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var nightscoutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Nightscout / Tandem tconnectsync Bridge", systemImage: "drop.transmission")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(GlucoTheme.tandemCyan)

            TextField("http://100.85.127.42:1337", text: $store.nightscoutURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(GlucoTheme.textPrimary)

            SecureField("Nightscout API Secret / Token (optional)", text: $store.nightscoutToken)
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(GlucoTheme.textPrimary)

            Button {
                Task {
                    await store.refreshAll()
                    syncFeedback = "Synced: \(store.connectionSummary)"
                }
            } label: {
                HStack {
                    Image(systemName: "bolt.horizontal.circle.fill")
                    Text("Connect & Sync All Sources Now")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(GlucoTheme.inRangeGreen, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.black)
            }

            if !syncFeedback.isEmpty {
                Text(syncFeedback)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GlucoTheme.inRangeGreen)
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var libreAndHealthKitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("LibreLinkUp & Apple HealthKit", systemImage: "heart.text.square.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(GlucoTheme.controlIQPurple)

            TextField("LibreLinkUp Email (optional)", text: $store.libreEmail)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(GlucoTheme.textPrimary)

            SecureField("LibreLinkUp Password", text: $store.librePassword)
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(GlucoTheme.textPrimary)

            Toggle("Sync with Apple HealthKit", isOn: $store.healthKitEnabled)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GlucoTheme.textPrimary)
                .tint(GlucoTheme.inRangeGreen)
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var alertsAndThresholdsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Glucose Units & Alert Thresholds", systemImage: "bell.badge.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(GlucoTheme.highAmber)

            Picker("Display Units", selection: $store.unit) {
                ForEach(GlucoseUnit.allCases) { u in
                    Text(u.rawValue).tag(u)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Local Hypo / Hyper Notifications", isOn: $store.notificationsEnabled)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GlucoTheme.textPrimary)
                .tint(GlucoTheme.inRangeGreen)
                .onChange(of: store.notificationsEnabled) { enabled in
                    if enabled { store.requestNotificationPermission() }
                }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }
}
