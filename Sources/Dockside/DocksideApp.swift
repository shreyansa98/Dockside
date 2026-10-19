import SwiftUI
import AppKit
import Carbon
import Combine

@main
struct DocksideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Dockside", systemImage: "dock.rectangle") {
            MenuBarContent()
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        Button(store.settings.visible ? "Hide Dockside" : "Show Dockside") {
            AppDelegate.shared?.setDockVisible(!store.settings.visible)
        }
        .keyboardShortcut("d", modifiers: [.control, .option])
        Divider()
        Picker("Profile", selection: Binding(get: { store.data.activeProfileID }, set: { store.data.activeProfileID = $0 })) {
            ForEach(store.data.profiles) { p in
                Label(p.name, systemImage: p.symbol).tag(Optional(p.id))
            }
        }
        Button("Claude") { ClaudeWindowController.shared.show() }
            .keyboardShortcut("c", modifiers: [.control, .option])
        Button("Customize Widgets…") { SettingsWindowController.shared.show(.widgets) }
        Button("Appearance…") { SettingsWindowController.shared.show(.appearance) }
        Button("Settings…") { SettingsWindowController.shared.show(.general) }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Dockside") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    private var dock: DockWindowController?
    private var hotKey: HotKey?
    private var claudeHotKey: HotKey?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        SystemMonitor.shared.start()
        WeatherService.shared.start()
        MusicService.shared.start()
        ClipboardService.shared.start()
        VolumeService.shared.start()
        _ = RunningAppsService.shared
        _ = CalendarService.shared

        dock = DockWindowController()
        if Store.shared.settings.visible { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.dock?.peek(for: 3) } }

        Store.shared.$settings
            .map(\.hotkeyEnabled).removeDuplicates()
            .sink { [weak self] enabled in
                self?.hotKey = enabled
                    ? HotKey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
                        self?.dock?.toggleFromShortcut()
                    }
                    : nil
                self?.claudeHotKey = enabled
                    ? HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey)) {
                        ClaudeWindowController.shared.toggle()
                    }
                    : nil
            }
            .store(in: &bag)

        // Developer aid: DOCKSIDE_SNAPSHOT=/dir renders the app's own windows to PNGs (no screen-recording permission needed).
        if let dir = ProcessInfo.processInfo.environment["DOCKSIDE_SNAPSHOT"] {
            if let name = ProcessInfo.processInfo.environment["DOCKSIDE_PROFILE"],
               let p = Store.shared.data.profiles.first(where: { $0.name == name }) {
                Store.shared.data.activeProfileID = p.id
            }
            if let q = ProcessInfo.processInfo.environment["DOCKSIDE_ASK"] {
                // "first || follow-up" sends a second turn in the same chat.
                let turns = q.components(separatedBy: " || ")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ClaudeWindowController.shared.ask(turns[0]) }
                for (i, t) in turns.dropFirst().enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i + 1) * 2.5) { ClaudeChat.shared.send(t) }
                }
            }
            if let tab = ProcessInfo.processInfo.environment["DOCKSIDE_TAB"].flatMap(SettingsTab.init(rawValue:)) {
                SettingsWindowController.shared.show(tab)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.dock?.peek(for: 5)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { Self.snapshotWindows(to: dir) }
            }
        }

        if !Store.shared.data.onboarded {
            Store.shared.data.onboarded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                SettingsWindowController.shared.show(.general)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.flush()
        TogglesService.shared.stopAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show(.general)
        return true
    }

    static func snapshotWindows(to dir: String) {
        for (i, w) in NSApp.windows.enumerated() where w.isVisible {
            guard let v = w.contentView?.superview ?? w.contentView,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            let name = w is DockPanel ? "dock" : "window\(i)"
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func setDockVisible(_ visible: Bool) {
        Store.shared.settings.visible = visible
        if visible { DispatchQueue.main.async { self.dock?.peek() } }
    }

    func peekDock() {
        dock?.peek()
    }
}

/// Hosts the SwiftUI settings in a regular window and promotes the app to a regular app while it's open.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(_ tab: SettingsTab) {
        SettingsNav.shared.tab = tab
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: host)
            w.title = "Dockside"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.toolbar = NSToolbar(identifier: "settings")
            w.setContentSize(NSSize(width: 920, height: 640))
            w.minSize = NSSize(width: 780, height: 520)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }
}
