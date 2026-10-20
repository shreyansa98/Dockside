import SwiftUI

// MARK: - Stat gauges

struct StatWidget: View {
    let kind: WidgetKind
    @ObservedObject private var sys = SystemMonitor.shared
    @Environment(\.palette) private var p

    private var value: Double {
        switch kind {
        case .cpu: sys.cpu
        case .memory: sys.memory
        case .battery: sys.battery
        default: sys.diskUsed
        }
    }

    private var color: Color {
        switch kind {
        case .cpu: value > 0.8 ? .red : Color(red: 0.25, green: 0.6, blue: 1)
        case .memory: value > 0.85 ? .red : Color(red: 0.7, green: 0.45, blue: 1)
        case .battery: value < 0.2 && !sys.charging ? .red : Color(red: 0.25, green: 0.85, blue: 0.45)
        default: Color(red: 1, green: 0.6, blue: 0.2)
        }
    }

    private var symbol: String {
        switch kind {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .battery: sys.charging ? "bolt.fill" : (sys.onAC ? "powerplug.fill" : "battery.75percent")
        default: "internaldrive"
        }
    }

    var body: some View {
        PopoverTile(width: DockMetrics.tile, padding: 0, popoverWidth: 240) {
            ZStack {
                RingGauge(value: value, color: color, lineWidth: 4.5)
                    .frame(width: 50, height: 50)
                VStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                    Text(kind == .battery && !sys.hasBattery ? "AC" : "\(Int((value * 100).rounded()))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(p.primary)
                        .contentTransition(.numericText())
                }
                .offset(y: 1)
            }
            .help(kind.title)
        } popover: {
            VStack(alignment: .leading, spacing: 10) {
                PopoverHeader(title: LocalizedStringKey(kind.title), symbol: kind.symbol, tint: color)
                ForEach(details, id: \.0) { row in
                    HStack {
                        Text(row.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(row.1).monospacedDigit().fontWeight(.medium)
                    }
                    .font(.system(size: 12))
                }
                BarProgress(value: value, color: color, height: 6)
                Button("Open Activity Monitor") { Launcher.open(path: "/System/Applications/Utilities/Activity Monitor.app") }
                    .buttonStyle(.borderless).font(.system(size: 12))
            }
        }
    }

    private var details: [(String, String)] {
        let gb: (Double) -> String = { String(format: "%.1f GB", $0 / 1_073_741_824) }
        switch kind {
        case .cpu:
            return [("Total", "\(Int(sys.cpu * 100))%"), ("User", "\(Int(sys.cpuUser * 100))%"),
                    ("System", "\(Int(sys.cpuSystem * 100))%"), ("Cores", "\(ProcessInfo.processInfo.activeProcessorCount)")]
        case .memory:
            return [("Used", gb(sys.memoryUsed)), ("Total", gb(sys.memoryTotal)), ("Pressure", "\(Int(sys.memory * 100))%")]
        case .battery:
            guard sys.hasBattery else { return [("Power", "AC Power")] }
            var rows = [("Charge", "\(Int(sys.battery * 100))%"),
                        ("Source", sys.onAC ? "Power Adapter" : "Battery"),
                        ("Status", sys.charging ? "Charging" : (sys.onAC ? "Not charging" : "Discharging"))]
            if let m = sys.batteryMinutes { rows.append((sys.charging ? "Until full" : "Remaining", "\(m / 60)h \(m % 60)m")) }
            return rows
        default:
            return [("Free", gb(sys.diskFree)), ("Used", gb(sys.diskTotal - sys.diskFree)), ("Capacity", gb(sys.diskTotal))]
        }
    }
}

// MARK: - Network

struct NetworkWidget: View {
    @ObservedObject private var sys = SystemMonitor.shared
    @Environment(\.palette) private var p

