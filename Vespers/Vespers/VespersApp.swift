import SwiftUI
import EventKit

@main
struct VespersApp: App {
    @StateObject private var settings = VespersSettings()
    @StateObject private var calendar = VespersCalendarStore()

    var body: some Scene {
        WindowGroup {
            VespersRootView()
                .environmentObject(settings)
                .environmentObject(calendar)
                .preferredColorScheme(.dark)
                .tint(settings.theme.accent)
                .task { await calendar.refreshAuthorizationAndEvents() }
        }
    }
}

// MARK: - Theme and accessibility settings

enum VespersTheme: String, CaseIterable, Identifiable {
    case crimson
    case purple

    var id: String { rawValue }
    var name: String { self == .crimson ? "Crimson & Black" : "Purple & Black" }
    var accent: Color { self == .crimson ? Color(red: 0.96, green: 0.13, blue: 0.27) : Color(red: 0.72, green: 0.48, blue: 1.0) }
    var glow: Color { self == .crimson ? Color(red: 0.43, green: 0.04, blue: 0.11) : Color(red: 0.25, green: 0.10, blue: 0.46) }
    var background: Color { Color(red: 0.025, green: 0.018, blue: 0.045) }
    var panel: Color { self == .crimson ? Color(red: 0.075, green: 0.025, blue: 0.045) : Color(red: 0.075, green: 0.045, blue: 0.12) }
    var border: Color { accent.opacity(0.52) }
    var mutedText: Color { Color(red: 0.80, green: 0.75, blue: 0.88) }
}

@MainActor
final class VespersSettings: ObservableObject {
    @Published var theme: VespersTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "vespers.theme") }
    }
    @Published var textScale: Double {
        didSet { UserDefaults.standard.set(textScale, forKey: "vespers.textScale") }
    }

    init() {
        theme = VespersTheme(rawValue: UserDefaults.standard.string(forKey: "vespers.theme") ?? "crimson") ?? .crimson
        let savedScale = UserDefaults.standard.object(forKey: "vespers.textScale") as? Double ?? 1.18
        textScale = min(max(savedScale, 0.9), 1.6)
    }

    var bodyScale: CGFloat { CGFloat(min(max(textScale, 0.9), 1.6)) }
}

// MARK: - Calendar access

@MainActor
final class VespersCalendarStore: ObservableObject {
    @Published private(set) var events: [EKEvent] = []
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var loadError: String?

    let store = EKEventStore()
    private var calendar: Calendar { Calendar.current }

    func requestAccessAndLoad() async {
        do {
            if #available(iOS 17.0, *) {
                try await store.requestFullAccessToEvents()
            } else {
                try await store.requestAccess(to: .event)
            }
            access = EKEventStore.authorizationStatus(for: .event)
            loadError = nil
            loadEvents(around: Date())
        } catch {
            access = EKEventStore.authorizationStatus(for: .event)
            loadError = "Calendar access wasn’t granted. You can enable it in Settings."
        }
    }

    func refreshAuthorizationAndEvents() async {
        access = EKEventStore.authorizationStatus(for: .event)
        if access == .fullAccess || access == .authorized {
            loadEvents(around: Date())
        } else if access == .notDetermined {
            await requestAccessAndLoad()
        }
    }

    func loadEvents(around date: Date) {
        guard access == .fullAccess || access == .authorized else { events = []; calendars = []; return }
        let monthStart = calendar.startOfMonth(for: date)
        let start = calendar.date(byAdding: .month, value: -2, to: monthStart) ?? monthStart
        let end = calendar.date(byAdding: .month, value: 4, to: monthStart) ?? monthStart
        let selected = store.calendars(for: .event)
        calendars = selected
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func events(on day: Date) -> [EKEvent] {
        events.filter { calendar.isDate($0.startDate, inSameDayAs: day) }.sorted { $0.startDate < $1.startDate }
    }

    func hasEvents(on day: Date) -> Bool { events.contains { calendar.isDate($0.startDate, inSameDayAs: day) } }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? date
    }
}

// MARK: - Root and navigation

private enum VespersTab: String, CaseIterable, Identifiable {
    case month = "Month"
    case agenda = "Agenda"
    var id: String { rawValue }
}

