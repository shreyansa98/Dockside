import SwiftUI
import UniformTypeIdentifiers

// MARK: - App icon

struct AppIconButton: View {
    var path: String
    var size: CGFloat = 44
    var showsRunning = true
    var onRemove: (() -> Void)? = nil

    @ObservedObject private var running = RunningAppsService.shared
    @Environment(\.palette) private var p
    @State private var hover = false

    var body: some View {
        Button { Launcher.open(path: path) } label: {
            Image(nsImage: IconCache.shared.icon(for: path))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .scaleEffect(hover ? 1.12 : 1, anchor: .bottom)
                .offset(y: hover ? -2 : 0)
                .animation(.spring(duration: 0.25, bounce: 0.4), value: hover)
        }
        .buttonStyle(PressableStyle())
        .overlay(alignment: .bottom) {
            if showsRunning && running.isRunning(path: path) {
                Circle().fill(p.primary.opacity(0.75)).frame(width: 3.5, height: 3.5).offset(y: 5)
            }
        }
        .onHover { hover = $0 }
        .help(Launcher.appName(path))
        .contextMenu {
            Button("Open") { Launcher.open(path: path) }
            Button("Show in Finder") { Launcher.reveal(path) }
            if let app = running.apps.first(where: { $0.bundleURL?.path == path }) {
                Button("Quit") { app.terminate() }
            }
            if let onRemove {
                Divider()
                Button("Remove from Dock", role: .destructive, action: onRemove)
            }
        }
    }
}

// MARK: - Favorite apps

struct AppsWidget: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p
    @State private var targeted = false

    var body: some View {
        Tile(padding: 10) {
            HStack(spacing: 8) {
                ForEach(store.data.favoriteApps, id: \.self) { path in
                    AppIconButton(path: path, size: 46) {
                        withAnimation { store.data.favoriteApps.removeAll { $0 == path } }
                    }
                }
                if store.data.favoriteApps.isEmpty {
                    Label("Drop apps here", systemImage: "plus.app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.secondary)
                        .padding(.horizontal, 6)
                        .onTapGesture { addApps() }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: DockMetrics.radius, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: targeted ? 2 : 0))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            DropHelper.fileURLs(from: providers) { urls in
                let apps = urls.map(\.path).filter { $0.hasSuffix(".app") && !store.data.favoriteApps.contains($0) }
                withAnimation(.spring) { store.data.favoriteApps.append(contentsOf: apps) }
            }
            return true
        }
    }

    private func addApps() {
        Launcher.chooseApps { paths in
            store.data.favoriteApps.append(contentsOf: paths.filter { !store.data.favoriteApps.contains($0) })
        }
    }
}

// MARK: - Folder

struct FolderWidget: View {
    let item: WidgetItem
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p

    private var folderIndex: Int? {
        store.data.folders.firstIndex { $0.id.uuidString == item.options["folder"] } ?? (store.data.folders.isEmpty ? nil : 0)
    }

    var body: some View {
        let folder = folderIndex.map { store.data.folders[$0] }
        PopoverTile(width: DockMetrics.tile, padding: 0, popoverWidth: 300) {
            let apps = Array((folder?.apps ?? []).prefix(4))
            LazyVGrid(columns: [GridItem(.fixed(22), spacing: 5), GridItem(.fixed(22), spacing: 5)], spacing: 5) {
                ForEach(apps, id: \.self) { a in
                    Image(nsImage: IconCache.shared.icon(for: a)).resizable().frame(width: 22, height: 22)
                }
                ForEach(0..<max(0, 4 - apps.count), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6).fill(p.control).frame(width: 20, height: 20)
                }
            }
            .help(folder?.name ?? "Folder")
        } popover: {
            if let i = folderIndex {
                FolderPopover(index: i)
            } else {
                Button("Create Folder") { store.data.folders.append(DockData.defaultFolder) }
            }
        }
    }
}

private struct FolderPopover: View {
    let index: Int
    @ObservedObject private var store = Store.shared

