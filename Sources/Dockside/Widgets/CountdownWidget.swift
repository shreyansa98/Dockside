import SwiftUI

/// Counts down to a date the user picks. Each instance stores its own title and date in `WidgetItem.options`.
struct CountdownWidget: View {
    let item: WidgetItem
    @Environment(\.palette) private var p
    @Environment(\.dockAccent) private var accent

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func isoString(_ d: Date) -> String { iso.string(from: d) }

    static var nextNewYear: Date {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date()) + 1
        return cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
    }

    private var title: String { item.options["title"].flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Countdown") }
    private var target: Date { item.options["date"].flatMap(Self.iso.date(from:)) ?? Self.nextNewYear }

    /// The big number and its unit: days, then hours, then minutes on the final stretch.
    static func remaining(until target: Date, now: Date) -> (value: String, unit: String, done: Bool) {
        let seconds = target.timeIntervalSince(now)
        if seconds <= 0 { return ("🎉", String(localized: "today"), true) }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: target)).day ?? 0
        if days >= 1 { return ("\(days)", days == 1 ? String(localized: "day") : String(localized: "days"), false) }
        let hours = Int(seconds / 3600)
        if hours >= 1 { return ("\(hours)", hours == 1 ? String(localized: "hour") : String(localized: "hours"), false) }
        let minutes = max(1, Int(seconds / 60))
        return ("\(minutes)", String(localized: "min"), false)
    }

    var body: some View {
        PopoverTile(width: 184, padding: 12, popoverWidth: 280) {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let r = Self.remaining(until: target, now: ctx.date)
                HStack(spacing: 12) {
                    VStack(spacing: -2) {
                        Text(r.value)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(r.done ? accent : p.primary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(r.unit)
                            .font(.system(size: 9, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(p.secondary)
                    }
                    .frame(width: 54)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.primary)
                            .lineLimit(1)
                        Text(target.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(p.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        } popover: {
            CountdownEditor(item: item, title: title, date: target)
        }
    }
}

private struct CountdownEditor: View {
    let item: WidgetItem
    @State var title: String
    @State var date: Date

    private var presets: [(String, Date)] {
        let cal = Calendar.current
        let now = Date()
        let weekend = cal.nextDate(after: now, matching: DateComponents(hour: 18, weekday: 6), matchingPolicy: .nextTime) ?? now
        let nextMonth = cal.date(byAdding: .month, value: 1, to: cal.startOfDay(for: now)) ?? now
        return [(String(localized: "New Year"), CountdownWidget.nextNewYear),
                (String(localized: "Friday 6 PM"), weekend),
                (String(localized: "In a month"), nextMonth)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(title: "Countdown", symbol: "hourglass", tint: .pink)
            TextField("What are you counting down to?", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
            HStack(spacing: 6) {
                ForEach(presets, id: \.0) { preset in
                    Button(preset.0) {
                        title = title.isEmpty || presets.contains(where: { $0.0 == title }) ? preset.0 : title
                        date = preset.1
                        save()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .onChange(of: date) { save() }
        .onDisappear(perform: save)
    }

    private func save() {
        Store.shared.setOption(item.id, "title", title.trimmingCharacters(in: .whitespaces))
        Store.shared.setOption(item.id, "date", CountdownWidget.isoString(date))
    }
}
