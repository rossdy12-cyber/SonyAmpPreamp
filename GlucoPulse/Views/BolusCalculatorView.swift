import SwiftUI
import Charts

struct BolusCalculatorView: View {
    @EnvironmentObject private var store: GlucoStore

    @State private var carbsInput: String = "45"
    @State private var bgInputMmol: String = ""
    @State private var fatInput: String = ""
    @State private var proteinInput: String = ""
    @State private var mealNote: String = ""
    @State private var exerciseChoice: ExerciseAdjustment = .none
    @State private var reverseCorrection: Bool = true
    @State private var loggedBannerText: String = ""

    private var currentBgMmol: Double {
        if let typed = Double(bgInputMmol.replacingOccurrences(of: ",", with: ".")), typed > 0 {
            return store.unit == .mmolL ? typed : (typed / 18.0182)
        }
        return store.latestReading?.mmolL ?? 6.2
    }

    private var calculation: SmartBolusResult {
        let carbs = Double(carbsInput.replacingOccurrences(of: ",", with: ".")) ?? 0
        let fat = Double(fatInput.replacingOccurrences(of: ",", with: ".")) ?? 0
        let prot = Double(proteinInput.replacingOccurrences(of: ",", with: ".")) ?? 0
        return store.calculateSmartBolus(
            carbsGrams: carbs,
            currentBgMmol: currentBgMmol,
            fatGrams: fat,
            proteinGrams: prot,
            exercise: exerciseChoice,
            includeReverseCorrection: reverseCorrection
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlucoTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        activeProfileBanner
                        if !loggedBannerText.isEmpty {
                            loggedConfirmationBanner
                        }
                        inputsCard
                        recommendedDoseHeroCard
                        if calculation.fpuCount >= 1.0 {
                            warsawFpuCard
                        }
                        iobDecayChartCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Smart Bolus & IOB")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                syncDraftFromCarbPrep()
                if bgInputMmol.isEmpty, let latest = store.latestReading {
                    bgInputMmol = store.formatGlucose(latest.mgdL)
                }
            }
            .onChange(of: store.draftBolusCarbs) { _ in
                syncDraftFromCarbPrep()
            }
        }
    }

    private func syncDraftFromCarbPrep() {
        if !store.draftBolusCarbs.isEmpty {
            carbsInput = store.draftBolusCarbs
            fatInput = store.draftBolusFat
            proteinInput = store.draftBolusProtein
            mealNote = store.draftMealNote
            store.draftBolusCarbs = ""
        }
    }

    private var activeProfileBanner: some View {
        let block = calculation.activeBlock
        return HStack(spacing: 10) {
            Image(systemName: "clock.badge.checkmark.fill")
                .foregroundStyle(GlucoTheme.tandemCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.label.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(GlucoTheme.tandemCyan)
                Text("ICR 1:\(String(format: "%.0fg", block.icrGramsPerUnit)) · ISF 1:\(String(format: "%.1f", block.isfMmolPerUnit)) mmol/L · Target \(String(format: "%.1f", block.targetMmol))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GlucoTheme.textPrimary)
            }
            Spacer()
            Button {
                store.selectedTab = 5
            } label: {
                Text("Edit")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(GlucoTheme.cardElevated, in: Capsule())
                    .foregroundStyle(GlucoTheme.textSecondary)
            }
        }
        .padding(14)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var loggedConfirmationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(GlucoTheme.inRangeGreen)
            Text(loggedBannerText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(GlucoTheme.textPrimary)
            Spacer()
        }
        .padding(12)
        .background(GlucoTheme.inRangeGreen.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
    }

    private var inputsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Meal & Glucose Inputs")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(GlucoTheme.textPrimary)
                Spacer()
                Button {
                    store.selectedTab = 2
                } label: {
                    Label("Pick UK Food / Scan", systemImage: "barcode.viewfinder")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GlucoTheme.inRangeGreen)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Carbohydrates (g)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    HStack {
                        TextField("0", text: $carbsInput)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(GlucoTheme.inRangeGreen)
                        Text("g")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(GlucoTheme.textSecondary)
                    }
                    .padding(12)
                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Current BG (\(store.unit.rawValue))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GlucoTheme.textSecondary)
                        Spacer()
                        Button("Use G7") {
                            if let latest = store.latestReading {
                                bgInputMmol = store.formatGlucose(latest.mgdL)
                            }
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GlucoTheme.tandemCyan)
                    }
                    HStack {
                        TextField("6.0", text: $bgInputMmol)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(GlucoTheme.tandemCyan)
                        Text(store.unit.rawValue)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GlucoTheme.textSecondary)
                    }
                    .padding(12)
                    .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            // Quick carb steppers
            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60, 80, 100], id: \.self) { preset in
                    Button("\(preset)g") {
                        carbsInput = "\(preset)"
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(carbsInput == "\(preset)" ? GlucoTheme.inRangeGreen.opacity(0.25) : GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(carbsInput == "\(preset)" ? GlucoTheme.inRangeGreen : GlucoTheme.textSecondary)
                }
            }

            // Optional Fat & Protein for Warsaw FPU Dual-Wave
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fat (g) — Optional FPU")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    TextField("0g", text: $fatInput)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                        .padding(10)
                        .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Protein (g) — Optional FPU")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    TextField("0g", text: $proteinInput)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                        .padding(10)
                        .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Exercise / Activity Adjustment")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GlucoTheme.textSecondary)
                Picker("Exercise", selection: $exerciseChoice) {
                    ForEach(ExerciseAdjustment.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .tint(GlucoTheme.tandemCyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 10))
            }

            Toggle(isOn: $reverseCorrection) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reverse Correction When Below Target")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Text("Reduces meal bolus if current BG is below target or IOB is high")
                        .font(.system(size: 11))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
            }
            .tint(GlucoTheme.inRangeGreen)
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }

    private var recommendedDoseHeroCard: some View {
        let res = calculation
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOMMENDED RAPID BOLUS")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(GlucoTheme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.2f", res.immediateUnits))
                            .font(.system(size: 46, weight: .black, design: .rounded))
                            .foregroundStyle(GlucoTheme.tandemCyan)
                        Text("U Upfront")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(GlucoTheme.textPrimary)
                    }
                    if res.fpuExtendedUnits > 0 {
                        Text("+ \(String(format: "%.2f U", res.fpuExtendedUnits)) extended over \(res.fpuExtendedDurationHours)h (Total \(String(format: "%.2f U", res.totalRecommendedUnits)))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(GlucoTheme.controlIQPurple)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Active IOB")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    Text(String(format: "-%.2f U", res.iobSubtracted))
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundStyle(GlucoTheme.highAmber)
                }
            }

            Divider().overlay(GlucoTheme.border)

            VStack(spacing: 7) {
                mathRow(label: "Meal Insulin (\(carbsInput.isEmpty ? "0" : carbsInput)g ÷ \(Int(res.activeBlock.icrGramsPerUnit))g/U)", value: String(format: "%+.2f U", res.mealInsulin), color: GlucoTheme.inRangeGreen)
                mathRow(label: "BG Correction (\(String(format: "%.1f", currentBgMmol)) vs \(String(format: "%.1f", res.activeBlock.targetMmol)) mmol/L)", value: String(format: "%+.2f U", res.rawCorrectionInsulin), color: GlucoTheme.textPrimary)
                mathRow(label: "Active IOB Deduction (\(Int(store.diaHours))h decay)", value: String(format: "-%.2f U", res.iobSubtracted), color: GlucoTheme.highAmber)
                if res.exerciseReductionUnits > 0.01 {
                    mathRow(label: "Exercise Reduction (\(exerciseChoice.rawValue))", value: String(format: "-%.2f U", res.exerciseReductionUnits), color: GlucoTheme.controlIQPurple)
                }
            }

            if let warn = res.safetyWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(GlucoTheme.lowRed)
                    Text(warn)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                }
                .padding(10)
                .background(GlucoTheme.lowRed.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            }

            Button {
                let carbs = Int(Double(carbsInput) ?? 0)
                let note = mealNote.isEmpty ? "Smart Bolus (\(carbs)g carbs @ BG \(String(format: "%.1f", currentBgMmol)) mmol/L)" : mealNote
                store.logPumpEvent(
                    type: carbs > 0 ? .mealBolus : .manualCorrection,
                    insulin: res.immediateUnits,
                    carbs: carbs > 0 ? carbs : nil,
                    basal: nil,
                    note: note
                )
                loggedBannerText = "Logged \(String(format: "%.2f U", res.immediateUnits)) & \(carbs)g carbs to Pump Log & Nightscout"
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Log \(String(format: "%.2f U", res.immediateUnits)) Bolus & \(Int(Double(carbsInput) ?? 0))g Carbs")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(GlucoTheme.tandemCyan, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.black)
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.tandemCyan.opacity(0.45), lineWidth: 1.5))
    }

    private func mathRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(GlucoTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private var warsawFpuCard: some View {
        let res = calculation
        let total = max(0.05, res.totalRecommendedUnits)
        let immPct = Int(((res.immediateUnits / total) * 100.0).rounded())
        let extPct = max(0, 100 - immPct)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(GlucoTheme.controlIQPurple)
                Text("WARSAW FAT-PROTEIN (FPU) EXTENDED BOLUS ADVISOR")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(GlucoTheme.controlIQPurple)
            }
            Text("High Fat/Protein detected: **\(String(format: "%.1f FPU", res.fpuCount))** (equivalent to **\(Int(res.fpuEquivalentCarbs))g** delayed carbs). On Tandem t:slim X2, use an **Extended Bolus**:")
                .font(.system(size: 12))
                .foregroundStyle(GlucoTheme.textPrimary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DELIVER NOW (\(immPct)%)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    Text(String(format: "%.2f U", res.immediateUnits))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(GlucoTheme.tandemCyan)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("EXTEND (\(extPct)% OVER \(res.fpuExtendedDurationHours)H)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GlucoTheme.textSecondary)
                    Text(String(format: "%.2f U", res.fpuExtendedUnits))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(GlucoTheme.controlIQPurple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(GlucoTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.controlIQPurple.opacity(0.45), lineWidth: 1))
    }

    private var iobDecayChartCard: some View {
        let points = store.iobDecayForecast(additionalBolus: calculation.immediateUnits)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Insulin Decay Curve (\(Int(store.diaHours))h DIA)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(GlucoTheme.textPrimary)
                    Text("Projected active IOB including \(String(format: "%.2f U", calculation.immediateUnits)) proposed bolus")
                        .font(.system(size: 11))
                        .foregroundStyle(GlucoTheme.textSecondary)
                }
                Spacer()
            }

            Chart(points) { pt in
                AreaMark(
                    x: .value("Time", pt.timestamp),
                    y: .value("IOB", pt.remainingIOB)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [GlucoTheme.tandemCyan.opacity(0.45), GlucoTheme.tandemCyan.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", pt.timestamp),
                    y: .value("IOB", pt.remainingIOB)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(GlucoTheme.tandemCyan)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            .frame(height: 155)
        }
        .padding(16)
        .background(GlucoTheme.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GlucoTheme.border, lineWidth: 1))
    }
}
