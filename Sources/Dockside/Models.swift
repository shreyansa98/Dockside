import SwiftUI

// MARK: - Widget catalogue

enum WidgetCategory: String, CaseIterable, Codable, Identifiable {
    case apps = "Apps & Files"
    case productivity = "Productivity"
    case system = "Mac Controls"
    case media = "Media & Weather"
    case utility = "Creator & Utility"
    case developer = "Developer"
    case ai = "AI"

    var id: String { rawValue }
    var title: String { String(localized: String.LocalizationValue(rawValue)) }

    var symbol: String {
        switch self {
        case .apps: "square.grid.2x2.fill"
        case .productivity: "checklist"
        case .system: "slider.horizontal.3"
        case .media: "music.note"
        case .utility: "paintpalette.fill"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .ai: "sparkles"
        }
    }
}

enum WidgetKind: String, CaseIterable, Codable, Identifiable {
    case clock, worldClock, weather, nowPlaying
    case apps, folder, runningApps, search, downloads, fileShelf, bookmarks, trash
    case calendar, reminders, todos, pomodoro, water, progress, notes, countdown
    case cpu, memory, battery, disk, network, toggles, volume
    case clipboard, screenshot, voiceMemo, emoji, colorPicker, calculator, watch
    case github
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: String(localized: "Clock")
        case .worldClock: String(localized: "World Clock")
        case .weather: String(localized: "Weather")
        case .nowPlaying: String(localized: "Now Playing")
        case .apps: String(localized: "Favorite Apps")
        case .folder: String(localized: "App Folder")
        case .runningApps: String(localized: "App Switcher")
        case .search: String(localized: "Search")
        case .downloads: String(localized: "Downloads")
        case .fileShelf: String(localized: "File Shelf")
        case .bookmarks: String(localized: "Bookmarks")
        case .trash: String(localized: "Trash")
        case .calendar: String(localized: "Calendar")
        case .reminders: String(localized: "Reminders")
        case .todos: String(localized: "Todos")
        case .pomodoro: String(localized: "Pomodoro")
        case .water: String(localized: "Drink Water")
        case .progress: String(localized: "Progress")
        case .notes: String(localized: "Quick Note")
        case .countdown: String(localized: "Countdown")
        case .cpu: String(localized: "CPU")
        case .memory: String(localized: "Memory")
        case .battery: String(localized: "Battery")
        case .disk: String(localized: "Storage")
        case .network: String(localized: "Network")
        case .toggles: String(localized: "Quick Toggles")
        case .volume: String(localized: "Audio")
        case .clipboard: String(localized: "Clipboard")
        case .screenshot: String(localized: "Screenshots")
        case .voiceMemo: String(localized: "Voice Memo")
        case .emoji: String(localized: "Emoji")
        case .colorPicker: String(localized: "Color Picker")
        case .calculator: String(localized: "Converter")
        case .watch: String(localized: "Watch")
        case .github: String(localized: "GitHub")
        case .claude: String(localized: "Claude")
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock.fill"
        case .worldClock: "globe.americas.fill"
        case .weather: "cloud.sun.fill"
        case .nowPlaying: "music.note"
        case .apps: "star.square.fill"
        case .folder: "folder.fill"
        case .runningApps: "rectangle.stack.fill"
        case .search: "magnifyingglass"
        case .downloads: "arrow.down.circle.fill"
        case .fileShelf: "tray.full.fill"
        case .bookmarks: "bookmark.fill"
        case .trash: "trash.fill"
        case .calendar: "calendar"
        case .reminders: "list.bullet.circle.fill"
        case .todos: "checkmark.circle.fill"
        case .pomodoro: "timer"
        case .water: "drop.fill"
        case .progress: "chart.pie.fill"
        case .notes: "note.text"
        case .countdown: "hourglass"
        case .cpu: "cpu.fill"
        case .memory: "memorychip.fill"
        case .battery: "battery.75percent"
        case .disk: "internaldrive.fill"
        case .network: "network"
        case .toggles: "switch.2"
        case .volume: "speaker.wave.2.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .screenshot: "camera.viewfinder"
        case .voiceMemo: "mic.fill"
        case .emoji: "face.smiling.inverse"
        case .colorPicker: "eyedropper.halffull"
        case .calculator: "plus.forwardslash.minus"
        case .watch: "play.rectangle.fill"
        case .github: "chevron.left.forwardslash.chevron.right"
        case .claude: "sparkle"
        }
    }

    var tint: Color {
        switch self {
        case .clock, .worldClock: .indigo
        case .weather: .cyan
        case .nowPlaying: .pink
        case .apps, .folder, .runningApps: .blue
        case .search: .gray
        case .downloads, .fileShelf: .teal
        case .bookmarks: .orange
        case .trash: .gray
        case .calendar: .red
        case .reminders, .todos: .green
        case .pomodoro: .orange
        case .water: .blue
        case .progress: .mint
        case .notes: .yellow
        case .countdown: .pink
        case .cpu: .blue
        case .memory: .purple
        case .battery: .green
        case .disk: .orange
        case .network: .cyan
        case .toggles: .indigo
        case .volume: .pink
        case .clipboard: .brown
        case .screenshot: .gray
        case .voiceMemo: .red
        case .emoji: .yellow
        case .colorPicker: .purple
        case .calculator: .orange
        case .watch: .red
        case .github: .gray
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }

    var category: WidgetCategory {
        switch self {
        case .apps, .folder, .runningApps, .search, .downloads, .fileShelf, .bookmarks, .trash: .apps
        case .clock, .worldClock, .calendar, .reminders, .todos, .pomodoro, .water, .progress, .notes, .countdown: .productivity
        case .cpu, .memory, .battery, .disk, .network, .toggles, .volume, .clipboard, .screenshot, .voiceMemo: .system
        case .weather, .nowPlaying, .watch: .media
        case .emoji, .colorPicker, .calculator: .utility
        case .github: .developer
        case .claude: .ai
        }
    }

    var summary: String {
        switch self {
        case .clock: String(localized: "Time and date with a month calendar.")
        case .worldClock: String(localized: "Keep an eye on another city's time.")
        case .weather: String(localized: "Current conditions and a 3‑day forecast.")
        case .nowPlaying: String(localized: "Control YouTube Music, Spotify or Apple Music.")
        case .apps: String(localized: "Launch your favorite apps in one click.")
        case .folder: String(localized: "Group apps into a compact folder.")
        case .runningApps: String(localized: "Switch between running apps.")
        case .search: String(localized: "Find apps, files and the web instantly.")
        case .downloads: String(localized: "Your most recent downloads.")
        case .fileShelf: String(localized: "Park files temporarily, drag them out later.")
        case .bookmarks: String(localized: "Open your favorite links.")
        case .trash: String(localized: "Drop files to trash them, empty in a click.")
        case .calendar: String(localized: "Your next event and the week ahead.")
        case .reminders: String(localized: "Apple Reminders, ticked off from the Dock.")
        case .todos: String(localized: "A fast local todo list.")
        case .pomodoro: String(localized: "Focus sessions with breaks.")
        case .water: String(localized: "Track glasses of water each day.")
        case .progress: String(localized: "How far through the day, week, month or year.")
        case .notes: String(localized: "Capture an idea before it's gone.")
        case .countdown: String(localized: "Days until the moment you're waiting for.")
        case .cpu: String(localized: "Live processor load.")
        case .memory: String(localized: "Live memory pressure.")
        case .battery: String(localized: "Charge level and power source.")
        case .disk: String(localized: "Free space on your startup disk.")
        case .network: String(localized: "Live download and upload speed.")
        case .toggles: String(localized: "Dark mode, keep awake, desktop icons, lock.")
        case .volume: String(localized: "Output volume and mute.")
        case .clipboard: String(localized: "Your recent clipboard history.")
        case .screenshot: String(localized: "Capture areas, windows and screens.")
        case .voiceMemo: String(localized: "One‑click audio recording.")
        case .emoji: String(localized: "Your favorite emoji, one click to copy.")
        case .colorPicker: String(localized: "Pick any color on screen, copy as hex.")
        case .calculator: String(localized: "Calculator plus unit conversion.")
        case .watch: String(localized: "Search and watch YouTube, Netflix and JioHotstar in picture-in-picture.")
        case .github: String(localized: "Followers and repos for a GitHub user.")
        case .claude: String(localized: "Chat with Claude and view your artifacts.")
        }
    }

    var allowsMultiple: Bool { self == .worldClock || self == .folder || self == .progress || self == .countdown }
}