    var body: some View {
        Tile(width: 116, padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                row("arrow.down", Formatters.bytes(sys.down) + "/s", Color(red: 0.3, green: 0.65, blue: 1))
                row("arrow.up", Formatters.bytes(sys.up) + "/s", Color(red: 0.3, green: 0.85, blue: 0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help("Network throughput")
    }

    private func row(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .heavy)).foregroundStyle(color)
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(p.primary)
        }
    }
}

// MARK: - Quick toggles

struct TogglesWidget: View {
    @ObservedObject private var t = TogglesService.shared
    @Environment(\.dockAccent) private var accent

    var body: some View {
        Tile(padding: 12) {
            HStack(spacing: 8) {
                toggle("moon.fill", on: t.darkMode, tint: .indigo, help: "Dark Mode") { t.toggleDarkMode() }
                toggle("cup.and.saucer.fill", on: t.keepAwake, tint: .orange, help: "Keep Awake") { t.toggleKeepAwake() }
                toggle(t.desktopIcons ? "desktopcomputer" : "eye.slash.fill", on: !t.desktopIcons, tint: .teal,
                       help: t.desktopIcons ? "Hide Desktop Icons" : "Show Desktop Icons") { t.toggleDesktopIcons() }
                toggle("lock.fill", on: false, tint: .gray, help: "Lock Screen") { t.lockScreen() }
            }
        }
        .onAppear { t.refresh() }
    }

    private func toggle(_ symbol: String, on: Bool, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        CircleIconButton(symbol: symbol, size: 38, fill: on ? tint : nil, foreground: on ? .white : nil, help: help, action: action)
            .animation(.spring(duration: 0.3), value: on)
    }
}

// MARK: - Volume

struct VolumeWidget: View {
    @ObservedObject private var v = VolumeService.shared
    @Environment(\.palette) private var p
    @Environment(\.dockAccent) private var accent

    private var symbol: String {
        if v.muted || v.volume == 0 { return "speaker.slash.fill" }
        return v.volume < 0.33 ? "speaker.wave.1.fill" : v.volume < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    var body: some View {
        Tile(width: 184, padding: 12) {
            HStack(spacing: 10) {
                CircleIconButton(symbol: symbol, size: 36, help: v.muted ? "Unmute" : "Mute") { v.toggleMute() }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.track)
                        Capsule().fill(v.muted ? p.secondary : p.primary)
                            .frame(width: max(10, g.size.width * v.volume))
                    }
                    .frame(height: 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { e in
                        v.set(e.location.x / g.size.width)
                    })
                }
                .frame(height: 30)
                Text("\(Int(v.volume * 100))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(p.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .onAppear { v.start() }
    }
}

// MARK: - Clipboard

struct ClipboardWidget: View {
    @ObservedObject private var clip = ClipboardService.shared
    @Environment(\.palette) private var p

    var body: some View {
        PopoverTile(width: 204, padding: 10, popoverWidth: 340) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: "doc.on.clipboard.fill", colors: [Color(red: 0.75, green: 0.55, blue: 0.35), Color(red: 0.55, green: 0.38, blue: 0.22)], size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipboard").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                    Text(clip.history.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Copy something…")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.primary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        } popover: {
            ClipboardPopover()
        }
    }
}

private struct ClipboardPopover: View {
    @ObservedObject private var clip = ClipboardService.shared
    @Environment(\.dismissPopover) private var dismiss
    @State private var filter = ""

