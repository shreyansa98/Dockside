import AppKit
import ApplicationServices

/// Now Playing for YouTube Music (in a browser tab), Spotify and Apple Music.
/// Scripts are only compiled for apps that are running, so macOS never asks "Where is Spotify?".
final class MusicService: ObservableObject {
    static let shared = MusicService()

    enum Player: Equatable {
        case music, spotify
        case youtube(browser: Browser)

        var displayName: String {
            switch self {
            case .music: "Apple Music"
            case .spotify: "Spotify"
            case .youtube: "YouTube Music"
            }
        }
    }

    struct Browser: Equatable {
        let name: String       // AppleScript application name
        let bundleID: String
        let isSafari: Bool

        static let all: [Browser] = [
            Browser(name: "Google Chrome", bundleID: "com.google.Chrome", isSafari: false),
            Browser(name: "Brave Browser", bundleID: "com.brave.Browser", isSafari: false),
            Browser(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", isSafari: false),
            Browser(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", isSafari: false),
            Browser(name: "Chromium", bundleID: "org.chromium.Chromium", isSafari: false),
            Browser(name: "Safari", bundleID: "com.apple.Safari", isSafari: true),
        ]
    }

    @Published var player: Player?
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var artwork: NSImage?
    @Published var positionStamp = Date()
    /// Set when a browser has YouTube Music open but refuses JavaScript from Apple Events.
    @Published var jsBlockedBrowser: String?

    private var timer: Timer?
    private var artworkKey = ""

    private static let appBundleIDs: [String: String] = ["Music": "com.apple.Music", "Spotify": "com.spotify.client"]
    private static let ytURL = "https://music.youtube.com"

    var source: MusicSource { Store.shared.settings.musicSource }

    func start() {
        guard timer == nil else { return }
        if ProcessInfo.processInfo.environment["DOCKSIDE_DEMO"] != nil {
            // Screenshot mode: a fixed sample track instead of reading the user's players.
            title = "Midnight City"
            artist = "M83"
            isPlaying = true
            duration = 243
            position = 97
            positionStamp = Date()
            return
        }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: Candidates

    private var candidates: [Player] {
        var out: [Player] = []
        let src = source
        if src == .youtubeMusic || src == .automatic {
            out += Browser.all.filter { isRunning($0.bundleID) }.map { .youtube(browser: $0) }
        }
        if (src == .spotify || src == .automatic), isRunning(Self.appBundleIDs["Spotify"]!) { out.append(.spotify) }
        if (src == .appleMusic || src == .automatic), isRunning(Self.appBundleIDs["Music"]!) { out.append(.music) }
        return out
    }

    // MARK: Scripts

    private func appScript(_ p: Player) -> String {
        let app = p == .spotify ? "Spotify" : "Music"
        let duration = p == .spotify ? "((duration of t) / 1000)" : "(duration of t)"
        return """
        tell application "\(app)"
            if player state is stopped then return "stopped"
            set t to current track
            return (name of t) & "|~|" & (artist of t) & "|~|" & (album of t) & "|~|" & (player state as string) & "|~|" & (player position as string) & "|~|" & (\(duration) as string)\(p == .spotify ? " & \"|~|\" & (artwork url of t)" : "")
        end tell
        """
    }

    /// Reads track info from YouTube Music's Media Session metadata. Single quotes only: it's embedded in AppleScript.
    private static let infoJS = """
    (function(){var v=document.querySelector('video');var s=navigator.mediaSession;var m=s&&s.metadata;if(!m||!m.title){return '';}var a='';if(m.artwork&&m.artwork.length){a=m.artwork[m.artwork.length-1].src;}var playing=v?!v.paused:(s.playbackState==='playing');return [m.title,m.artist,m.album,playing?'playing':'paused',v?v.currentTime:0,(v&&isFinite(v.duration))?v.duration:0,a].join('|~|');})()
    """

    private enum YTCommand {
        case playPause, next, previous, seek(Double)
        var js: String {
            switch self {
            case .playPause:
                "(function(){var b=document.querySelector('#play-pause-button');if(b){b.click();}else{var v=document.querySelector('video');if(v){if(v.paused){v.play();}else{v.pause();}}}return 'ok';})()"
            case .next:
                "(function(){var b=document.querySelector('.next-button');if(b){b.click();}return 'ok';})()"
            case .previous:
                "(function(){var b=document.querySelector('.previous-button');if(b){b.click();}return 'ok';})()"
            case .seek(let t):
                "(function(){var v=document.querySelector('video');if(v){v.currentTime=\(t);}return 'ok';})()"
            }
        }
    }

    /// Finds the first YouTube Music tab and runs `js` in it. Returns "JS<result>", "TITLE<tab title>" (JS refused) or "NONE".
    private func tabScript(_ b: Browser, js: String) -> String {
        let run = b.isSafari ? "do JavaScript \"\(js)\" in t" : "execute t javascript \"\(js)\""
        let title = b.isSafari ? "name of t" : "title of t"
        return """
        tell application "\(b.name)"
            repeat with w in windows
                repeat with t in tabs of w
                    set u to ""
                    try
                        set u to URL of t
                    end try
                    if u starts with "\(Self.ytURL)" then
                        try
                            return "JS" & (\(run))
                        on error
                            return "TITLE" & (\(title))
                        end try
                    end if
                end repeat
            end repeat
            return "NONE"
        end tell
        """
    }

    private func focusScript(_ b: Browser) -> String {
        let select = b.isSafari ? "set current tab of w to t" : "set active tab index of w to i"
        return """
        tell application "\(b.name)"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    set u to ""
                    try
                        set u to URL of t
                    end try
                    if u starts with "\(Self.ytURL)" then
                        \(select)
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
            return "NONE"
        end tell
        """
    }

    // MARK: Polling

    private struct Result {
        var fields: [String]?   // title, artist, album, state, position, duration, artwork
        var jsBlocked = false
        var tabOpen = false
    }

    private func poll() {
        let players = candidates
        guard !players.isEmpty else {
            jsBlockedBrowser = nil
            if player != nil { clear() }
            return
        }
        var results: [Int: Result] = [:]
        let group = DispatchGroup()
        for (i, p) in players.enumerated() {
            group.enter()
            let script: String = if case .youtube(let b) = p { tabScript(b, js: Self.infoJS) } else { appScript(p) }
            AppleScriptRunner.shared.run(script) { desc in
                results[i] = Self.parse(desc?.stringValue, player: p)
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.jsBlockedBrowser = players.enumerated().first { results[$0.offset]?.jsBlocked == true }
                .flatMap { if case .youtube(let b) = $0.element { b.name } else { nil } }

            let indices = players.indices
            let pick = indices.first { results[$0]?.fields?[safe: 3] == "playing" }
                ?? indices.first { results[$0]?.fields != nil }
            if let i = pick, let f = results[i]?.fields {
                self.apply(player: players[i], fields: f)
            } else {
                // Keep a reference to an open YouTube Music tab (or running app) so the play button targets it.
                let idle = indices.first { results[$0]?.tabOpen == true }.map { players[$0] }
                    ?? players.first { if case .youtube = $0 { false } else { true } }
                self.clear(keepPlayer: idle)
            }
        }
    }

    private static func parse(_ s: String?, player: Player) -> Result {
        guard let s else { return Result() }
        if case .youtube = player {
            if s.hasPrefix("JS") {
                let body = String(s.dropFirst(2))
                let f = body.components(separatedBy: "|~|")
                return Result(fields: f.count >= 6 ? f : nil, tabOpen: true)
            }
            if s.hasPrefix("TITLE") {
                // JavaScript is turned off: fall back to the tab title, e.g. "Song • Artist - YouTube Music".
                var t = String(s.dropFirst(5))
                for suffix in [" - YouTube Music", " – YouTube Music"] where t.hasSuffix(suffix) { t.removeLast(suffix.count) }
                guard !t.isEmpty, t != "YouTube Music" else { return Result(jsBlocked: true, tabOpen: true) }
                let parts = t.components(separatedBy: " • ")
                return Result(fields: [parts[0], parts.count > 1 ? parts[1] : "", "", "playing", "0", "0", ""],
                              jsBlocked: true, tabOpen: true)
            }
            return Result()
        }
        guard s != "stopped" else { return Result() }
        let f = s.components(separatedBy: "|~|")
        return Result(fields: f.count >= 6 ? f : nil)
    }

    private func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private func apply(player p: Player, fields f: [String]) {
        player = p
        title = f[0]
        artist = f[1]
        album = f[2]
        isPlaying = f[3] == "playing"
        position = num(f[4])
        duration = num(f[5])
        positionStamp = Date()

        let key = "\(p.displayName)|\(f[0])|\(f[1])|\(f[safe: 6] ?? "")"
        if key != artworkKey {
            artworkKey = key
            loadArtwork(player: p, url: f[safe: 6])
        }
    }

    private func loadArtwork(player p: Player, url: String?) {
        if p == .music {
            AppleScriptRunner.shared.run("""
            tell application "Music"
                try
                    return raw data of artwork 1 of current track
                end try
            end tell
            """) { [weak self] desc in
                self?.artwork = desc.flatMap { NSImage(data: $0.data) }
            }
        } else if let url, !url.isEmpty, let u = URL(string: url) {
            URLSession.shared.dataTask(with: u) { data, _, _ in
                let img = data.flatMap(NSImage.init(data:))
                DispatchQueue.main.async { self.artwork = img }
            }.resume()
        } else {
            artwork = nil
        }
    }

    private func clear(keepPlayer: Player? = nil) {
        player = keepPlayer
        title = ""
        artist = ""
        album = ""
        isPlaying = false
        position = 0
        duration = 0
        artwork = nil
        artworkKey = ""
    }

    var livePosition: Double {
        guard isPlaying else { return position }
        return min(duration, position + Date().timeIntervalSince(positionStamp))
    }

    // MARK: Controls

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.poll() }
    }

    private func youtube(_ cmd: YTCommand, fallbackKey: Int32?) {
        guard case .youtube(let b) = player else { return }
        if jsBlockedBrowser == b.name {
            if let fallbackKey { MediaKeys.press(fallbackKey) }
            refreshSoon()
            return
        }
        AppleScriptRunner.shared.run(tabScript(b, js: cmd.js)) { [weak self] _ in self?.refreshSoon() }
    }

    private func appCommand(_ command: String) {
        let app = player == .spotify ? "Spotify" : "Music"
        AppleScriptRunner.shared.run("tell application \"\(app)\" to \(command)") { [weak self] _ in self?.refreshSoon() }
    }

    func playPause() {
        guard let player else {
            // Nothing open yet: start the chosen service.
            switch source {
            case .youtubeMusic, .automatic: NSWorkspace.shared.open(URL(string: Self.ytURL)!)
            case .spotify: openApp("Spotify")
            case .appleMusic: openApp("Music")
            }
            return
        }
        isPlaying.toggle()
        positionStamp = Date()
        if case .youtube = player { youtube(.playPause, fallbackKey: MediaKeys.play) } else { appCommand("playpause") }
    }

    func next() {
        if case .youtube = player { youtube(.next, fallbackKey: MediaKeys.next) } else if player != nil { appCommand("next track") }
    }

    func previous() {
        if case .youtube = player { youtube(.previous, fallbackKey: MediaKeys.previous) } else if player != nil { appCommand("previous track") }
    }

    func seek(to fraction: Double) {
        let t = duration * fraction
        position = t
        positionStamp = Date()
        if case .youtube = player { youtube(.seek(t), fallbackKey: nil) } else if player != nil { appCommand("set player position to \(t)") }
    }

    func openPlayer() {
        switch player {
        case .youtube(let b):
            AppleScriptRunner.shared.run(focusScript(b))
        case .spotify:
            openApp("Spotify")
        case .music:
            openApp("Music")
        case nil:
            if source == .spotify { openApp("Spotify") }
            else if source == .appleMusic { openApp("Music") }
            else { NSWorkspace.shared.open(URL(string: Self.ytURL)!) }
        }
    }

    private func openApp(_ name: String) {
        if let id = Self.appBundleIDs[name], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Hardware media keys, used when a browser won't accept JavaScript from Apple Events. Needs Accessibility access.
enum MediaKeys {
    static let play: Int32 = 16
    static let next: Int32 = 17
    static let previous: Int32 = 18

    static func press(_ key: Int32) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else { return }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