    var body: some View {
        let folder = store.data.folders[index]
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(title: LocalizedStringKey(folder.name), symbol: "folder.fill", tint: .blue) {
                Button { Launcher.chooseApps { add($0) } } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("Add apps")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(folder.apps, id: \.self) { a in
                    VStack(spacing: 4) {
                        AppIconButton(path: a, size: 48, showsRunning: false) {
                            store.data.folders[index].apps.removeAll { $0 == a }
                        }
                        Text(Launcher.appName(a)).font(.system(size: 10)).lineLimit(1).truncationMode(.tail)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                DropHelper.fileURLs(from: providers) { add($0.map(\.path)) }
                return true
            }
            if folder.apps.isEmpty {
                Text("Drop apps here or click +").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private func add(_ paths: [String]) {
        let apps = paths.filter { $0.hasSuffix(".app") && !store.data.folders[index].apps.contains($0) }
        store.data.folders[index].apps.append(contentsOf: apps)
    }
}

// MARK: - Running apps

struct RunningAppsWidget: View {
    @ObservedObject private var running = RunningAppsService.shared
    @Environment(\.palette) private var p

    var body: some View {
        Tile(padding: 10) {
            HStack(spacing: 6) {
                ForEach(running.apps.prefix(10), id: \.processIdentifier) { app in
                    Button {
                        app.unhide()
                        app.activate()
                    } label: {
                        Image(nsImage: app.icon ?? NSImage())
                            .resizable()
                            .frame(width: 38, height: 38)
                            .opacity(app.isHidden ? 0.5 : 1)
                    }
                    .buttonStyle(PressableStyle())
                    .overlay(alignment: .bottom) {
                        if app.processIdentifier == running.frontmost {
                            Capsule().fill(p.primary).frame(width: 12, height: 3).offset(y: 6)
                        }
                    }
                    .help(app.localizedName ?? "")
                    .contextMenu {
                        Button("Hide") { app.hide() }
                        Button("Quit") { app.terminate() }
                    }
                }
            }
        }
    }
}

// MARK: - Search

struct AppIndex {
    static let all: [String] = {
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications", "/System/Library/CoreServices/Applications"]
        var out: [String] = []
        for d in dirs {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []
            out += items.filter { $0.hasSuffix(".app") }.map { d + "/" + $0 }
        }
        return Array(Set(out)).sorted { Launcher.appName($0) < Launcher.appName($1) }
    }()
}

struct SearchWidget: View {
    @Environment(\.palette) private var p

    var body: some View {
        PopoverTile(width: 120, popoverWidth: 400) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold))
                Text("Search").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(p.secondary)
        } popover: {
            SearchPopover()
        }
    }
}

private struct SearchPopover: View {
    @Environment(\.dismissPopover) private var dismiss
    @State private var query = ""
    @State private var files: [String] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var apps: [String] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return AppIndex.all.filter { Launcher.appName($0).lowercased().contains(q) }
            .sorted { Launcher.appName($0).lowercased().hasPrefix(q) && !Launcher.appName($1).lowercased().hasPrefix(q) }
            .prefix(6).map { $0 }
    }

    private var calc: String? {
        guard query.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%×÷()")) != nil,
              let v = Calc.evaluate(query) else { return nil }
        return Calc.format(v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
                TextField("Search apps, files and the web", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($focused)
                    .onSubmit(openFirst)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))

            if !query.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if let calc {
                            section("Calculator")
                            Button { Launcher.copy(calc) } label: {
                                HStack {
                                    Image(systemName: "equal.circle.fill").font(.system(size: 22)).foregroundStyle(.orange)
                                    Text(calc).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                                    Spacer()
                                    Text("Copy").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(RowButtonStyle())
                        }
                        if !apps.isEmpty {
                            section("Applications")
                            ForEach(apps, id: \.self) { a in
                                Button { open(a) } label: {
                                    HStack(spacing: 10) {
                                        Image(nsImage: IconCache.shared.icon(for: a)).resizable().frame(width: 26, height: 26)
                                        Text(Launcher.appName(a)).font(.system(size: 13))
                                    }
                                }.buttonStyle(RowButtonStyle())
                            }
                        }
                        if !files.isEmpty {
                            section("Files")
                            ForEach(files, id: \.self) { f in
                                FileRow(path: f, subtitle: (f as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            }
                        }
                        section("Claude")
                        Button {
                            dismiss()
                            ClaudeWindowController.shared.ask(query)
                        } label: {
                            HStack(spacing: 10) {
                                ClaudeBadge(size: 24)
                                Text("Ask Claude “\(query)”").font(.system(size: 13)).lineLimit(1)
                            }
                        }.buttonStyle(RowButtonStyle())
                        section("Web")
                        Button { web() } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "safari.fill").font(.system(size: 22)).foregroundStyle(.blue)
                                Text("Search the web for “\(query)”").font(.system(size: 13)).lineLimit(1)
                            }
                        }.buttonStyle(RowButtonStyle())
                    }
                }
                .frame(maxHeight: 380)
            } else {
                Text("Type to search · Return opens the top result")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: query) { _, q in scheduleFileSearch(q) }
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            .padding(.top, 6).padding(.leading, 8)
    }

    private func scheduleFileSearch(_ q: String) {
        searchTask?.cancel()
        guard q.count >= 2 else { files = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let result = await Task.detached { () -> [String] in
                let out = Shell.run("/usr/bin/mdfind", ["-onlyin", NSHomeDirectory(), "-name", q]) ?? ""
                return out.split(separator: "\n").map(String.init)
                    .filter { !$0.contains("/Library/") && !$0.contains("/.") }
                    .prefix(6).map { $0 }
            }.value
            guard !Task.isCancelled else { return }
            files = result
        }
    }

    private func open(_ path: String) { Launcher.open(path: path); dismiss() }

    private func web() {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [.init(name: "q", value: query)]
        NSWorkspace.shared.open(c.url!)
        dismiss()
    }

    private func openFirst() {
        if let calc { Launcher.copy(calc); return }
        if let a = apps.first { open(a) } else if let f = files.first { open(f) } else { web() }
    }
}

