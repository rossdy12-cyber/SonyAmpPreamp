import SwiftUI
import UserNotifications

// ============================================================
//  PHIAL — gothic medication reminders
//  Morning + evening medication rites, and insulin pings at
//  meal times. Everything lives on the device. No network.
// ============================================================

let crimson = Color(red: 1.0, green: 0.09, blue: 0.27)
let bloodDim = Color(red: 0.48, green: 0.05, blue: 0.13)
let ashText = Color(red: 0.96, green: 0.89, blue: 0.91)
let ashDim = Color(red: 0.69, green: 0.53, blue: 0.56)
let cryptBg = Color(red: 0.02, green: 0.004, blue: 0.012)
let cryptPanel = Color(red: 0.06, green: 0.01, blue: 0.03)

// MARK: - Models

struct Medication: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var dose: String
    var morning: Bool
    var evening: Bool
}

struct DoseEvent: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: String      // "med" or "insulin"
    var label: String     // medication name, or insulin name
    var slot: String      // "morning", "evening", "breakfast", "lunch", "dinner"
    var day: String       // "yyyy-MM-dd"
    var at: Date
}

struct PhialSettings: Codable, Equatable {
    var morningHour: Int = 8
    var morningMinute: Int = 0
    var eveningHour: Int = 20
    var eveningMinute: Int = 0
    var insulinEnabled: Bool = true
    var insulinName: String = "Insulin"
    var breakfastHour: Int = 8
    var breakfastMinute: Int = 0
    var lunchHour: Int = 13
    var lunchMinute: Int = 0
    var dinnerHour: Int = 19
    var dinnerMinute: Int = 0
}

// MARK: - Store

@MainActor
final class PhialStore: ObservableObject {
    @Published var meds: [Medication] = [] {
        didSet { persist() }
    }
    @Published var log: [DoseEvent] = [] {
        didSet { persist() }
    }
    @Published var settings: PhialSettings = PhialSettings() {
        didSet { persist() }
    }
    @Published var notifAuthorized = false

    static let allIdentifiers = [
        "phial.morning", "phial.evening",
        "phial.insulin.breakfast", "phial.insulin.lunch", "phial.insulin.dinner"
    ]

    private let defaults = UserDefaults.standard
    private let medsKey = "phial.meds"
    private let logKey = "phial.log"
    private let settingsKey = "phial.settings"
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: persistence

