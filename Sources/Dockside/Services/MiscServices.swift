import AppKit
import EventKit
import AVFoundation
import Carbon
import Combine

// MARK: - Clipboard

final class ClipboardService: ObservableObject {
    static let shared = ClipboardService()

    struct Entry: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let date: Date
    }

    @Published var history: [Entry] = []
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.check() }
    }

    func ignoreNextChange() { lastChange = NSPasteboard.general.changeCount }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        guard Store.shared.settings.keepClipboardHistory,
              // Respect password managers that mark their copies as transient/concealed.
              !(pb.types ?? []).contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")),
              let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        history.removeAll { $0.text == s }
        history.insert(Entry(text: s, date: Date()), at: 0)
        if history.count > 30 { history.removeLast(history.count - 30) }
    }

    func copy(_ e: Entry) {
        Launcher.copy(e.text)
        history.removeAll { $0.id == e.id }
        history.insert(Entry(text: e.text, date: Date()), at: 0)
    }
}

// MARK: - Calendar & Reminders

final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    let store = EKEventStore()
    @Published var events: [EKEvent] = []
    @Published var reminders: [EKReminder] = []
    @Published var eventsAccess = false
    @Published var remindersAccess = false

    private init() {
        eventsAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersAccess = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.reload() }
        reload()
    }

    func requestEvents() {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                self.eventsAccess = granted
                self.reload()
                if !granted { Self.openPrivacy("Privacy_Calendars") }
            }
        }
    }

    func requestReminders() {
        store.requestFullAccessToReminders { granted, _ in
            DispatchQueue.main.async {
                self.remindersAccess = granted
                self.reload()
                if !granted { Self.openPrivacy("Privacy_Reminders") }
            }
        }
    }

    static func openPrivacy(_ anchor: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(u)
        }
    }

    func reload() {
        if eventsAccess {
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
            let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            events = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
        }
        if remindersAccess {
            let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: pred) { r in
                let sorted = (r ?? []).sorted {
                    ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture)
                }
                DispatchQueue.main.async { self.reminders = sorted }
            }
        }
    }

    var nextEvent: EKEvent? {
        let now = Date()
        return events.first { !$0.isAllDay && $0.endDate > now } ?? events.first { $0.endDate > now }
    }

    func complete(_ r: EKReminder) {
        r.isCompleted = true
        try? store.save(r, commit: true)
        reminders.removeAll { $0.calendarItemIdentifier == r.calendarItemIdentifier }
    }

    func addReminder(_ title: String) {
        guard let cal = store.defaultCalendarForNewReminders() else { return }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = cal
        try? store.save(r, commit: true)
        reload()
    }
}

// MARK: - Running apps

final class RunningAppsService: ObservableObject {
    static let shared = RunningAppsService()
    @Published var apps: [NSRunningApplication] = []
    @Published var frontmost: pid_t = 0

    private init() {
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                  NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        let me = ProcessInfo.processInfo.processIdentifier
        apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
        frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    }

    func isRunning(path: String) -> Bool {
        apps.contains { $0.bundleURL?.path == path }
    }
}

// MARK: - Pomodoro

final class PomodoroService: ObservableObject {
    static let shared = PomodoroService()

    enum Mode { case focus, rest }

    @Published var mode: Mode = .focus
    @Published var remaining: TimeInterval = 25 * 60
    @Published var running = false
    @Published var sessionsToday = 0

    private var endDate: Date?
    private var timer: Timer?

    var total: TimeInterval {
        let s = Store.shared.settings
        return TimeInterval((mode == .focus ? s.focusMinutes : s.breakMinutes) * 60)
    }

    var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    init() { remaining = total }

    func toggle() { running ? pause() : startTimer() }

    func startTimer() {
        endDate = Date().addingTimeInterval(remaining)
        running = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    func pause() {
        running = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        mode = .focus
        remaining = total
    }

    func skip() { finish(playSound: false) }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { finish(playSound: true) }
    }

    private func finish(playSound: Bool) {
        let wasRunning = running
        pause()
        if mode == .focus { sessionsToday += 1 }
        mode = mode == .focus ? .rest : .focus
        remaining = total
        if playSound { NSSound(named: "Glass")?.play() }
        if wasRunning { startTimer() }
    }
}

// MARK: - Volume

final class VolumeService: ObservableObject {
    static let shared = VolumeService()
    @Published var volume: Double = 0.5
    @Published var muted = false
    private var timer: Timer?
    private var lastSet = Date.distantPast

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
    }

    func poll() {
        guard Date().timeIntervalSince(lastSet) > 1.5 else { return }
        AppleScriptRunner.shared.run("""
        set v to get volume settings
        return ((output volume of v) as string) & "|" & ((output muted of v) as string)
        """) { [weak self] d in
            guard let self, let parts = d?.stringValue?.components(separatedBy: "|"), parts.count == 2 else { return }
            if let v = Double(parts[0]) { self.volume = v / 100 }
            self.muted = parts[1] == "true"
        }
    }

    func set(_ v: Double) {
        volume = min(1, max(0, v))
        lastSet = Date()
        if muted { muted = false }
        AppleScriptRunner.shared.run("set volume output volume \(Int(volume * 100)) without output muted")
    }

    func toggleMute() {
        muted.toggle()
        lastSet = Date()
        AppleScriptRunner.shared.run("set volume output muted \(muted)")
    }
}