// MARK: - Downloads

struct DownloadsWidget: View {
    @Environment(\.palette) private var p
    @State private var recent: [URL] = []

    private var folder: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    var body: some View {
        PopoverTile(width: DockMetrics.tile, padding: 0, popoverWidth: 320) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.white, Color(red: 0.2, green: 0.6, blue: 1.0).gradient)
        } popover: {
            VStack(alignment: .leading, spacing: 8) {
                PopoverHeader(title: "Downloads", symbol: "arrow.down", tint: .blue) {
                    Button("Open Folder") { NSWorkspace.shared.open(folder) }.buttonStyle(.borderless).font(.system(size: 12))
                }
                if recent.isEmpty {
                    Text("No downloads yet").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(recent, id: \.self) { u in
                            FileRow(path: u.path, subtitle: modified(u))
                        }
                    }
                }
                .frame(maxHeight: 340)
            }
            .onAppear(perform: load)
        }
    }

    private func modified(_ u: URL) -> String {
        let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return Formatters.relative.localizedString(for: d, relativeTo: Date())
    }

    private func load() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .addedToDirectoryDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        func date(_ u: URL) -> Date {
            let v = try? u.resourceValues(forKeys: Set(keys))
            return v?.addedToDirectoryDate ?? v?.contentModificationDate ?? .distantPast
        }
        recent = items.sorted { date($0) > date($1) }.prefix(12).map { $0 }
    }
}

// MARK: - File shelf

struct FileShelfWidget: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p
    @State private var targeted = false

    var body: some View {
        let files = store.data.shelf.filter { FileManager.default.fileExists(atPath: $0) }
        PopoverTile(width: files.isEmpty ? 128 : nil, padding: 12, popoverWidth: 300) {
            HStack(spacing: 10) {
                if files.isEmpty {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 20)).foregroundStyle(.teal)
                    Text("Drop files").font(.system(size: 12, weight: .medium)).foregroundStyle(p.secondary)
                } else {
                    ZStack {
                        ForEach(Array(files.prefix(3).enumerated()), id: \.offset) { i, f in
                            Image(nsImage: IconCache.shared.icon(for: f)).resizable().frame(width: 36, height: 36)
                                .rotationEffect(.degrees(Double(i - 1) * 9))
                                .offset(x: CGFloat(i - 1) * 6)
                        }
                    }
                    .frame(width: 50)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("File Shelf").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                        Text("\(files.count) item\(files.count == 1 ? "" : "s")").font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary)
                    }
                }
            }
            .onDrag {
                // Dragging the stack out drags the most recent file.
                files.first.flatMap { NSItemProvider(contentsOf: URL(fileURLWithPath: $0)) } ?? NSItemProvider()
            }
        } popover: {
            VStack(alignment: .leading, spacing: 8) {
                PopoverHeader(title: "File Shelf", symbol: "tray.full.fill", tint: .teal) {
                    if !files.isEmpty {
                        Button("Clear") { withAnimation { store.data.shelf.removeAll() } }.buttonStyle(.borderless).font(.system(size: 12))
                    }
                }
                Text("Drag files out to move them anywhere.").font(.system(size: 11)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(files, id: \.self) { f in
                            FileRow(path: f) { store.data.shelf.removeAll { $0 == f } }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: DockMetrics.radius, style: .continuous)
            .strokeBorder(Color.teal, style: StrokeStyle(lineWidth: targeted ? 2 : 0, dash: [5])))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            DropHelper.fileURLs(from: providers) { urls in
                let new = urls.map(\.path).filter { !store.data.shelf.contains($0) }
                withAnimation(.spring) { store.data.shelf.insert(contentsOf: new, at: 0) }
            }
            return true
        }
    }
}

