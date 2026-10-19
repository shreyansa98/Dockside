import SwiftUI
import EventKit

// MARK: - Calendar

struct CalendarBadge: View {
    var date = Date()
    var size: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: size * 0.3)
                .background(Color(red: 1, green: 0.27, blue: 0.23))
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                .foregroundStyle(.black.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct CalendarWidget: View {
    @ObservedObject private var cal = CalendarService.shared
    @Environment(\.palette) private var p

    var body: some View {
        PopoverTile(width: 236, padding: 10, popoverWidth: 320) {
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    CalendarBadge(date: ctx.date, size: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if !cal.eventsAccess {
                        Text("Calendar").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                        Text("Connect calendar").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary)
                    } else if let e = cal.nextEvent {
                        Text(when(e)).font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary).lineLimit(1)
                        Text(e.title ?? "Event").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary).lineLimit(1)
                    } else {
                        Text("Today").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                        Text("No more events").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary)
                    }
                }
                Spacer(minLength: 0)
            }
        } popover: {
            CalendarPopover()
        }
    }

    private func when(_ e: EKEvent) -> String {
        let day = Calendar.current.isDateInToday(e.startDate) ? "Today"
            : Calendar.current.isDateInTomorrow(e.startDate) ? "Tomorrow"
            : e.startDate.formatted(.dateTime.weekday(.abbreviated))
        if e.isAllDay { return "\(day) · All day" }
        if e.startDate <= Date() { return "Now · until \(e.endDate.formatted(date: .omitted, time: .shortened))" }
        return "\(day) · \(e.startDate.formatted(date: .omitted, time: .shortened))"
    }
}

private struct CalendarPopover: View {
    @ObservedObject private var cal = CalendarService.shared

    private var grouped: [(Date, [EKEvent])] {
        let g = Dictionary(grouping: cal.events.filter { $0.endDate > Date() }) { Calendar.current.startOfDay(for: $0.startDate) }
        return g.keys.sorted().map { ($0, g[$0]!) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(title: "Upcoming", symbol: "calendar", tint: .red) {
                Button("Open Calendar") { Launcher.open(path: "/System/Applications/Calendar.app") }
                    .buttonStyle(.borderless).font(.system(size: 12))
            }
            if !cal.eventsAccess {
                PermissionPrompt(text: "Allow Dockside to read your calendars to see upcoming events.") { cal.requestEvents() }
            } else if grouped.isEmpty {
                Text("Nothing scheduled this week 🎉").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(grouped, id: \.0) { day, events in
                            Text(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month().day()))
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            ForEach(events, id: \.eventIdentifier) { e in
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: e.calendar.cgColor)).frame(width: 4)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.title ?? "Event").font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(e.isAllDay ? "All day" : "\(e.startDate.formatted(date: .omitted, time: .shortened)) – \(e.endDate.formatted(date: .omitted, time: .shortened))")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let u = e.url ?? meetingURL(e) {
                                        Button("Join") { NSWorkspace.shared.open(u) }.buttonStyle(PillButtonStyle(tint: .blue))
                                    }
                                }
                                .frame(height: 34)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
    }

    private func meetingURL(_ e: EKEvent) -> URL? {
        let text = [e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        guard let r = text.range(of: #"https://[^\s]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|webex\.com)[^\s>]*"#, options: .regularExpression) else { return nil }
        return URL(string: String(text[r]))
    }
}

struct PermissionPrompt: View {
    var text: String
    var action: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Grant Access", action: action).buttonStyle(PillButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Reminders

struct RemindersWidget: View {
    @ObservedObject private var cal = CalendarService.shared
    @Environment(\.palette) private var p

    var body: some View {
        PopoverTile(width: 200, padding: 10, popoverWidth: 320) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: "list.bullet", colors: [Color(red: 0.25, green: 0.6, blue: 1), Color(red: 0.1, green: 0.4, blue: 0.95)], size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cal.remindersAccess ? "\(cal.reminders.count) Reminders" : "Reminders")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                    Text(cal.remindersAccess ? (cal.reminders.first?.title ?? "All done") : "Connect Reminders")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        } popover: {
            RemindersPopover()
        }
    }
}