// MARK: - System toggles

final class TogglesService: ObservableObject {
    static let shared = TogglesService()
    @Published var darkMode = false
    @Published var keepAwake = false
    @Published var desktopIcons = true

    private var caffeinate: Process?

    private init() { refresh() }

    func refresh() {
        darkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        Shell.runAsync("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"]) { [weak self] r in
            self?.desktopIcons = !(r == "0" || r?.lowercased() == "false")
        }
    }

    func toggleDarkMode() {
        darkMode.toggle()
        AppleScriptRunner.shared.run("""
        tell application "System Events" to tell appearance preferences to set dark mode to \(darkMode)
        """) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refresh() }
        }
    }

    func toggleKeepAwake() {
        if let p = caffeinate {
            p.terminate()
            caffeinate = nil
            keepAwake = false
        } else {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-di", "-w", String(ProcessInfo.processInfo.processIdentifier)]
            try? p.run()
            caffeinate = p
            keepAwake = true
        }
    }

    func toggleDesktopIcons() {
        desktopIcons.toggle()
        let v = desktopIcons ? "true" : "false"
        Shell.runAsync("/bin/sh", ["-c", "defaults write com.apple.finder CreateDesktop -bool \(v) && killall Finder"])
    }

    func lockScreen() {
        typealias LockFn = @convention(c) () -> Void
        if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let sym = dlsym(h, "SACLockScreenImmediate") {
            unsafeBitCast(sym, to: LockFn.self)()
        } else {
            Shell.runAsync("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    func stopAll() { caffeinate?.terminate() }
}

// MARK: - Voice memos

final class VoiceMemoService: NSObject, ObservableObject {
    static let shared = VoiceMemoService()
    @Published var recording = false
    @Published var started = Date()
    private var recorder: AVAudioRecorder?

    var folder: URL {
        let u = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("Dockside Memos")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func toggle() { recording ? stop() : begin() }

    private func begin() {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async {
                guard ok else { CalendarService.openPrivacy("Privacy_Microphone"); return }
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
                let url = self.folder.appendingPathComponent("Memo \(f.string(from: Date())).m4a")
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
                self.recorder = try? AVAudioRecorder(url: url, settings: settings)
                if self.recorder?.record() == true {
                    self.started = Date()
                    self.recording = true
                }
            }
        }
    }

    private func stop() {
        recorder?.stop()
        recorder = nil
        recording = false
        NSSound(named: "Pop")?.play()
    }

    var recent: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == "m4a" }
            .sorted { (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast >
                      (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
    }
}

// MARK: - GitHub

final class GitHubService: ObservableObject {
    static let shared = GitHubService()
    struct Profile { var login: String; var name: String; var followers: Int; var following: Int; var repos: Int; var avatar: URL? }
    struct Repo: Identifiable { var id: Int; var name: String; var stars: Int; var url: String; var language: String? }

    @Published var profile: Profile?
    @Published var repos: [Repo] = []
    @Published var error: String?
    private var loadedUser = ""
    private var lastLoad = Date.distantPast

    func load(force: Bool = false) {
        let user = Store.shared.settings.githubUser.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty else { profile = nil; return }
        guard force || user != loadedUser || Date().timeIntervalSince(lastLoad) > 900 else { return }
        loadedUser = user
        lastLoad = Date()
        Task {
            do {
                let (d, _) = try await URLSession.shared.data(from: URL(string: "https://api.github.com/users/\(user)")!)
                guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], j["login"] != nil else {
                    throw URLError(.badServerResponse)
                }
                let p = Profile(login: j["login"] as? String ?? user, name: j["name"] as? String ?? user,
                                followers: j["followers"] as? Int ?? 0, following: j["following"] as? Int ?? 0,
                                repos: j["public_repos"] as? Int ?? 0, avatar: (j["avatar_url"] as? String).flatMap(URL.init(string:)))
                let (rd, _) = try await URLSession.shared.data(from: URL(string: "https://api.github.com/users/\(user)/repos?sort=updated&per_page=6")!)
                let arr = (try? JSONSerialization.jsonObject(with: rd) as? [[String: Any]]) ?? []
                let repos = arr.map { Repo(id: $0["id"] as? Int ?? 0, name: $0["name"] as? String ?? "",
                                           stars: $0["stargazers_count"] as? Int ?? 0, url: $0["html_url"] as? String ?? "",
                                           language: $0["language"] as? String) }
                await MainActor.run { self.profile = p; self.repos = repos; self.error = nil }
            } catch {
                await MainActor.run { self.error = "User not found"; self.profile = nil }
            }
        }
    }
}

// MARK: - Global hotkey

final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var actions: [UInt32: () -> Void] = [:]
    private static var installed = false
    private static var nextID: UInt32 = 1

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action
        if !HotKey.installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                let pressed = hk.id
                DispatchQueue.main.async { HotKey.actions[pressed]?() }
                return noErr
            }, 1, &spec, nil, nil)
            HotKey.installed = true
        }
        let hkID = EventHotKeyID(signature: OSType(0x43444F4B), id: id)
        RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.actions[id] = nil
    }
}
