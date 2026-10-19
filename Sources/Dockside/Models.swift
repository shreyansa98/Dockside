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
    case calendar, reminders, todos, pomodoro, water, progress, notes
    case cpu, memory, battery, disk, network, toggles, volume
    case clipboard, screenshot, voiceMemo, emoji, colorPicker, calculator
    case github
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: "Clock"
        case .worldClock: "World Clock"
        case .weather: "Weather"
        case .nowPlaying: "Now Playing"
        case .apps: "Favorite Apps"
        case .folder: "App Folder"
        case .runningApps: "App Switcher"
        case .search: "Search"
        case .downloads: "Downloads"
        case .fileShelf: "File Shelf"
        case .bookmarks: "Bookmarks"
        case .trash: "Trash"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .todos: "Todos"
        case .pomodoro: "Pomodoro"
        case .water: "Drink Water"
        case .progress: "Progress"
        case .notes: "Quick Note"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .battery: "Battery"
        case .disk: "Storage"
        case .network: "Network"
        case .toggles: "Quick Toggles"
        case .volume: "Audio"
        case .clipboard: "Clipboard"
        case .screenshot: "Screenshots"
        case .voiceMemo: "Voice Memo"
        case .emoji: "Emoji"
        case .colorPicker: "Color Picker"
        case .calculator: "Converter"
        case .github: "GitHub"
        case .claude: "Claude"
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
        case .github: .gray
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }

    var category: WidgetCategory {
        switch self {
        case .apps, .folder, .runningApps, .search, .downloads, .fileShelf, .bookmarks, .trash: .apps
        case .clock, .worldClock, .calendar, .reminders, .todos, .pomodoro, .water, .progress, .notes: .productivity
        case .cpu, .memory, .battery, .disk, .network, .toggles, .volume, .clipboard, .screenshot, .voiceMemo: .system
        case .weather, .nowPlaying: .media
        case .emoji, .colorPicker, .calculator: .utility
        case .github: .developer
        case .claude: .ai
        }
    }

    var summary: String {
        switch self {
        case .clock: "Time and date with a month calendar."
        case .worldClock: "Keep an eye on another city's time."
        case .weather: "Current conditions and a 3‑day forecast."
        case .nowPlaying: "Control YouTube Music, Spotify or Apple Music."
        case .apps: "Launch your favorite apps in one click."
        case .folder: "Group apps into a compact folder."
        case .runningApps: "Switch between running apps."
        case .search: "Find apps, files and the web instantly."
        case .downloads: "Your most recent downloads."
        case .fileShelf: "Park files temporarily, drag them out later."
        case .bookmarks: "Open your favorite links."
        case .trash: "Drop files to trash them, empty in a click."
        case .calendar: "Your next event and the week ahead."
        case .reminders: "Apple Reminders, ticked off from the Dock."
        case .todos: "A fast local todo list."
        case .pomodoro: "Focus sessions with breaks."
        case .water: "Track glasses of water each day."
        case .progress: "How far through the day, week, month or year."
        case .notes: "Capture an idea before it's gone."
        case .cpu: "Live processor load."
        case .memory: "Live memory pressure."
        case .battery: "Charge level and power source."
        case .disk: "Free space on your startup disk."
        case .network: "Live download and upload speed."
        case .toggles: "Dark mode, keep awake, desktop icons, lock."
        case .volume: "Output volume and mute."
        case .clipboard: "Your recent clipboard history."
        case .screenshot: "Capture areas, windows and screens."
        case .voiceMemo: "One‑click audio recording."
        case .emoji: "Your favorite emoji, one click to copy."
        case .colorPicker: "Pick any color on screen, copy as hex."
        case .calculator: "Calculator plus unit conversion."
        case .github: "Followers and repos for a GitHub user."
        case .claude: "Chat with Claude and view your artifacts."
        }
    }

    var allowsMultiple: Bool { self == .worldClock || self == .folder || self == .progress }
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
    var title: String { self == .bottom ? "Bottom" : "Top" }
}

enum DockTheme: String, Codable, CaseIterable, Identifiable {
    case dark, glass, light, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: "Midnight"
        case .glass: "Glass"
        case .light: "Light"
        case .system: "Automatic"
        }
    }
}

enum DockSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
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
        case .youtubeMusic: "YouTube Music"
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        case .automatic: "Automatic"
        }
    }
}

struct DockSettings: Codable, Equatable {
    var visible = true
    var autoHide = true
    var avoidMacDock = true
    var musicSource: MusicSource = .youtubeMusic
    var position: DockPosition = .bottom
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