    func load() {
        if let data = defaults.data(forKey: medsKey),
           let decoded = try? JSONDecoder().decode([Medication].self, from: data) {
            meds = decoded
        }
        if let data = defaults.data(forKey: logKey),
           let decoded = try? JSONDecoder().decode([DoseEvent].self, from: data) {
            log = decoded
        }
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(PhialSettings.self, from: data) {
            settings = decoded
        }
        Task {
            await refreshAuth()
            scheduleAll()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(meds) { defaults.set(data, forKey: medsKey) }
        if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: logKey) }
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: settingsKey) }
    }

    // MARK: time helpers

    var morningTime: String { String(format: "%02d:%02d", settings.morningHour, settings.morningMinute) }
    var eveningTime: String { String(format: "%02d:%02d", settings.eveningHour, settings.eveningMinute) }
    var breakfastTime: String { String(format: "%02d:%02d", settings.breakfastHour, settings.breakfastMinute) }
    var lunchTime: String { String(format: "%02d:%02d", settings.lunchHour, settings.lunchMinute) }
    var dinnerTime: String { String(format: "%02d:%02d", settings.dinnerHour, settings.dinnerMinute) }

    func dateAt(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    var todayKey: String { dayFormatter.string(from: Date()) }

    // MARK: medication management

    func addMed(_ med: Medication) {
        meds.append(med)
        scheduleAll()
    }

    func deleteMeds(at offsets: IndexSet) {
        meds.remove(atOffsets: offsets)
        scheduleAll()
    }

    func toggleMedSlots(_ med: Medication, morning: Bool? = nil, evening: Bool? = nil) {
        guard let idx = meds.firstIndex(where: { $0.id == med.id }) else { return }
        if let morning = morning { meds[idx].morning = morning }
        if let evening = evening { meds[idx].evening = evening }
        scheduleAll()
    }

    // MARK: dose logging

    func hasTaken(kind: String, label: String, slot: String) -> Bool {
        log.contains { $0.day == todayKey && $0.kind == kind && $0.label == label && $0.slot == slot }
    }

    func toggleTaken(kind: String, label: String, slot: String) {
        if hasTaken(kind: kind, label: label, slot: slot) {
            log.removeAll { $0.day == todayKey && $0.kind == kind && $0.label == label && $0.slot == slot }
        } else {
            log.append(DoseEvent(kind: kind, label: label, slot: slot, day: todayKey, at: Date()))
        }
    }

    func slotAllTaken(slot: String, kind: String = "med") -> Bool {
        let relevant = meds.filter { slot == "morning" ? $0.morning : $0.evening }
        if relevant.isEmpty { return false }
        return relevant.allSatisfy { hasTaken(kind: kind, label: $0.name, slot: slot) }
    }

    func insulinTaken(slot: String) -> Bool {
        hasTaken(kind: "insulin", label: settings.insulinName, slot: slot)
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: notifications

    func refreshAuth() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        notifAuthorized = (s.authorizationStatus == .authorized || s.authorizationStatus == .provisional)
    }

    func requestNotifications() async {
        do {
            let ok = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notifAuthorized = ok
            if ok { scheduleAll() }
        } catch {
            notifAuthorized = false
        }
    }

    func scheduleAll() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: PhialStore.allIdentifiers)
        guard notifAuthorized else { return }

        let morningMeds = meds.filter { $0.morning }
        if !morningMeds.isEmpty {
            pushDaily(id: "phial.morning", hour: settings.morningHour, minute: settings.morningMinute,
                      title: "PHIAL — MORNING RITE",
                      body: "The sun is up. Take your morning medication\(morningMeds.count == 1 ? "" : "s").")
        }
        let eveningMeds = meds.filter { $0.evening }
        if !eveningMeds.isEmpty {
            pushDaily(id: "phial.evening", hour: settings.eveningHour, minute: settings.eveningMinute,
                      title: "PHIAL — EVENING RITE",
                      body: "Night falls. Take your evening medication\(eveningMeds.count == 1 ? "" : "s").")
        }
        if settings.insulinEnabled {
            let meals: [(String, String, Int, Int)] = [
                ("phial.insulin.breakfast", "Breakfast is served", settings.breakfastHour, settings.breakfastMinute),
                ("phial.insulin.lunch", "Midday meal is served", settings.lunchHour, settings.lunchMinute),
                ("phial.insulin.dinner", "Evening meal is served", settings.dinnerHour, settings.dinnerMinute)
            ]
            for (id, mealName, hour, minute) in meals {
                pushDaily(id: id, hour: hour, minute: minute,
                          title: "PHIAL — INSULIN",
                          body: "\(mealName). Time to take your \(settings.insulinName).")
            }
        }
    }

    private func pushDaily(id: String, hour: Int, minute: Int, title: String, body: String) {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "PHIAL — THE HERALD SPEAKS"
        content.body = "This is how your reminders will sound. The vial is watching over you."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "phial.test", content: content, trigger: trigger))
    }
}

// MARK: - Root

@main
struct PhialApp: App {
    @StateObject private var store = PhialStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: PhialStore

    var body: some View {
        TabView {
            TodayView(store: store)
                .tabItem { Label("TODAY", systemImage: "pills.fill") }
            VaultView(store: store)
                .tabItem { Label("VAULT", systemImage: "archivebox.fill") }
            RitesView(store: store)
                .tabItem { Label("RITES", systemImage: "bell.fill") }
            LedgerView(store: store)
                .tabItem { Label("LEDGER", systemImage: "book.closed.fill") }
        }
        .accentColor(crimson)
        .onAppear { store.load() }
    }
}

// MARK: - Shared

struct VCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(crimson)
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cryptPanel)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(crimson.opacity(0.35), lineWidth: 1))
    }
}

