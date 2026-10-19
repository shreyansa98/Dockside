import SwiftUI
import ServiceManagement
import EventKit
import AVFoundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, widgets, appearance, apps, profiles, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .widgets: "Widgets"
        case .appearance: "Appearance"
        case .apps: "Apps & Folders"
        case .profiles: "Profiles"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .widgets: "square.grid.2x2.fill"
        case .appearance: "paintbrush.fill"
        case .apps: "folder.fill"
        case .profiles: "person.2.fill"
        case .permissions: "hand.raised.fill"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .widgets: .blue
        case .appearance: .pink
        case .apps: .cyan
        case .profiles: .orange
        case .permissions: .indigo
        case .about: .green
        }
    }
}

final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab: SettingsTab? = .general
}

struct SettingsView: View {
    @ObservedObject private var nav = SettingsNav.shared

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $nav.tab) { t in
                Label {
                    Text(t.title)
                } icon: {
                    Image(systemName: t.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.color.gradient))
                }
                .tag(t)
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            Group {
                switch nav.tab ?? .general {
                case .general: GeneralSettings()
                case .widgets: WidgetsSettings()
                case .appearance: AppearanceSettings()
                case .apps: AppsSettings()
                case .profiles: ProfilesSettings()
                case .permissions: PermissionsSettings()
                case .about: AboutSettings()
                }
            }
            .navigationTitle((nav.tab ?? .general).title)
        }
        .frame(minWidth: 780, minHeight: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject private var store = Store.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    AppGlyph(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to Dockside").font(.system(size: 20, weight: .bold))
                        Text("Your smart second Dock. Right‑click any widget to move or remove it, or use the menu bar icon to switch profiles.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            Section("Startup") {
                Toggle("Launch Dockside at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                Toggle("Show Dockside", isOn: $store.settings.visible)
                Toggle(isOn: $store.settings.hotkeyEnabled) {
                    HStack {
                        Text("Toggle with keyboard shortcut")
                        Spacer()
                        Text("⌃⌥D").font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    }
                }
            }
            Section("Clock") {
                Toggle("Use 24‑hour time", isOn: $store.settings.use24h)
                Toggle("Show seconds", isOn: $store.settings.showSeconds)
            }
            Section {
                Picker("Now Playing source", selection: $store.settings.musicSource) {
                    ForEach(MusicSource.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Music")
            } footer: {
                Text("YouTube Music works in Chrome, Brave, Edge and Safari. Turn on “Allow JavaScript from Apple Events” in the browser for full control (Chrome: View ▸ Developer).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Weather") {
                TextField("City", text: $store.settings.weatherCity, prompt: Text("Automatic (based on your network)"))
                Picker("Units", selection: $store.settings.fahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Section("Focus & Health") {
                Stepper("Pomodoro focus: \(store.settings.focusMinutes) min", value: $store.settings.focusMinutes, in: 1...120)
                Stepper("Pomodoro break: \(store.settings.breakMinutes) min", value: $store.settings.breakMinutes, in: 1...60)
                Stepper("Daily water goal: \(store.settings.waterGoal) glasses", value: $store.settings.waterGoal, in: 1...20)
            }
            Section {
                Toggle("Keep clipboard history", isOn: $store.settings.keepClipboardHistory)
                TextField("GitHub username", text: $store.settings.githubUser, prompt: Text("octocat"))
            } header: {
                Text("Privacy & Integrations")
            } footer: {
                Text("Everything stays on your Mac. Clipboard history is kept in memory only and skips password manager copies.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Widgets

private struct WidgetsSettings: View {
    @ObservedObject private var store = Store.shared
    @State private var category: WidgetCategory?
    @State private var query = ""

    private var kinds: [WidgetKind] {
        WidgetKind.allCases.filter {
            (category == nil || $0.category == category) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            currentDock
                .frame(width: 270)
            Divider()
            gallery
        }
    }

    private var currentDock: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("In your Dock").font(.system(size: 15, weight: .semibold))
                Text("\(store.activeProfile?.name ?? "") profile · drag to reorder")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(16)
            List {
                ForEach(store.widgets) { item in
                    CurrentWidgetRow(item: item)
                }
                .onMove { from, to in store.widgets.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            if store.widgets.isEmpty {
                Text("Your Dock is empty. Add widgets from the gallery →")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding()
            }
        }
        .background(Color.primary.opacity(0.025))
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search widgets", text: $query).textFieldStyle(.plain)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip(nil, "All", "square.grid.3x3.fill")
                        ForEach(WidgetCategory.allCases) { c in chip(c, c.rawValue, c.symbol) }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(kinds) { k in WidgetCard(kind: k) }
                }
            }
            .padding(20)
        }
    }

    private func chip(_ c: WidgetCategory?, _ title: String, _ symbol: String) -> some View {
        let on = category == c
        return Button { withAnimation(.snappy) { category = c } } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(on ? .white : .primary)
                .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

private struct CurrentWidgetRow: View {
    let item: WidgetItem
    @ObservedObject private var store = Store.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary)
            SymbolBadge(symbol: item.kind.symbol, colors: [item.kind.tint.opacity(0.85), item.kind.tint], size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.kind.title).font(.system(size: 12, weight: .medium))
                if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Spacer()
            if item.kind == .folder && store.data.folders.count > 1 {
                Menu {
                    ForEach(store.data.folders) { f in
                        Button(f.name) { store.setOption(item.id, "folder", f.id.uuidString) }
                    }
                } label: { Image(systemName: "folder") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            Button { store.remove(item.id) } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.vertical, 2)
    }

    private var detail: String? {
        switch item.kind {
        case .worldClock: item.options["city"]
        case .progress: (item.options["period"] ?? "day").capitalized
        case .folder: store.data.folders.first { $0.id.uuidString == item.options["folder"] }?.name ?? store.data.folders.first?.name
        default: nil
        }
    }
}

private struct WidgetCard: View {
    let kind: WidgetKind
    @ObservedObject private var store = Store.shared
    @State private var hover = false

    var body: some View {
        let added = store.contains(kind)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SymbolBadge(symbol: kind.symbol, colors: [kind.tint.opacity(0.8), kind.tint], size: 38)
                Spacer()
                if added && !kind.allowsMultiple {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.green)
                } else {
                    Button(added ? "Add Another" : "Add") { store.add(kind) }
                        .buttonStyle(PillButtonStyle(tint: .accentColor))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(.system(size: 13, weight: .semibold))
                Text(kind.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            Text(kind.category.rawValue).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary).textCase(.uppercase)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(hover ? 0.07 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        Form {
            Section("Theme") {
                HStack(spacing: 14) {
                    ForEach(DockTheme.allCases) { t in ThemeCard(theme: t, selected: store.settings.theme == t) {
                        store.settings.theme = t
                    } }
                }
                .padding(.vertical, 6)
                HStack {
                    Text("Accent")
                    Spacer()
                    ForEach(AccentChoice.allCases) { a in
                        Circle().fill(a.color.gradient)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(store.settings.accent == a ? 0.8 : 0), lineWidth: 2).padding(-3))
                            .onTapGesture { store.settings.accent = a }
                            .padding(.horizontal, 2)
                    }
                }
            }
            Section("Layout") {
                Picker("Size", selection: $store.settings.size) {
                    ForEach(DockSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Position", selection: $store.settings.position) {
                    ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(store.settings.floating)
                HStack {
                    Text("Distance from edge")
                    Slider(value: $store.settings.edgeMargin, in: 0...60)
                    Text("\(Int(store.settings.edgeMargin)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 44)
                }
                .disabled(store.settings.floating)
                Toggle(isOn: $store.settings.floating) {
                    VStack(alignment: .leading) {
                        Text("Free placement")
                        Text("Drag Dockside anywhere by the edge of its bar.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Behavior") {
                Toggle(isOn: $store.settings.autoHide) {
                    VStack(alignment: .leading) {
                        Text("Auto‑hide")
                        Text("Slides in when the pointer touches the \(store.settings.position == .top ? "top" : "bottom") edge of the screen. ⌃⌥D keeps it open.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .disabled(store.settings.floating)
                Toggle(isOn: $store.settings.avoidMacDock) {
                    VStack(alignment: .leading) {
                        Text("Stay above the macOS Dock")
                        Text("Leaves room for an auto‑hiding Dock so the two never overlap.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .disabled(store.settings.floating || store.settings.position == .top)
                Toggle(isOn: $store.settings.aboveWindows) {
                    VStack(alignment: .leading) {
                        Text("Keep above windows")
                        Text("When off, Dockside sits on the desktop behind your windows.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Toggle("Show on all Spaces", isOn: $store.settings.allSpaces)
                Toggle("Hover animations", isOn: $store.settings.hoverEffects)
            }
        }
        .formStyle(.grouped)
        // Show an auto-hidden dock while its look is being changed.
        .onChange(of: store.settings) { AppDelegate.shared?.peekDock() }
    }
}

private struct ThemeCard: View {
    let theme: DockTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.55, green: 0.7, blue: 0.45), Color(red: 0.85, green: 0.85, blue: 0.7)],
                                   startPoint: .bottom, endPoint: .top)
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4).fill(tile).frame(width: i == 1 ? 30 : 18, height: 18)
                        }
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(bar))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
                }
                .frame(width: 112, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1))
                Text(theme.title).font(.system(size: 11, weight: selected ? .semibold : .regular))
            }
        }
        .buttonStyle(.plain)
    }

    private var bar: AnyShapeStyle {
        switch theme {
        case .dark: AnyShapeStyle(Color.black.opacity(0.85))
        case .glass: AnyShapeStyle(Color.black.opacity(0.3))
        case .light: AnyShapeStyle(Color.white.opacity(0.85))
        case .system: AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.85), .black.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
        }
    }

    private var tile: Color {
        switch theme {
        case .dark: .white.opacity(0.14)
        case .glass: .white.opacity(0.3)
        case .light: .black.opacity(0.08)
        case .system: .gray.opacity(0.4)
        }
    }
}

// MARK: - Apps & folders

private struct AppsSettings: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        Form {
            Section {
                ForEach(store.data.favoriteApps, id: \.self) { path in
                    HStack {
                        Image(nsImage: IconCache.shared.icon(for: path)).resizable().frame(width: 24, height: 24)
                        Text(Launcher.appName(path))
                        Spacer()
                        Button { store.data.favoriteApps.removeAll { $0 == path } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }.buttonStyle(.plain)
                    }
                }
                .onMove { store.data.favoriteApps.move(fromOffsets: $0, toOffset: $1) }
                Button("Add Apps…") {
                    Launcher.chooseApps { paths in
                        store.data.favoriteApps.append(contentsOf: paths.filter { !store.data.favoriteApps.contains($0) })
                    }
                }
            } header: {
                Text("Favorite Apps")
            } footer: {
                Text("You can also drop apps from Finder straight onto the Favorite Apps widget.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            ForEach($store.data.folders) { $folder in
                Section {
                    TextField("Folder name", text: $folder.name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(folder.apps, id: \.self) { a in
                                VStack(spacing: 2) {
                                    Image(nsImage: IconCache.shared.icon(for: a)).resizable().frame(width: 36, height: 36)
                                    Text(Launcher.appName(a)).font(.system(size: 9)).lineLimit(1).frame(width: 52)
                                }
                                .overlay(alignment: .topTrailing) {
                                    Button { folder.apps.removeAll { $0 == a } } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .gray)
                                    }.buttonStyle(.plain).offset(x: 2, y: -4)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        Button("Add Apps…") {
                            Launcher.chooseApps { folder.apps.append(contentsOf: $0.filter { !folder.apps.contains($0) }) }
                        }
                        Spacer()
                        Button("Delete Folder", role: .destructive) {
                            let id = folder.id
                            store.data.folders.removeAll { $0.id == id }
                        }
                    }
                } header: {
                    Label(folder.name.isEmpty ? "Folder" : folder.name, systemImage: "folder.fill")
                }
            }
            Section {
                Button {
                    store.data.folders.append(AppFolder(name: "New Folder", apps: []))
                } label: { Label("New Folder", systemImage: "folder.badge.plus") }
            } footer: {
                Text("Add an “App Folder” widget for each folder you want in the Dock.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Profiles

private struct ProfilesSettings: View {
    @ObservedObject private var store = Store.shared
    private let symbols = ["house.fill", "briefcase.fill", "hammer.fill", "gamecontroller.fill", "paintbrush.fill",
                           "graduationcap.fill", "music.note", "airplane", "moon.fill", "sparkles"]

    var body: some View {
        Form {
            Section {
                ForEach($store.data.profiles) { $profile in
                    let active = profile.id == store.data.activeProfileID
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(symbols, id: \.self) { s in
                                Button { profile.symbol = s } label: { Label(s, systemImage: s) }
                            }
                        } label: {
                            Image(systemName: profile.symbol)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8).fill((active ? Color.accentColor : Color.gray).gradient))
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: $profile.name).textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                            Text("\(profile.widgets.count) widgets").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if active {
                            Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12, weight: .medium))
                        } else {
                            Button("Activate") { withAnimation { store.data.activeProfileID = profile.id } }
                        }
                        Menu {
                            Button("Duplicate") {
                                var copy = profile
                                copy.id = UUID()
                                copy.name += " Copy"
                                copy.widgets = copy.widgets.map { var w = $0; w.id = UUID(); return w }
                                store.data.profiles.append(copy)
                            }
                            Button("Delete", role: .destructive) {
                                let id = profile.id
                                store.data.profiles.removeAll { $0.id == id }
                                if store.data.activeProfileID == id { store.data.activeProfileID = store.data.profiles.first?.id }
                            }
                            .disabled(store.data.profiles.count <= 1)
                        } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Each profile has its own set of widgets. Switch from the menu bar or by right‑clicking the Dock.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    let p = DockProfile(name: "New Profile", symbol: "sparkles", widgets: [WidgetItem(kind: .clock)])
                    store.data.profiles.append(p)
                    store.data.activeProfileID = p.id
                } label: { Label("New Profile", systemImage: "plus") }
                Button("Restore Default Profiles") {
                    store.data.profiles.append(contentsOf: DockData.defaultProfiles)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionsSettings: View {
    @ObservedObject private var cal = CalendarService.shared
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var body: some View {
        Form {
            Section {
                row("Calendar", "calendar", .red, cal.eventsAccess, "Upcoming events in the Calendar widget") { cal.requestEvents() }
                row("Reminders", "list.bullet", .blue, cal.remindersAccess, "Show and complete Apple Reminders") { cal.requestReminders() }
                row("Microphone", "mic.fill", .orange, mic, "Record voice memos") {
                    AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { mic = ok } }
                }
            } header: {
                Text("Data access")
            } footer: {
                Text("Dockside only asks when a widget needs it. Nothing leaves your Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section {
                info("Automation", "applescript.fill", .purple,
                     "Now Playing, Dark Mode and Empty Trash control Music, Spotify, System Events and Finder. macOS asks the first time.",
                     "Privacy_Automation")
                info("Screen Recording", "rectangle.dashed.badge.record", .pink,
                     "Needed by the Screenshots widget and the Color Picker on some systems.", "Privacy_ScreenCapture")
                info("Files & Folders", "folder.fill", .cyan,
                     "The Downloads widget reads your Downloads folder.", "Privacy_FilesAndFolders")
            } header: {
                Text("System")
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ title: String, _ symbol: String, _ color: Color, _ granted: Bool, _ detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: symbol, colors: [color.opacity(0.8), color], size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
            } else {
                Button("Allow", action: action)
            }
        }
    }

    private func info(_ title: String, _ symbol: String, _ color: Color, _ detail: String, _ anchor: String) -> some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: symbol, colors: [color.opacity(0.8), color], size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Settings") { CalendarService.openPrivacy(anchor) }
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            AppGlyph(size: 112)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            Text("Dockside").font(.system(size: 30, weight: .bold))
            Text("A useful Dock for live widgets.").font(.system(size: 15)).foregroundStyle(.secondary)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") · Public Beta")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            HStack(spacing: 10) {
                feature("lock.shield.fill", "Local first")
                feature("bolt.fill", "Live widgets")
                feature("square.stack.3d.up.fill", "Profiles")
            }
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ s: String, _ t: String) -> some View {
        Label(t, systemImage: s)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// The app's icon, drawn in SwiftUI so it can be shown anywhere at any size.
struct AppGlyph: View {
    var size: CGFloat

    var body: some View {
        let r = size * 0.225
        ZStack {
            LinearGradient(colors: [Color(red: 0.96, green: 0.95, blue: 0.88), Color(red: 0.62, green: 0.76, blue: 0.48), Color(red: 0.27, green: 0.47, blue: 0.27)],
                           startPoint: .top, endPoint: .bottom)
            HStack(spacing: size * 0.04) {
                RoundedRectangle(cornerRadius: size * 0.05).fill(Color.white.opacity(0.18))
                    .overlay(Text("9:41").font(.system(size: size * 0.09, weight: .bold, design: .rounded)).foregroundStyle(.white))
                    .frame(width: size * 0.3)
                Circle().trim(from: 0, to: 0.7).stroke(Color(red: 0.25, green: 0.9, blue: 0.45), style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(size * 0.04)
                    .frame(width: size * 0.17)
                RoundedRectangle(cornerRadius: size * 0.04).fill(LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.17)
            }
            .padding(size * 0.04)
            .frame(height: size * 0.26)
            .background(RoundedRectangle(cornerRadius: size * 0.08, style: .continuous).fill(Color.black.opacity(0.88)))
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, size * 0.12)
            .padding(.horizontal, size * 0.08)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
    }
}
