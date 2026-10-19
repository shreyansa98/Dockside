import SwiftUI
import Combine

/// Where Dockside keeps its files. `DOCKSIDE_DATA_DIR` points it elsewhere (used for demo screenshots).
enum AppPaths {
    static let support: URL = {
        let fm = FileManager.default
        if let custom = ProcessInfo.processInfo.environment["DOCKSIDE_DATA_DIR"], !custom.isEmpty {
            let u = URL(fileURLWithPath: custom, isDirectory: true)
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let u = base.appendingPathComponent("Dockside", isDirectory: true)
        // The app was called CoolDock during early development; carry that data over once.
        let legacy = base.appendingPathComponent("CoolDock", isDirectory: true)
        if !fm.fileExists(atPath: u.path), fm.fileExists(atPath: legacy.path) {
            try? fm.copyItem(at: legacy, to: u)
        }
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
}

/// Single source of truth for everything the user configures. Persisted as JSON in Application Support.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var settings: DockSettings
    @Published var data: DockData

    private var bag = Set<AnyCancellable>()
    private let folder: URL

    private init() {
        folder = AppPaths.support

        settings = Store.load(DockSettings.self, from: folder.appendingPathComponent("settings.json"), defaults: DockSettings())
        data = Store.load(DockData.self, from: folder.appendingPathComponent("data.json"), defaults: DockData())

        if data.activeProfileID == nil || !data.profiles.contains(where: { $0.id == data.activeProfileID }) {
            data.activeProfileID = data.profiles.first?.id
        }
        if data.profiles.isEmpty {
            data.profiles = DockData.defaultProfiles
            data.activeProfileID = data.profiles.first?.id
        }

        $settings.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save($0, name: "settings.json") }.store(in: &bag)
        $data.dropFirst().debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.save($0, name: "data.json") }.store(in: &bag)

        // One-time: put the Claude widget next to the clock in the active profile.
        if !data.claudeIntroduced {
            data.claudeIntroduced = true
            if let i = data.profiles.firstIndex(where: { $0.id == data.activeProfileID }),
               !data.profiles[i].widgets.contains(where: { $0.kind == .claude }) {
                let pos = data.profiles[i].widgets.firstIndex { $0.kind == .clock }.map { $0 + 1 } ?? 0
                data.profiles[i].widgets.insert(WidgetItem(kind: .claude), at: pos)
            }
        }
    }

    // MARK: Persistence

    /// Decodes stored JSON on top of the defaults so new fields added in later versions never wipe user data.
    private static func load<T: Codable>(_ type: T.Type, from url: URL, defaults: T) -> T {
        guard let stored = try? Data(contentsOf: url),
              let storedObj = try? JSONSerialization.jsonObject(with: stored) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(defaults),
              var base = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return defaults }
        base.merge(storedObj) { _, new in new }
        guard let merged = try? JSONSerialization.data(withJSONObject: base),
              let value = try? JSONDecoder().decode(T.self, from: merged)
        else { return defaults }
        return value
    }

    private func save<T: Encodable>(_ value: T, name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let json = try? encoder.encode(value) else { return }
        try? json.write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    func flush() {
        save(settings, name: "settings.json")
        save(data, name: "data.json")
    }

    // MARK: Profiles & widgets

    var activeProfile: DockProfile? { data.profiles.first { $0.id == data.activeProfileID } }

    var widgets: [WidgetItem] {
        get { activeProfile?.widgets ?? [] }
        set {
            guard let i = data.profiles.firstIndex(where: { $0.id == data.activeProfileID }) else { return }
            data.profiles[i].widgets = newValue
        }
    }

    func add(_ kind: WidgetKind) {
        var item = WidgetItem(kind: kind)
        switch kind {
        case .folder:
            if data.folders.isEmpty { data.folders.append(DockData.defaultFolder) }
            item.options["folder"] = data.folders[0].id.uuidString
        case .worldClock:
            item.options = ["tz": "Europe/London", "city": "London"]
        case .progress:
            item.options = ["period": "day"]
        default: break
        }
        withAnimation(.spring(duration: 0.35)) { widgets.append(item) }
    }

    func remove(_ id: UUID) {
        withAnimation(.spring(duration: 0.35)) { widgets.removeAll { $0.id == id } }
    }

    func move(_ id: UUID, by offset: Int) {
        var list = widgets
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard list.indices.contains(j) else { return }
        list.swapAt(i, j)
        withAnimation(.spring(duration: 0.35)) { widgets = list }
    }

    func setOption(_ id: UUID, _ key: String, _ value: String) {
        var list = widgets
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].options[key] = value
        widgets = list
    }

    func contains(_ kind: WidgetKind) -> Bool { widgets.contains { $0.kind == kind } }

    // MARK: Water

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var waterToday: Int {
        data.waterDay == Store.dayFormatter.string(from: Date()) ? data.waterCount : 0
    }

    func addWater(_ delta: Int) {
        let today = Store.dayFormatter.string(from: Date())
        let current = waterToday
        data.waterDay = today
        data.waterCount = max(0, current + delta)
    }
}