struct DoseRow: View {
    let title: String
    let subtitle: String
    let taken: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(taken ? crimson : ashDim)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundColor(taken ? ashDim : ashText)
                    .strikethrough(taken, color: crimson)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ashDim)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - TODAY

struct TodayView: View {
    @ObservedObject var store: PhialStore

    var body: some View {
        NavigationView {
            ZStack {
                cryptBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        let morningMeds = store.meds.filter { $0.morning }
                        let eveningMeds = store.meds.filter { $0.evening }

                        VCard(title: "01 // MORNING RITE — \(store.morningTime)") {
                            if morningMeds.isEmpty {
                                Text("No morning medications sworn yet. Add them in the VAULT.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(ashDim)
                            } else {
                                if store.slotAllTaken(slot: "morning") {
                                    Text("THE MORNING RITE IS SEALED")
                                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                        .foregroundColor(crimson)
                                }
                                ForEach(morningMeds) { med in
                                    DoseRow(
                                        title: med.name,
                                        subtitle: med.dose,
                                        taken: store.hasTaken(kind: "med", label: med.name, slot: "morning")
                                    ) {
                                        store.toggleTaken(kind: "med", label: med.name, slot: "morning")
                                    }
                                }
                            }
                        }

                        VCard(title: "02 // EVENING RITE — \(store.eveningTime)") {
                            if eveningMeds.isEmpty {
                                Text("No evening medications sworn yet. Add them in the VAULT.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(ashDim)
                            } else {
                                if store.slotAllTaken(slot: "evening") {
                                    Text("THE EVENING RITE IS SEALED")
                                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                        .foregroundColor(crimson)
                                }
                                ForEach(eveningMeds) { med in
                                    DoseRow(
                                        title: med.name,
                                        subtitle: med.dose,
                                        taken: store.hasTaken(kind: "med", label: med.name, slot: "evening")
                                    ) {
                                        store.toggleTaken(kind: "med", label: med.name, slot: "evening")
                                    }
                                }
                            }
                        }

                        VCard(title: "03 // INSULIN — AT MEALS") {
                            if !store.settings.insulinEnabled {
                                Text("Insulin reminders rest in the crypt. Wake them in RITES.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(ashDim)
                            } else {
                                mealRow(slot: "breakfast", title: "Breakfast", time: store.breakfastTime)
                                mealRow(slot: "lunch", title: "Midday meal", time: store.lunchTime)
                                mealRow(slot: "dinner", title: "Evening meal", time: store.dinnerTime)
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("PHIAL")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
        }
    }

    private func mealRow(slot: String, title: String, time: String) -> some View {
        let taken = store.insulinTaken(slot: slot)
        return DoseRow(
            title: "\(store.settings.insulinName) — \(title)",
            subtitle: time,
            taken: taken
        ) {
            store.toggleTaken(kind: "insulin", label: store.settings.insulinName, slot: slot)
        }
    }
}

// MARK: - VAULT (medication list)

struct VaultView: View {
    @ObservedObject var store: PhialStore
    @State private var showingAdd = false

    var body: some View {
        NavigationView {
            ZStack {
                cryptBg.ignoresSafeArea()
                if store.meds.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 38))
                            .foregroundColor(crimson)
                        Text("The vault lies empty.\nSwear your first medication.")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(ashDim)
                            .multilineTextAlignment(.center)
                        Button {
                            showingAdd = true
                        } label: {
                            Text("ADD A MEDICATION")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(crimson)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                } else {
                    List {
                        ForEach(store.meds) { med in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(med.name)
                                        .font(.system(size: 16, weight: .semibold, design: .serif))
                                        .foregroundColor(ashText)
                                    Spacer()
                                    if med.morning {
                                        Text("MORN")
                                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                            .foregroundColor(crimson)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(crimson.opacity(0.5), lineWidth: 1))
                                    }
                                    if med.evening {
                                        Text("EVE")
                                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                            .foregroundColor(crimson)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(crimson.opacity(0.5), lineWidth: 1))
                                    }
                                }
                                Text(med.dose.isEmpty ? "—" : med.dose)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(ashDim)
                            }
                            .listRowBackground(cryptPanel)
                            .listRowSeparatorTint(crimson.opacity(0.25))
                        }
                        .onDelete { store.deleteMeds(at: $0) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("THE VAULT")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(crimson)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddMedicationView(store: store)
            }
        }
    }
}

struct AddMedicationView: View {
    @ObservedObject var store: PhialStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dose = ""
    @State private var morning = true
    @State private var evening = false

    var body: some View {
        NavigationView {
            ZStack {
                cryptBg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    VCard(title: "01 // THE VESSEL") {
                        TextField("Medication name", text: $name)
                            .font(.system(size: 16, design: .serif))
                            .foregroundColor(ashText)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(8)
                        TextField("Dose (e.g. 1 tablet, 5 ml)", text: $dose)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(ashDim)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color.black.opacity(0.35))
                            .cornerRadius(8)
                    }
                    VCard(title: "02 // WHEN THE BELL TOLLS") {
                        Toggle(isOn: $morning) {
                            Text("Morning rite (\(store.morningTime))")
                                .font(.system(size: 14, design: .serif))
                                .foregroundColor(ashText)
                        }
                        .tint(crimson)
                        Toggle(isOn: $evening) {
                            Text("Evening rite (\(store.eveningTime))")
                                .font(.system(size: 14, design: .serif))
                                .foregroundColor(ashText)
                        }
                        .tint(crimson)
                        if !morning && !evening {
                            Text("A medication must be sworn to at least one rite.")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(bloodDim)
                        }
                    }
                    Spacer()
                }
                .padding(14)
            }
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("SWEAR A MEDICATION")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(ashDim)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Swear it") {
                        let med = Medication(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            dose: dose.trimmingCharacters(in: .whitespacesAndNewlines),
                            morning: morning,
                            evening: evening
                        )
                        store.addMed(med)
                        dismiss()
                    }
                    .foregroundColor(name.isEmpty || (!morning && !evening) ? ashDim : crimson)
                    .disabled(name.isEmpty || (!morning && !evening))
                }
            }
        }
    }
}