    var body: some View {
        let items = filter.isEmpty ? clip.history : clip.history.filter { $0.text.localizedCaseInsensitiveContains(filter) }
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(title: "Clipboard History", symbol: "doc.on.clipboard", tint: .brown) {
                if !clip.history.isEmpty {
                    Button("Clear") { clip.history.removeAll() }.buttonStyle(.borderless).font(.system(size: 12))
                }
            }
            TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(items) { e in
                        Button { clip.copy(e); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                    .font(.system(size: 12)).lineLimit(2).multilineTextAlignment(.leading)
                                Text(Formatters.relative.localizedString(for: e.date, relativeTo: Date()))
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
            .frame(maxHeight: 340)
            if clip.history.isEmpty {
                Text("Things you copy will appear here. History stays in memory only.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Screenshots

struct ScreenshotWidget: View {
    @Environment(\.palette) private var p

    var body: some View {
        PopoverTile(width: DockMetrics.tile, padding: 0, popoverWidth: 320) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(p.primary)
        } popover: {
            ScreenshotPopover()
        }
    }
}

private struct ScreenshotPopover: View {
    @Environment(\.dismissPopover) private var dismiss
    @State private var toClipboard = false
    @State private var recent: [URL] = []

    static var folder: URL {
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let u = URL(fileURLWithPath: (loc as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(title: "Screenshots", symbol: "camera.viewfinder", tint: .gray) {
                Button("Open Folder") { NSWorkspace.shared.open(Self.folder) }.buttonStyle(.borderless).font(.system(size: 12))
            }
            HStack(spacing: 8) {
                captureButton("Area", "rectangle.dashed", ["-i"])
                captureButton("Window", "macwindow", ["-iW"])
                captureButton("Screen", "display", [])
            }
            Toggle("Copy to clipboard instead of saving", isOn: $toClipboard).font(.system(size: 12))
            if !recent.isEmpty {
                Text("Recent").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(recent, id: \.self) { u in
                        AsyncThumb(url: u)
                            .onTapGesture { NSWorkspace.shared.open(u) }
                            .onDrag { NSItemProvider(contentsOf: u) ?? NSItemProvider() }
                            .contextMenu {
                                Button("Show in Finder") { Launcher.reveal(u.path) }
                                Button("Move to Trash") { try? FileManager.default.trashItem(at: u, resultingItemURL: nil); load() }
                            }
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    private func captureButton(_ title: String, _ symbol: String, _ args: [String]) -> some View {
        Button {
            dismiss()
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let path = Self.folder.appendingPathComponent("Screenshot \(f.string(from: Date())).png").path
            let full = args + (toClipboard ? ["-c"] : [path])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                Shell.runAsync("/usr/sbin/screencapture", full)
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func load() {
        let items = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        recent = items.filter { ["png", "jpg", "heic", "mov"].contains($0.pathExtension.lowercased()) &&
            ($0.lastPathComponent.hasPrefix("Screenshot") || $0.lastPathComponent.hasPrefix("Screen Shot") || $0.lastPathComponent.hasPrefix("Screen Recording")) }
            .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) >
                      ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .prefix(6).map { $0 }
    }
}

struct AsyncThumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
        }
        .frame(height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            let u = url
            let data = await Task.detached { try? Data(contentsOf: u) }.value
            image = data.flatMap(NSImage.init(data:))
        }
    }
}

// MARK: - Voice memo

struct VoiceMemoWidget: View {
    @ObservedObject private var memo = VoiceMemoService.shared
    @Environment(\.palette) private var p

    var body: some View {
        Tile(width: memo.recording ? 124 : DockMetrics.tile, padding: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(memo.recording ? Color.red : p.control).frame(width: 40, height: 40)
                    Image(systemName: memo.recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(memo.recording ? .white : Color.red)
                }
                .symbolEffect(.pulse, isActive: memo.recording)
                if memo.recording {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Formatters.duration(ctx.date.timeIntervalSince(memo.started)))
                            .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(p.primary)
                    }
                }
            }
        }
        .onTapGesture { withAnimation(.spring) { memo.toggle() } }
        .contextMenu {
            Button("Show Recordings in Finder") { NSWorkspace.shared.open(memo.folder) }
            if let last = memo.recent.first {
                Button("Play Latest Memo") { NSWorkspace.shared.open(last) }
            }
        }
        .help(memo.recording ? "Stop recording" : "Record a voice memo")
    }
}
