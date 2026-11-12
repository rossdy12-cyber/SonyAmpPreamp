import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject private var store: GlucoStore
    @State private var selectedHours: Int = 6
    private let hourChoices = [3, 6, 12, 24]

    private var filteredReadings: [GlucoseReading] {
        let cutoff = Date().addingTimeInterval(-Double(selectedHours) * 3600)
        return store.readings.filter { $0.timestamp >= cutoff }
    }

    private var filteredBoluses: [PumpEvent] {
        let cutoff = Date().addingTimeInterval(-Double(selectedHours) * 3600)
        return store.pumpEvents.filter {
            $0.timestamp >= cutoff && ($0.insulinUnits ?? 0) > 0
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlucoTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        statusHeaderBar
                        if store.hypoRescueEndTime != nil {
                            activeHypoCountdownBanner
                        } else if let hypoMins = store.predictedHypoInMinutes {
                            predictiveHypoWarningBanner(mins: hypoMins)
                        }
                        glucoseHeroCard
                        quickActionRow
                        tandemStatusCard
                        combinedChartCard
                        timeInRangeCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await store.refreshAll()
                }
            }
            .navigationTitle("GlucoPulse T1D")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        store.unit = (store.unit == .mmolL) ? .mgdL : .mmolL
                    } label: {
                        Text(store.unit.rawValue)
                            .font(.system(size: 12, weight: .bold, design: .serif))
                            .foregroundStyle(GlucoTheme.tandemCyan)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(GlucoTheme.cardElevated, in: Capsule())
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        if store.isSyncing {
                            ProgressView().tint(GlucoTheme.inRangeGreen)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(GlucoTheme.inRangeGreen)
                        }
                    }
                }
            }
        }
    }

    private var statusHeaderBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.connectionSummary.contains("Simulated") ? GlucoTheme.highAmber : GlucoTheme.inRangeGreen)
                .frame(width: 8, height: 8)
            Text(store.connectionSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GlucoTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            Text("G7: \(String(format: "%.1fd", store.sensorElapsedDays))/10d")
                .font(.system(size: 11, weight: .bold, design: .serif))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(GlucoTheme.cardElevated, in: Capsule())
                .foregroundStyle(GlucoTheme.textPrimary)
        }
    }

    private var activeHypoCountdownBanner: some View {
        let mins = store.hypoRescueRemainingSeconds / 60
        let secs = store.hypoRescueRemainingSeconds % 60
        return HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("15/15 HYPO RESCUE TIMER ACTIVE")
                    .font(.system(size: 11, weight: .heavy, design: .serif))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Re-check BG in \(String(format: "%02d:%02d", mins, secs)) · \(store.lastHypoRescueNote)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                store.cancelHypoRescueTimer()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(14)
        .background(GlucoTheme.urgentRed, in: RoundedRectangle(cornerRadius: 16))
    }

    private func predictiveHypoWarningBanner(mins: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(GlucoTheme.lowRed)
            VStack(alignment: .leading, spacing: 2) {
                Text(mins == 0 ? "LOW GLUCOSE ALERT" : "PREDICTIVE LOW IN ~\(mins) MIN")
                    .font(.system(size: 11, weight: .heavy, design: .serif))
                    .foregroundStyle(GlucoTheme.lowRed)
                Text("30m forecast: \(store.formatGlucose(store.predicted30MinMgdL)) \(store.unit.rawValue) · Active IOB: \(String(format: "%.2f U", store.effectiveIOBUnits))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GlucoTheme.textPrimary)
            }
            Spacer()
            Button {
                store.startHypoRescue(carbsGrams: 15, treatmentName: "15g Fast Glucose")
            } label: {
                Text("15g Rescue")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(GlucoTheme.lowRed, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(14)
        .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GlucoTheme.lowRed.opacity(0.6), lineWidth: 1.5))
    }

    private var glucoseHeroCard: some View {
        let latest = store.latestReading
        let mgdL = latest?.mgdL ?? 110
        let glucoseColor = store.color(for: mgdL)
        let minsAgo = latest.map { max(0, Int(Date().timeIntervalSince($0.timestamp) / 60)) } ?? 0
        let predMgdL = store.predicted30MinMgdL
        let predColor = store.color(for: predMgdL)

        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .foregroundStyle(GlucoTheme.inRangeGreen)
                    Text("DEXCOM G7 CGM")
                        .font(.system(size: 11, weight: .heavy, design: .serif))
                        .tracking(0.8)
                        .foregroundStyle(GlucoTheme.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.formatGlucose(mgdL))
                        .font(.system(size: 54, weight: .black, design: .serif))
                        .foregroundStyle(glucoseColor)

                    Text(latest?.trend.arrow ?? "→")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(glucoseColor)
                }

                HStack(spacing: 10) {
                    Text("\(store.deltaString) \(store.unit.rawValue)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(glucoseColor.opacity(0.16), in: Capsule())
                        .foregroundStyle(glucoseColor)

                    Text(latest?.trend.label ?? "Steady")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GlucoTheme.textPrimary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 9) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(minsAgo == 0 ? "Just now" : "\(minsAgo)m ago")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Text("5m G7 interval")
                        .font(.system(size: 11))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }

                Divider().frame(width: 85)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("30m Forecast")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    Text("\(store.formatGlucose(predMgdL)) \(store.unit.rawValue)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(predColor)
                }
            }
        }
        .padding(18)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(glucoseColor.opacity(0.35), lineWidth: 1.5))
    }

    private var quickActionRow: some View {
        HStack(spacing: 10) {
            Button {
                store.selectedTab = 1
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cross.vial.fill")
                    Text("Smart Bolus")
                }
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(GlucoTheme.tandemCyan.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(GlucoTheme.tandemCyan)
            }

            Button {
                store.selectedTab = 2
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "barcode.viewfinder")
                    Text("UK Carbs & Prep")
                }
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(GlucoTheme.inRangeGreen.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(GlucoTheme.inRangeGreen)
            }

            Button {
                store.startHypoRescue(carbsGrams: 15, treatmentName: "15g Fast Glucose")
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.heart.fill")
                    Text("15g Hypo")
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GlucoTheme.lowRed.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(GlucoTheme.lowRed)
            }
        }
    }

    private var tandemStatusCard: some View {
        let p = store.pumpStatus
        let bolusMinsAgo = max(1, Int(Date().timeIntervalSince(p.lastBolusDate) / 60))
        let bolusAgoText = bolusMinsAgo >= 60
            ? "\(bolusMinsAgo / 60)h \(bolusMinsAgo % 60)m ago"
            : "\(bolusMinsAgo)m ago"

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "drop.transmission")
                        .foregroundStyle(GlucoTheme.tandemCyan)
                    Text("TANDEM t:slim X2")
                        .font(.system(size: 11, weight: .heavy, design: .serif))
                        .tracking(0.8)
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                    Text(p.controlIQMode)
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(GlucoTheme.controlIQPurple.opacity(0.2), in: Capsule())
                .foregroundStyle(GlucoTheme.controlIQPurple)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                pumpTile(
                    title: "Active IOB (\(Int(store.diaHours))h DIA)",
                    value: String(format: "%.2f U", store.effectiveIOBUnits),
                    subtitle: "COB: \(p.cobGrams)g active",
                    symbol: "drop.fill",
                    color: GlucoTheme.tandemCyan
                )

                pumpTile(
                    title: "Control-IQ Basal",
                    value: String(format: "%.2f U/hr", p.activeBasalRate),
                    subtitle: String(format: "Profile: %.2f U/hr", p.scheduledBasalRate),
                    symbol: "waveform.path.ecg",
                    color: GlucoTheme.controlIQPurple
                )

                pumpTile(
                    title: "Last Bolus",
                    value: String(format: "%.2f U", p.lastBolusUnits),
                    subtitle: bolusAgoText,
                    symbol: "clock.arrow.circlepath",
                    color: GlucoTheme.inRangeGreen
                )

                pumpTile(
                    title: "Pump & Cartridge",
                    value: "\(Int(p.reservoirUnits)) U",
                    subtitle: "Battery: \(p.batteryPercent)% · Cannula \(String(format: "%.1fd", store.cannulaElapsedDays))",
                    symbol: "battery.75percent",
                    color: p.batteryPercent < 25 ? GlucoTheme.lowRed : GlucoTheme.highAmber
                )
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private func pumpTile(title: String, value: String, subtitle: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GlucoTheme.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .serif))
                .foregroundStyle(GlucoTheme.textPrimary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(GlucoTheme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 14))
    }

    private var combinedChartCard: some View {
        let lowVal = store.unit == .mmolL ? Double(store.lowMgdL) / 18.0182 : Double(store.lowMgdL)
        let highVal = store.unit == .mmolL ? Double(store.highMgdL) / 18.0182 : Double(store.highMgdL)
        let yMin = store.unit == .mmolL ? 2.0 : 40.0
        let yMax = store.unit == .mmolL ? 18.0 : 320.0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("G7 Glucose & t:slim X2 Bolus Timeline")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Text("Green = In Range · Cyan Drops = Tandem Boluses")
                        .font(.system(size: 11))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
                Spacer()
                Picker("Window", selection: $selectedHours) {
                    ForEach(hourChoices, id: \.self) { h in
                        Text("\(h)h").tag(h)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 165)
            }

            Chart {
                RectangleMark(
                    yStart: .value("Low", lowVal),
                    yEnd: .value("High", highVal)
                )
                .foregroundStyle(GlucoTheme.inRangeGreen.opacity(0.08))

                RuleMark(y: .value("High Target", highVal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(GlucoTheme.highAmber.opacity(0.6))

                RuleMark(y: .value("Low Target", lowVal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(GlucoTheme.lowRed.opacity(0.6))

                ForEach(filteredReadings) { r in
                    let yVal = store.unit == .mmolL ? r.mmolL : Double(r.mgdL)
                    LineMark(
                        x: .value("Time", r.timestamp),
                        y: .value("Glucose", yVal)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(GlucoTheme.inRangeGreen.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 2.2))

                    PointMark(
                        x: .value("Time", r.timestamp),
                        y: .value("Glucose", yVal)
                    )
                    .symbolSize(22)
                    .foregroundStyle(store.color(for: r.mgdL))
                }

                ForEach(filteredBoluses) { ev in
                    PointMark(
                        x: .value("Bolus Time", ev.timestamp),
                        y: .value("Bolus Marker", yMin + (yMax - yMin) * 0.08)
                    )
                    .symbol(.circle)
                    .symbolSize(75)
                    .foregroundStyle(GlucoTheme.tandemCyan)
                    .annotation(position: .top, spacing: 2) {
                        if let u = ev.insulinUnits {
                            Text(String(format: "%.1fU", u))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(GlucoTheme.tandemCyan)
                        }
                    }
                }
            }
            .chartYScale(domain: yMin...yMax)
            .frame(height: 220)
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var timeInRangeCard: some View {
        let tir = store.timeInRangePercent
        let low = store.timeBelowRangePercent
        let high = store.timeAboveRangePercent

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("24-Hour Combined Summary")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(GlucoTheme.textPrimary)
                Spacer()
                Text("CV \(String(format: "%.1f%%", store.cvPercent)) · \(store.estimatedIfccMmolMol) mmol/mol")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GlucoTheme.textSecondary)
            }

            GeometryReader { geo in
                HStack(spacing: 3) {
                    if low > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GlucoTheme.lowRed)
                            .frame(width: max(8, geo.size.width * CGFloat(low) / 100.0))
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(GlucoTheme.inRangeGreen)
                        .frame(width: max(12, geo.size.width * CGFloat(tir) / 100.0))
                    if high > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GlucoTheme.highAmber)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 12) {
                summaryStat(label: "In Range", value: "\(tir)%", color: GlucoTheme.inRangeGreen)
                summaryStat(label: "High", value: "\(high)%", color: GlucoTheme.highAmber)
                summaryStat(label: "Low", value: "\(low)%", color: GlucoTheme.lowRed)
                summaryStat(label: "Average", value: "\(store.formatGlucose(store.averageMgdL))", color: GlucoTheme.textPrimary)
                summaryStat(label: "GMI (A1c)", value: store.gmiPercent, color: GlucoTheme.tandemCyan)
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private func summaryStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(GlucoTheme.textSecondary)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .serif))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