struct VespersRootView: View {
    @EnvironmentObject private var settings: VespersSettings
    @EnvironmentObject private var calendarStore: VespersCalendarStore
    @State private var selectedTab: VespersTab = .month
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var showingSettings = false
    @State private var showingNewEvent = false

    private var cal: Calendar { Calendar.current }
    private var displayedEvents: [EKEvent] { calendarStore.events(on: selectedDate) }

    var body: some View {
        ZStack {
            settings.theme.background
                .ignoresSafeArea()
            VespersPalette.ambient(theme: settings.theme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if selectedTab == .month {
                    monthHeader
                    weekdayHeader
                    monthGrid
                    selectedDayHeading
                    agendaList(events: displayedEvents, emptyText: "Nothing planned for this day")
                } else {
                    agendaHeader
                    agendaList(events: upcomingEvents, emptyText: "No upcoming events")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) { VespersSettingsSheet().environmentObject(settings) }
        .sheet(isPresented: $showingNewEvent) {
            VespersNewEventSheet(date: selectedDate) { Task { await calendarStore.refreshAuthorizationAndEvents() } }
                .environmentObject(settings)
        }
        .task(id: cal.component(.month, from: selectedDate)) { calendarStore.loadEvents(around: selectedDate) }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in calendarStore.loadEvents(around: selectedDate) }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(settings.theme.accent)
                    .frame(width: 38, height: 38)
                    .background(settings.theme.panel, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel("Calendar settings")

            Spacer(minLength: 0)
            Picker("Calendar view", selection: $selectedTab) {
                ForEach(VespersTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 210)
            .accessibilityLabel("Month or agenda view")

            Button { selectedDate = Calendar.current.startOfDay(for: Date()); calendarStore.loadEvents(around: selectedDate) } label: {
                Text("Today").font(VespersPalette.font(13, weight: .semibold)).foregroundStyle(settings.theme.accent)
            }
            .accessibilityLabel("Go to today")

            Button { showingNewEvent = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(settings.theme.accent)
                    .frame(width: 34, height: 34)
                    .background(settings.theme.panel, in: Circle())
            }
            .accessibilityLabel("Create event")
        }
        .padding(.top, 7)
        .padding(.bottom, 10)
    }

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).foregroundStyle(settings.theme.accent).frame(width: 40, height: 40) }
                .accessibilityLabel("Previous month")
            Spacer()
            VStack(spacing: 2) {
                Text(selectedDate.formatted(.dateTime.month(.wide)))
                    .font(VespersPalette.display(29 * settings.bodyScale))
                    .foregroundStyle(VespersPalette.text)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(selectedDate.formatted(.dateTime.year()).uppercased())
                    .font(VespersPalette.font(12 * settings.bodyScale, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(settings.theme.accent)
            }
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold)).foregroundStyle(settings.theme.accent).frame(width: 40, height: 40) }
                .accessibilityLabel("Next month")
        }
        .padding(.bottom, 8)
    }

    private var weekdayHeader: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let rotated = Array(symbols.dropFirst(cal.firstWeekday - 1)) + Array(symbols.prefix(cal.firstWeekday - 1))
        return HStack(spacing: 0) {
            ForEach(Array(rotated.enumerated()), id: \.offset) { item in
                Text(item.element.uppercased())
                    .font(VespersPalette.font(11 * settings.bodyScale, weight: .bold))
                    .foregroundStyle(settings.theme.mutedText)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(item.element)
            }
        }
        .padding(.vertical, 7)
    }

    private var monthGrid: some View {
        let dates = monthDates
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 4) {
            ForEach(dates, id: \.self) { date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 42)
                }
            }
        }
        .padding(.bottom, 9)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar month")
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let isToday = cal.isDateInToday(date)
        let inMonth = cal.component(.month, from: date) == cal.component(.month, from: selectedDate)
        let items = calendarStore.events(on: date)
        return Button {
            selectedDate = cal.startOfDay(for: date)
        } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day()))
                    .font(VespersPalette.font(14 * settings.bodyScale, weight: isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? VespersPalette.text : (inMonth ? VespersPalette.text : settings.theme.mutedText.opacity(0.52)))
                    .frame(width: 31, height: 31)
                    .background {
                        if isSelected {
                            Circle().fill(settings.theme.accent.opacity(0.30)).overlay(Circle().stroke(settings.theme.accent, lineWidth: 1.5)).shadow(color: settings.theme.accent.opacity(0.45), radius: 7)
                        } else if isToday {
                            Circle().stroke(settings.theme.accent.opacity(0.75), lineWidth: 1)
                        }
                    }
                HStack(spacing: 2) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { item in
                        Circle().fill(colorFor(item.element)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 41)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (items.isEmpty ? "" : ", \(items.count) events"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedDayHeading: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(VespersPalette.font(12 * settings.bodyScale, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(settings.theme.accent)
                Text(selectedDate.formatted(.dateTime.day().month(.wide)))
                    .font(VespersPalette.font(17 * settings.bodyScale, weight: .semibold))
                    .foregroundStyle(VespersPalette.text)
            }
            Spacer()
            Text("\(displayedEvents.count) EVENTS")
                .font(VespersPalette.font(10 * settings.bodyScale, weight: .bold))
                .foregroundStyle(settings.theme.mutedText)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 7)
    }

    private var agendaHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("AGENDA")
                .font(VespersPalette.display(27 * settings.bodyScale))
                .foregroundStyle(VespersPalette.text)
            Text("UPCOMING EVENTS · \(Date.now.formatted(.dateTime.month(.wide).year()))")
                .font(VespersPalette.font(12 * settings.bodyScale, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(settings.theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private var upcomingEvents: [EKEvent] {
        calendarStore.events.filter { $0.endDate >= cal.startOfDay(for: Date()) }.sorted { $0.startDate < $1.startDate }
    }

    private var monthDates: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: selectedDate), let days = cal.range(of: .day, in: .month, for: selectedDate) else { return [] }
        let leading = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        for day in days {
            if let date = cal.date(byAdding: .day, value: day - 1, to: interval.start) { result.append(date) }
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private func shiftMonth(_ amount: Int) {
        if let next = cal.date(byAdding: .month, value: amount, to: selectedDate) {
            selectedDate = next
            calendarStore.loadEvents(around: next)
        }
    }

    @ViewBuilder private func agendaList(events: [EKEvent], emptyText: String) -> some View {
        if events.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: calendarStore.access == .fullAccess || calendarStore.access == .authorized ? "moon.stars" : "calendar.badge.exclamationmark")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(settings.theme.accent.opacity(0.85))
                Text(calendarStore.loadError ?? (calendarStore.access == .fullAccess || calendarStore.access == .authorized ? emptyText : "Allow calendar access to see your events"))
                    .font(VespersPalette.font(14 * settings.bodyScale, weight: .medium))
                    .foregroundStyle(settings.theme.mutedText)
                    .multilineTextAlignment(.center)
                if calendarStore.access != .fullAccess && calendarStore.access != .authorized {
                    Button("Allow Calendar Access") { Task { await calendarStore.requestAccessAndLoad() } }
                        .font(VespersPalette.font(14 * settings.bodyScale, weight: .semibold))
                        .foregroundStyle(settings.theme.accent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(Array(events.enumerated()), id: \.offset) { item in
                        eventCard(item.element)
                    }
                }
                .padding(.bottom, 14)
            }
            .scrollIndicators(.visible)
        }
    }

    private func eventCard(_ event: EKEvent) -> some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 3)
                .fill(colorFor(event))
                .frame(width: 4)
                .shadow(color: colorFor(event).opacity(0.35), radius: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text((event.title?.isEmpty == false ? event.title : nil) ?? "Untitled event")
                    .font(VespersPalette.font(16 * settings.bodyScale, weight: .semibold))
                    .foregroundStyle(VespersPalette.text)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    if !event.isAllDay {
                        Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        Text("·")
                    }
                    Text(event.calendar.title)
                }
                .font(VespersPalette.font(12 * settings.bodyScale, weight: .medium))
                .foregroundStyle(settings.theme.mutedText)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(VespersPalette.font(12 * settings.bodyScale))
                        .foregroundStyle(settings.theme.mutedText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if event.isAllDay {
                Text("ALL DAY")
                    .font(VespersPalette.font(10 * settings.bodyScale, weight: .bold))
                    .foregroundStyle(settings.theme.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(settings.theme.panel, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(settings.theme.border.opacity(0.75), lineWidth: 1))
    }

    private func colorFor(_ event: EKEvent) -> Color {
        if let cg = event.calendar.cgColor { return Color(cgColor: cg) }
        return settings.theme.accent
    }
}

// MARK: - Settings

private struct VespersSettingsSheet: View {
    @EnvironmentObject private var settings: VespersSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: Binding(get: { settings.theme }, set: { settings.theme = $0 })) {
                        ForEach(VespersTheme.allCases) { theme in
                            Text(theme.name).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Choose Crimson and black or Purple and black")
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Text size")
                            Spacer()
                            Text(settings.textScale >= 1.38 ? "Extra large" : settings.textScale >= 1.18 ? "Large" : "Standard")
                                .foregroundStyle(settings.theme.accent)
                                .fontWeight(.semibold)
                        }
                        Slider(value: $settings.textScale, in: 0.95...1.55, step: 0.1)
                            .tint(settings.theme.accent)
                            .accessibilityLabel("Calendar text size")
                            .accessibilityValue("\(Int(settings.textScale * 100)) percent")
                        Text("Larger type applies to dates, event titles and agenda details.")
                            .font(VespersPalette.font(13, weight: .medium))
                            .foregroundStyle(settings.theme.mutedText)
                    }
                } header: {
                    Text("Readability")
                }
                Section {
                    Label("Events stay in Apple Calendar. Vespers only reads them and doesn’t upload your calendar.", systemImage: "lock.shield")
                        .font(VespersPalette.font(13, weight: .medium))
                        .foregroundStyle(settings.theme.mutedText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(VespersPalette.background.ignoresSafeArea())
            .tint(settings.theme.accent)
            .navigationTitle("Vespers Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(settings.theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Create an event

private struct VespersNewEventSheet: View {
    let date: Date
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var allDay = false
    @State private var selectedCalendarID: String?
    @State private var errorMessage: String?
    @State private var saving = false
    @EnvironmentObject private var settings: VespersSettings
    @StateObject private var eventAccess = VespersCalendarStore()

    init(date: Date, onSave: @escaping () -> Void) {
        self.date = date
        self.onSave = onSave
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        _startsAt = State(initialValue: start)
        _endsAt = State(initialValue: Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Event title", text: $title)
                        .font(VespersPalette.font(17 * settingsScale, weight: .medium))
                    Toggle("All day", isOn: $allDay).tint(settings.theme.accent)
                    if !allDay {
                        DatePicker("Starts", selection: $startsAt, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Ends", selection: $endsAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                if !eventAccess.calendars.isEmpty {
                    Section("Calendar") {
                        Picker("Save to", selection: Binding(get: { selectedCalendarID ?? eventAccess.calendars.first?.calendarIdentifier ?? "" }, set: { selectedCalendarID = $0 })) {
                            ForEach(eventAccess.calendars, id: \.calendarIdentifier) { c in Text(c.title).tag(c.calendarIdentifier) }
                        }
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .scrollContentBackground(.hidden)
            .background(settings.theme.background.ignoresSafeArea())
            .tint(settings.theme.accent)
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }
                        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { await eventAccess.requestAccessAndLoad() }
        }
        .preferredColorScheme(.dark)
    }

    private var settingsScale: CGFloat { settings.bodyScale }

    private func save() {
        guard !saving else { return }
        saving = true
        let store = eventAccess.store
        let auth = EKEventStore.authorizationStatus(for: .event)
        guard auth == .fullAccess || auth == .authorized else {
            errorMessage = "Allow calendar access in Settings before creating events."
            saving = false
            return
        }
        let event = EKEvent(eventStore: store)
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = allDay ? Calendar.current.startOfDay(for: date) : startsAt
        event.endDate = allDay ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date : max(endsAt, startsAt.addingTimeInterval(900))
        event.isAllDay = allDay
        event.calendar = eventAccess.calendars.first(where: { $0.calendarIdentifier == selectedCalendarID }) ?? store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent)
            onSave()
            dismiss()
        } catch {
            errorMessage = "Could not save event: \(error.localizedDescription)"
            saving = false
        }
    }
}

// MARK: - Theme drawing

private enum VespersPalette {
    static let text = Color(red: 0.97, green: 0.95, blue: 0.98)
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }


    static func ambient(theme: VespersTheme) -> some View {
        RadialGradient(colors: [theme.glow.opacity(0.45), .clear], center: .top, startRadius: 12, endRadius: 430)
            .allowsHitTesting(false)
    }

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