// MARK: - RITES (times, insulin, notifications)

struct RitesView: View {
    @ObservedObject var store: PhialStore

    var body: some View {
        NavigationView {
            ZStack {
                cryptBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        VCard(title: "01 // MEDICATION BELL TOLLS") {
                            timePicker(
                                label: "Morning rite",
                                hour: Binding(get: { store.settings.morningHour }, set: { store.settings.morningHour = $0; store.scheduleAll() }),
                                minute: Binding(get: { store.settings.morningMinute }, set: { store.settings.morningMinute = $0; store.scheduleAll() })
                            )
                            timePicker(
                                label: "Evening rite",
                                hour: Binding(get: { store.settings.eveningHour }, set: { store.settings.eveningHour = $0; store.scheduleAll() }),
                                minute: Binding(get: { store.settings.eveningMinute }, set: { store.settings.eveningMinute = $0; store.scheduleAll() })
                            )
                        }

                        VCard(title: "02 // INSULIN AT MEALS") {
                            Toggle(isOn: Binding(
                                get: { store.settings.insulinEnabled },
                                set: { store.settings.insulinEnabled = $0; store.scheduleAll() }
                            )) {
                                Text("Summon insulin reminders")
                                    .font(.system(size: 14, design: .serif))
                                    .foregroundColor(ashText)
                            }
                            .tint(crimson)
                            if store.settings.insulinEnabled {
                                TextField("Insulin name", text: Binding(
                                    get: { store.settings.insulinName },
                                    set: { store.settings.insulinName = $0; store.scheduleAll() }
                                ))
                                .font(.system(size: 14, design: .serif))
                                .foregroundColor(ashText)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.black.opacity(0.35))
                                .cornerRadius(8)
                                timePicker(
                                    label: "Breakfast",
                                    hour: Binding(get: { store.settings.breakfastHour }, set: { store.settings.breakfastHour = $0; store.scheduleAll() }),
                                    minute: Binding(get: { store.settings.breakfastMinute }, set: { store.settings.breakfastMinute = $0; store.scheduleAll() })
                                )
                                timePicker(
                                    label: "Midday meal",
                                    hour: Binding(get: { store.settings.lunchHour }, set: { store.settings.lunchHour = $0; store.scheduleAll() }),
                                    minute: Binding(get: { store.settings.lunchMinute }, set: { store.settings.lunchMinute = $0; store.scheduleAll() })
                                )
                                timePicker(
                                    label: "Evening meal",
                                    hour: Binding(get: { store.settings.dinnerHour }, set: { store.settings.dinnerHour = $0; store.scheduleAll() }),
                                    minute: Binding(get: { store.settings.dinnerMinute }, set: { store.settings.dinnerMinute = $0; store.scheduleAll() })
                                )
                            }
                        }

                        VCard(title: "03 // THE HERALD (NOTIFICATIONS)") {
                            if store.notifAuthorized {
                                HStack(spacing: 8) {
                                    Image(systemName: "bell.badge.fill")
                                        .foregroundColor(crimson)
                                    Text("The herald is sworn. Reminders will toll daily.")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(ashDim)
                                }
                                Button {
                                    store.sendTestNotification()
                                } label: {
                                    Text("HEAR THE HERALD (TEST)")
                                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(crimson)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            } else {
                                Text("The herald has not been summoned. Without it, no reminders can toll.")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(ashDim)
                                Button {
                                    Task { await store.requestNotifications() }
                                } label: {
                                    Text("SUMMON THE HERALD")
                                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(crimson)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                }
                            }
                        }

                        VCard(title: "04 // NOTES") {
                            Text("Phial keeps everything on this device — no account, no network, no analytics. Reminders repeat daily at the times chosen above, even if you never open the app.")
                                .font(.system(size: 12, design: .serif))
                                .foregroundColor(ashDim)
                        }
                    }
                    .padding(14)
                }
            }
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("THE RITES")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
            .onAppear { Task { await store.refreshAuth() } }
        }
    }

    private func timePicker(label: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        let binding = Binding<Date>(
            get: { store.dateAt(hour: hour.wrappedValue, minute: minute.wrappedValue) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                hour.wrappedValue = c.hour ?? hour.wrappedValue
                minute.wrappedValue = c.minute ?? minute.wrappedValue
            }
        )
        return HStack {
            Text(label)
                .font(.system(size: 14, design: .serif))
                .foregroundColor(ashText)
            Spacer()
            DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - LEDGER (history)

struct LedgerView: View {
    @ObservedObject var store: PhialStore

    private var grouped: [(String, [DoseEvent])] {
        let dict = Dictionary(grouping: store.log) { $0.day }
        return dict.sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationView {
            ZStack {
                cryptBg.ignoresSafeArea()
                if store.log.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 38))
                            .foregroundColor(crimson)
                        Text("The ledger is blank.\nEvery dose you take is inked here.")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(ashDim)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List {
                        ForEach(grouped, id: \.0) { day, events in
                            Section(day) {
                                ForEach(events.sorted { $0.at < $1.at }) { event in
                                    HStack {
                                        Image(systemName: event.kind == "insulin" ? "syringe.fill" : "pills.fill")
                                            .foregroundColor(crimson)
                                            .font(.system(size: 13))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(event.label) — \(slotName(event.slot))")
                                                .font(.system(size: 13, design: .serif))
                                                .foregroundColor(ashText)
                                            Text(event.at, style: .time)
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(ashDim)
                                        }
                                        Spacer()
                                    }
                                    .listRowBackground(cryptPanel)
                                    .listRowSeparatorTint(crimson.opacity(0.25))
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("")
            .overlay(alignment: .top) {
                Text("THE LEDGER")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(crimson)
                    .padding(.top, 2)
            }
            .toolbar {
                if !store.log.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            store.clearLog()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(crimson)
                        }
                    }
                }
            }
        }
    }

    private func slotName(_ slot: String) -> String {
        switch slot {
        case "morning": return "Morning rite"
        case "evening": return "Evening rite"
        case "breakfast": return "Breakfast"
        case "lunch": return "Midday meal"
        case "dinner": return "Evening meal"
        default: return slot
        }
    }
}
