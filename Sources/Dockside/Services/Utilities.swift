import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Shell {
    /// Runs a command synchronously and returns trimmed stdout.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func runAsync(_ launchPath: String, _ args: [String], completion: ((String?) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = run(launchPath, args)
            DispatchQueue.main.async { completion?(r) }
        }
    }
}

/// NSAppleScript isn't thread-safe, so every script runs on one serial queue.
final class AppleScriptRunner {
    static let shared = AppleScriptRunner()
    private let queue = DispatchQueue(label: "dockside.applescript", qos: .userInitiated)
    private var cache: [String: NSAppleScript] = [:]

    func run(_ source: String, completion: ((NSAppleEventDescriptor?) -> Void)? = nil) {
        queue.async {
            let script: NSAppleScript
            if let s = self.cache[source] { script = s } else {
                guard let s = NSAppleScript(source: source) else { return }
                self.cache[source] = s
                script = s
            }
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            let value: NSAppleEventDescriptor? = error == nil ? result : nil
            DispatchQueue.main.async { completion?(value) }
        }
    }
}

final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for path: String) -> NSImage {
        if let i = cache.object(forKey: path as NSString) { return i }
        // Resolve symlinks (e.g. /Applications/Safari.app) so icons don't get an alias badge.
        let i = NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        cache.setObject(i, forKey: path as NSString)
        return i
    }
}

enum Launcher {
    static func open(path: String) {
        let url = URL(fileURLWithPath: path)
        if path.hasSuffix(".app") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    static func open(url: String) {
        var s = url.trimmingCharacters(in: .whitespaces)
        if !s.contains("://") { s = "https://" + s }
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func appName(_ path: String) -> String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        ClipboardService.shared.ignoreNextChange()
    }

    static func chooseApps(completion: @escaping ([String]) -> Void) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { completion(panel.urls.map(\.path)) }
    }
}

enum DropHelper {
    /// Pulls file URLs out of drag providers and delivers them on the main queue.
    static func fileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                var url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let url { lock.lock(); urls.append(url); lock.unlock() }
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}

/// A file row that can be dragged out of a popover into Finder or another app.
struct FileRow: View {
    var path: String
    var subtitle: String? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        Button { Launcher.open(path: path) } label: {
            HStack(spacing: 10) {
                Image(nsImage: IconCache.shared.icon(for: path)).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text((path as NSString).lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    if let subtitle { Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                if let onRemove {
                    Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                }
            }
        }
        .buttonStyle(RowButtonStyle())
        .onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { Launcher.open(path: path) }
            Button("Show in Finder") { Launcher.reveal(path) }
            Button("Copy Path") { Launcher.copy(path) }
        }
    }
}

enum Formatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func bytes(_ v: Double) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = v
        var i = 0
        while value >= 1000 && i < units.count - 1 { value /= 1000; i += 1 }
        return i == 0 ? "\(Int(value)) \(units[i])" : String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[i])
    }

    static func duration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