// MARK: - Bookmarks

struct BookmarksWidget: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p

    var body: some View {
        PopoverTile(padding: 12, popoverWidth: 300) {
            HStack(spacing: 8) {
                ForEach(store.data.bookmarks.prefix(4)) { b in
                    Favicon(url: b.url, size: 30)
                        .onTapGesture { Launcher.open(url: b.url) }
                        .help(b.title)
                }
                if store.data.bookmarks.isEmpty {
                    Image(systemName: "bookmark.fill").font(.system(size: 20)).foregroundStyle(.orange)
                }
            }
        } popover: {
            BookmarksPopover()
        }
    }
}

struct Favicon: View {
    var url: String
    var size: CGFloat

    private var host: String {
        var s = url
        if !s.contains("://") { s = "https://" + s }
        return URL(string: s)?.host ?? url
    }

    var body: some View {
        AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")) { phase in
            if let img = phase.image {
                img.resizable().interpolation(.high).padding(size * 0.14)
            } else {
                Text(host.prefix(1).uppercased()).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Color.white.opacity(0.92)))
    }
}

private struct BookmarksPopover: View {
    @ObservedObject private var store = Store.shared
    @State private var title = ""
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(title: "Bookmarks", symbol: "bookmark.fill", tint: .orange)
            VStack(spacing: 0) {
                ForEach(store.data.bookmarks) { b in
                    HStack(spacing: 10) {
                        Favicon(url: b.url, size: 24)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(b.title).font(.system(size: 12, weight: .medium))
                            Text(b.url).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { store.data.bookmarks.removeAll { $0.id == b.id } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }.buttonStyle(.plain)
                    }
                    .padding(6)
                    .contentShape(Rectangle())
                    .onTapGesture { Launcher.open(url: b.url) }
                }
            }
            Divider()
            HStack {
                TextField("Title", text: $title).textFieldStyle(.roundedBorder).frame(width: 90)
                TextField("example.com", text: $url).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Add", action: add).disabled(url.isEmpty)
            }
        }
    }

    private func add() {
        guard !url.isEmpty else { return }
        var u = url
        if !u.contains("://") { u = "https://" + u }
        let t = title.isEmpty ? (URL(string: u)?.host ?? u) : title
        store.data.bookmarks.append(Bookmark(title: t, url: u))
        title = ""
        url = ""
    }
}

// MARK: - Trash

struct TrashWidget: View {
    @State private var targeted = false

    var body: some View {
        Tile(width: DockMetrics.tile, padding: 0) {
            Image(nsImage: NSWorkspace.shared.icon(for: .folder).trashIcon)
                .resizable()
                .frame(width: 44, height: 44)
                .scaleEffect(targeted ? 1.15 : 1)
                .animation(.spring, value: targeted)
        }
        .onTapGesture {
            if let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
                NSWorkspace.shared.open(trash)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            DropHelper.fileURLs(from: providers) { urls in
                for u in urls { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
                if !urls.isEmpty { NSSound(named: "Purr")?.play() }
            }
            return true
        }
        .contextMenu {
            Button("Open Trash") {
                if let t = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(t) }
            }
            Button("Empty Trash…") {
                AppleScriptRunner.shared.run("tell application \"Finder\" to empty trash")
            }
        }
        .help("Trash — drop files to delete")
    }
}

private extension NSImage {
    /// The system trash icon, falling back to the passed image.
    var trashIcon: NSImage {
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/TrashIcon.icns"
        return NSImage(contentsOfFile: path) ?? self
    }
}
