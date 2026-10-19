import SwiftUI

enum TimeFormat {
    static func time(_ d: Date, tz: TimeZone = .current, seconds: Bool = false) -> String {
        let f = DateFormatter()
        f.timeZone = tz
        let h24 = Store.shared.settings.use24h
        f.dateFormat = (h24 ? "HH:mm" : "h:mm") + (seconds ? ":ss" : "")
        return f.string(from: d)
    }
}

// MARK: - Clock

struct ClockWidget: View {
    @Environment(\.palette) private var p
    @ObservedObject private var store = Store.shared

    var body: some View {
        PopoverTile(width: store.settings.showSeconds ? 144 : 124, popoverWidth: 264) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(spacing: 1) {
                    Text(TimeFormat.time(ctx.date, seconds: store.settings.showSeconds))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(p.primary)
                        .contentTransition(.numericText())
                    Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.secondary)
                }
            }
        } popover: {
            MonthCalendarView()
        }
    }
}

struct MonthCalendarView: View {
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @Environment(\.dockAccent) private var accent

    private var cal: Calendar { Calendar.current }

    private var days: [Date?] {
        let range = cal.range(of: .day, in: .month, for: month)!
        let weekday = cal.component(.weekday, from: month)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: lead)
        for d in range { out.append(cal.date(byAdding: .day, value: d - 1, to: month)) }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                Button("Today") {
                    withAnimation { month = cal.date(from: cal.dateComponents([.year, .month], from: Date()))! }
                }.buttonStyle(.borderless).font(.system(size: 12, weight: .medium))
                Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
            }
            let symbols = rotatedWeekdays()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(symbols.indices, id: \.self) { i in
                    Text(symbols[i]).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                ForEach(days.indices, id: \.self) { i in
                    if let d = days[i] {
                        let today = cal.isDateInToday(d)
                        Text("\(cal.component(.day, from: d))")
                            .font(.system(size: 12, weight: today ? .bold : .regular))
                            .foregroundStyle(today ? .white : (cal.isDateInWeekend(d) ? .secondary : .primary))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(today ? accent : .clear))
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
        }
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { month = cal.date(byAdding: .month, value: n, to: month)! }
    }

    private func rotatedWeekdays() -> [String] {
        let s = cal.veryShortWeekdaySymbols
        let i = cal.firstWeekday - 1
        return Array(s[i...] + s[..<i])
    }
}

// MARK: - World clock

struct WorldClockWidget: View {
    let item: WidgetItem
    @Environment(\.palette) private var p

    static let cities: [(String, String)] = [
        ("San Francisco", "America/Los_Angeles"), ("Denver", "America/Denver"), ("Chicago", "America/Chicago"),
        ("New York", "America/New_York"), ("Toronto", "America/Toronto"), ("Mexico City", "America/Mexico_City"),
        ("São Paulo", "America/Sao_Paulo"), ("London", "Europe/London"), ("Paris", "Europe/Paris"),
        ("Berlin", "Europe/Berlin"), ("Madrid", "Europe/Madrid"), ("Istanbul", "Europe/Istanbul"),
        ("Moscow", "Europe/Moscow"), ("Dubai", "Asia/Dubai"), ("Mumbai", "Asia/Kolkata"),
        ("Singapore", "Asia/Singapore"), ("Hong Kong", "Asia/Hong_Kong"), ("Shanghai", "Asia/Shanghai"),
        ("Seoul", "Asia/Seoul"), ("Tokyo", "Asia/Tokyo"), ("Sydney", "Australia/Sydney"),
        ("Auckland", "Pacific/Auckland"), ("Honolulu", "Pacific/Honolulu"), ("Lagos", "Africa/Lagos"),
        ("Cairo", "Africa/Cairo"), ("Johannesburg", "Africa/Johannesburg"),
    ]

    private var tz: TimeZone { TimeZone(identifier: item.options["tz"] ?? "") ?? .current }
    private var city: String { item.options["city"] ?? tz.identifier }

    private var offset: String {
        let diff = (tz.secondsFromGMT() - TimeZone.current.secondsFromGMT()) / 60
        if diff == 0 { return "Same time" }
        let h = Double(diff) / 60
        let s = h == h.rounded() ? String(format: "%+.0fh", h) : String(format: "%+.1fh", h)
        return s
    }

    var body: some View {
        PopoverTile(width: 150, popoverWidth: 240) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(spacing: 1) {
                    Text(TimeFormat.time(ctx.date, tz: tz))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(p.primary)
                    Text("\(city) \(offset)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(p.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        } popover: {
            VStack(alignment: .leading, spacing: 6) {
                PopoverHeader(title: "World Clock", symbol: "globe.americas.fill", tint: .indigo)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Self.cities, id: \.0) { c in
                            let ctz = TimeZone(identifier: c.1)!
                            Button {
                                Store.shared.setOption(item.id, "tz", c.1)
                                Store.shared.setOption(item.id, "city", c.0)
                            } label: {
                                HStack {
                                    Image(systemName: c.1 == tz.identifier ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(c.1 == tz.identifier ? Color.accentColor : .secondary)
                                    Text(c.0).font(.system(size: 12))
                                    Spacer()
                                    Text(TimeFormat.time(Date(), tz: ctz)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                }
                .frame(height: 300)
            }
        }
    }
}

// MARK: - Progress

struct ProgressWidget: View {
    let item: WidgetItem
    @Environment(\.palette) private var p

    private static let periods = ["day", "week", "month", "year"]
    private var period: String { item.options["period"] ?? "day" }

    private func fraction(_ now: Date) -> Double {
        let cal = Calendar.current
        let comp: Calendar.Component = switch period {
        case "week": .weekOfYear
        case "month": .month
        case "year": .year
        default: .day
        }
        guard let interval = cal.dateInterval(of: comp, for: now) else { return 0 }
        return now.timeIntervalSince(interval.start) / interval.duration
    }

    private var color: Color {
        switch period {
        case "week": .cyan
        case "month": .purple
        case "year": .orange
        default: Color(red: 0.2, green: 0.85, blue: 0.4)
        }
    }

    var body: some View {
        Tile(width: DockMetrics.tile, padding: 0) {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let f = fraction(ctx.date)
                ZStack {
                    RingGauge(value: f, color: color, lineWidth: 5, openBottom: false)
                        .frame(width: 48, height: 48)
                    VStack(spacing: -1) {
                        Text("\(Int(f * 100))")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(p.primary)
                        Text(period.prefix(1).uppercased() + period.dropFirst())
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(p.secondary)
                            .textCase(.uppercase)
                    }
                }
            }
        }
        .onTapGesture {
            let i = Self.periods.firstIndex(of: period) ?? 0
            Store.shared.setOption(item.id, "period", Self.periods[(i + 1) % Self.periods.count])
        }
        .help("\(period.capitalized) progress — click to switch")
    }
}