struct WidgetItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: WidgetKind
    var options: [String: String] = [:]
}

struct DockProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var widgets: [WidgetItem]
}

struct AppFolder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var apps: [String]
}

struct TodoItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var done = false
    var created = Date()
}

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String
}

// MARK: - Settings

enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, top
    var id: String { rawValue }
    var title: String { self == .bottom ? String(localized: "Bottom") : String(localized: "Top") }
}

enum DockDisplay: String, Codable, CaseIterable, Identifiable {
    case main, pointer
    var id: String { rawValue }
    var title: String { self == .main ? String(localized: "Main display") : String(localized: "Follow the pointer") }
}

enum DockTheme: String, Codable, CaseIterable, Identifiable {
    case dark, glass, light, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: String(localized: "Midnight")
        case .glass: String(localized: "Glass")
        case .light: String(localized: "Light")
        case .system: String(localized: "Automatic")
        }
    }
}

enum DockSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
    var scale: CGFloat {
        switch self {
        case .small: 0.84
        case .medium: 1.0
        case .large: 1.16
        }
    }
}

enum AccentChoice: String, Codable, CaseIterable, Identifiable {
    case orange, blue, green, pink, purple, yellow, teal
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .orange: Color(red: 1.0, green: 0.58, blue: 0.18)
        case .blue: Color(red: 0.2, green: 0.55, blue: 1.0)
        case .green: Color(red: 0.2, green: 0.82, blue: 0.4)
        case .pink: Color(red: 1.0, green: 0.3, blue: 0.5)
        case .purple: Color(red: 0.62, green: 0.4, blue: 1.0)
        case .yellow: Color(red: 1.0, green: 0.8, blue: 0.1)
        case .teal: Color(red: 0.2, green: 0.78, blue: 0.82)
        }
    }
}