private struct RemindersPopover: View {
    @ObservedObject private var cal = CalendarService.shared
    @State private var newTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(title: "Reminders", symbol: "list.bullet", tint: .blue)
            if !cal.remindersAccess {
                PermissionPrompt(text: "Allow Dockside to access Reminders to show and complete them here.") { cal.requestReminders() }
            } else {
                TextField("New reminder", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard !newTitle.isEmpty else { return }
                        cal.addReminder(newTitle)
                        newTitle = ""
                    }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(cal.reminders, id: \.calendarItemIdentifier) { r in
                            HStack(spacing: 10) {
                                Button { withAnimation { cal.complete(r) } } label: {
                                    Image(systemName: "circle").font(.system(size: 16)).foregroundStyle(Color(cgColor: r.calendar.cgColor))
                                }.buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title ?? "").font(.system(size: 12))
                                    if let d = r.dueDateComponents?.date {
                                        Text(d.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10))
                                            .foregroundStyle(d < Date() ? .red : .secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }
}

// MARK: - Todos

struct TodosWidget: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p

    var body: some View {
        let todos = store.data.todos
        let done = todos.filter(\.done).count
        let pending = todos.filter { !$0.done }
        PopoverTile(width: 210, padding: 12, popoverWidth: 320) {
            HStack(spacing: 12) {
                ZStack {
                    RingGauge(value: todos.isEmpty ? 0 : Double(done) / Double(todos.count),
                              color: Color(red: 0.2, green: 0.82, blue: 0.4), lineWidth: 4, openBottom: false)
                        .frame(width: 38, height: 38)
                    Text("\(pending.count)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(p.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.isEmpty ? "Todos" : "\(pending.count) left")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                    Text(pending.first?.title ?? "All done ✓")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        } popover: {
            TodosPopover()
        }
    }
}

private struct TodosPopover: View {
    @ObservedObject private var store = Store.shared
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(title: "Todos", symbol: "checkmark", tint: .green) {
                if store.data.todos.contains(where: \.done) {
                    Button("Clear Done") { withAnimation { store.data.todos.removeAll(where: \.done) } }
                        .buttonStyle(.borderless).font(.system(size: 12))
                }
            }
            HStack {
                Image(systemName: "plus.circle.fill").foregroundStyle(.green).font(.system(size: 16))
                TextField("Add a task and press Return", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        let t = text.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        withAnimation(.spring) { store.data.todos.insert(TodoItem(title: t), at: 0) }
                        text = ""
                    }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach($store.data.todos) { $todo in
                        TodoRow(todo: $todo) {
                            withAnimation { store.data.todos.removeAll { $0.id == todo.id } }
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            if store.data.todos.isEmpty {
                Text("Nothing to do. Enjoy it.").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

private struct TodoRow: View {
    @Binding var todo: TodoItem
    var onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Button { withAnimation(.spring(duration: 0.3)) { todo.done.toggle() } } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(todo.done ? Color.green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }.buttonStyle(.plain)
            Text(todo.title)
                .font(.system(size: 13))
                .strikethrough(todo.done)
                .foregroundStyle(todo.done ? .secondary : .primary)
            Spacer()
            if hover {
                Button(action: onDelete) { Image(systemName: "trash").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

// MARK: - Pomodoro

struct PomodoroWidget: View {
    @ObservedObject private var timer = PomodoroService.shared
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p
    @Environment(\.dockAccent) private var accent
    @State private var showSettings = false

    var body: some View {
        let color = timer.mode == .focus ? accent : Color(red: 0.2, green: 0.8, blue: 0.5)
        Tile(width: 188, padding: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: -1) {
                    Text(timer.mode == .focus ? "FOCUS" : "BREAK")
                        .font(.system(size: 8.5, weight: .bold)).tracking(0.8).foregroundStyle(color)
                    Text(Formatters.duration(timer.remaining))
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(p.primary)
                        .contentTransition(.numericText(countsDown: true))
                        .fixedSize()
                }
                .frame(width: 80, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { NSApp.activate(ignoringOtherApps: true); showSettings = true }
                Spacer(minLength: 0)
                CircleIconButton(symbol: "xmark", size: 32, help: "Reset") { timer.reset() }
                CircleIconButton(symbol: timer.running ? "pause.fill" : "play.fill", size: 40, fill: color,
                                 foreground: .white, help: timer.running ? "Pause" : "Start") { timer.toggle() }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DockMetrics.radius, style: .continuous)
                .inset(by: 1)
                .trim(from: 0, to: timer.progress)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .animation(.linear(duration: 0.25), value: timer.progress)
        )
        .popover(isPresented: $showSettings, arrowEdge: store.settings.position == .top ? .bottom : .top) {
            VStack(alignment: .leading, spacing: 12) {
                PopoverHeader(title: "Pomodoro", symbol: "timer", tint: .orange)
                Stepper("Focus: \(store.settings.focusMinutes) min", value: $store.settings.focusMinutes, in: 1...120)
                Stepper("Break: \(store.settings.breakMinutes) min", value: $store.settings.breakMinutes, in: 1...60)
                HStack {
                    Label("\(timer.sessionsToday) sessions today", systemImage: "flame.fill").foregroundStyle(.orange)
                    Spacer()
                    Button("Skip") { timer.skip() }
                }
                .font(.system(size: 12))
            }
            .frame(width: 240)
            .padding(16)
            .onChange(of: store.settings.focusMinutes) { if !timer.running { timer.remaining = timer.total } }
            .onChange(of: store.settings.breakMinutes) { if !timer.running { timer.remaining = timer.total } }
        }
    }
}

// MARK: - Water

struct WaterWidget: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p

    var body: some View {
        let count = store.waterToday
        let goal = max(1, store.settings.waterGoal)
        let fill = min(1, Double(count) / Double(goal))
        Tile(width: 164, padding: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drink Water").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.primary)
                    Text(count >= goal ? "Goal reached 🎉" : "\(count) of \(goal) glasses")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                    HStack(spacing: 2) {
                        ForEach(0..<min(goal, 12), id: \.self) { i in
                            Capsule().fill(i < count ? Color(red: 0.3, green: 0.65, blue: 1) : p.track).frame(width: 6, height: 4)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
                CircleIconButton(symbol: "plus", size: 34, fill: Color(red: 0.2, green: 0.55, blue: 1), foreground: .white, help: "Add a glass") {
                    withAnimation(.spring) { store.addWater(1) }
                    NSSound(named: "Bottle")?.play()
                }
            }
        }
        .background(alignment: .bottom) {
            WaveShape(level: fill, phase: 0)
                .fill(Color(red: 0.25, green: 0.6, blue: 1).opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: DockMetrics.radius, style: .continuous))
                .animation(.spring(duration: 0.8), value: fill)
        }
        .contextMenu {
            Button("Remove a Glass") { store.addWater(-1) }
            Button("Reset Today") { store.addWater(-store.waterToday) }
        }
    }
}

struct WaveShape: Shape {
    var level: Double
    var phase: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.maxY - rect.height * level
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: y))
        let steps = 40
        for i in 0...steps {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(steps)
            let wave = level > 0 && level < 1 ? sin(Double(i) / Double(steps) * .pi * 3 + phase) * 2.5 : 0
            p.addLine(to: CGPoint(x: x, y: y + wave))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Notes

struct NotesWidget: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p

    var body: some View {
        let first = store.data.notes.split(separator: "\n").first.map(String.init) ?? ""
        PopoverTile(width: 196, padding: 10, popoverWidth: 340) {
            HStack(spacing: 10) {
                NotesIcon(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Note").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                    Text(first.isEmpty ? "Write something…" : first)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        } popover: {
            NotesPopover()
        }
    }
}

struct NotesIcon: View {
    var size: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(red: 1, green: 0.8, blue: 0.1)).frame(height: size * 0.28)
            VStack(spacing: size * 0.11) {
                ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1) }
            }
            .padding(.horizontal, size * 0.14)
            .frame(maxHeight: .infinity)
            .background(Color(white: 0.98))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

private struct NotesPopover: View {
    @ObservedObject private var store = Store.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(title: "Quick Note", symbol: "note.text", tint: .yellow) {
                Button { Launcher.copy(store.data.notes) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy note")
                Button { store.data.notes = "" } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Clear note")
            }
            TextEditor(text: $store.data.notes)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                .frame(height: 260)
                .focused($focused)
            Text("\(store.data.notes.split { $0.isWhitespace }.count) words · saved automatically")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