enum MusicSource: String, Codable, CaseIterable, Identifiable {
    case youtubeMusic, spotify, appleMusic, automatic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .youtubeMusic: String(localized: "YouTube Music")
        case .spotify: String(localized: "Spotify")
        case .appleMusic: String(localized: "Apple Music")
        case .automatic: String(localized: "Automatic")
        }
    }
}

struct DockSettings: Codable, Equatable {
    var visible = true
    var autoHide = true
    var avoidMacDock = true
    var musicSource: MusicSource = .youtubeMusic
    var position: DockPosition = .bottom
    var display: DockDisplay = .main
    var edgeMargin: Double = 8
    var theme: DockTheme = .dark
    var size: DockSize = .medium
    var accent: AccentChoice = .orange
    var floating = false
    var floatingX: Double?
    var floatingY: Double?
    var aboveWindows = true
    var allSpaces = true
    var hoverEffects = true
    var use24h = true
    var showSeconds = false
    var fahrenheit = false
    var weatherCity = ""
    var githubUser = ""
    var waterGoal = 8
    var focusMinutes = 25
    var breakMinutes = 5
    var hotkeyEnabled = true
    var keepClipboardHistory = true
    var videoPopOutOnHide = true
}

// MARK: - Persistent data

struct DockData: Codable {
    var profiles: [DockProfile] = DockData.defaultProfiles
    var activeProfileID: UUID?
    var favoriteApps: [String] = DockData.defaultApps
    var folders: [AppFolder] = [DockData.defaultFolder]
    var todos: [TodoItem] = [
        TodoItem(title: "Try every Dockside widget"),
        TodoItem(title: "Pick a wallpaper that matches"),
    ]
    var bookmarks: [Bookmark] = [
        Bookmark(title: "GitHub", url: "https://github.com"),
        Bookmark(title: "YouTube", url: "https://youtube.com"),
        Bookmark(title: "Hacker News", url: "https://news.ycombinator.com"),
    ]
    var notes = ""
    var waterCount = 0
    var waterDay = ""
    var shelf: [String] = []
    var recentColors: [String] = ["#FF9500", "#34C759", "#0A84FF", "#BF5AF2"]
    var emojis: [String] = ["😀", "😂", "😍", "👍", "🔥", "🎉", "🙏"]
    var onboarded = false
    var claudeIntroduced = false

    static var defaultApps: [String] {
        [
            "/Applications/Safari.app",
            "/System/Applications/Music.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/System Settings.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }

    static var defaultFolder: AppFolder {
        let paths = [
            "/System/Applications/Utilities/Activity Monitor.app",
            "/System/Applications/Utilities/Terminal.app",
            "/System/Applications/Utilities/Screenshot.app",
            "/System/Applications/Utilities/Disk Utility.app",
            "/System/Applications/Preview.app",
            "/System/Applications/TextEdit.app",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        return AppFolder(name: "Utilities", apps: paths)
    }

    static var defaultProfiles: [DockProfile] {
        [
            DockProfile(name: "Personal", symbol: "house.fill", widgets: [
                WidgetItem(kind: .clock),
                WidgetItem(kind: .weather),
                WidgetItem(kind: .apps),
                WidgetItem(kind: .progress, options: ["period": "day"]),
                WidgetItem(kind: .nowPlaying),
                WidgetItem(kind: .todos),
            ]),
            DockProfile(name: "Work", symbol: "briefcase.fill", widgets: [
                WidgetItem(kind: .clock),
                WidgetItem(kind: .calendar),
                WidgetItem(kind: .pomodoro),
                WidgetItem(kind: .todos),
                WidgetItem(kind: .notes),
                WidgetItem(kind: .clipboard),
                WidgetItem(kind: .search),
                WidgetItem(kind: .water),
            ]),
            DockProfile(name: "Maker", symbol: "hammer.fill", widgets: [
                WidgetItem(kind: .worldClock, options: ["tz": "America/Los_Angeles", "city": "San Francisco"]),
                WidgetItem(kind: .cpu),
                WidgetItem(kind: .memory),
                WidgetItem(kind: .network),
                WidgetItem(kind: .folder),
                WidgetItem(kind: .colorPicker),
                WidgetItem(kind: .screenshot),
                WidgetItem(kind: .fileShelf),
                WidgetItem(kind: .toggles),
                WidgetItem(kind: .trash),
            ]),
        ]
    }
}
