import SwiftUI
import AppKit

/// Lays the tiles out at their natural size but reports a size multiplied by `scale`, so the panel can fit the scaled bar.
struct ScaledLayout: Layout {
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: ceil(s.width * scale), height: ceil(s.height * scale))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let v = subviews.first else { return }
        v.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(v.sizeThatFits(.unspecified)))
    }
}

extension Palette {
    static func resolve(_ theme: DockTheme, _ scheme: ColorScheme) -> Palette {
        switch theme {
        case .dark: .dark
        case .glass: .glass
        case .light: .light
        case .system: scheme == .dark ? .dark : .light
        }
    }
}

/// The scrolling content: every tile at the user's chosen size. The panel follows this view's intrinsic size.
struct DockRootView: View {
    @ObservedObject private var store = Store.shared

    var body: some View {
        let s = store.settings.size.scale
        ScaledLayout(scale: s) {
            DockTiles()
                .fixedSize()
                .scaleEffect(s)
        }
    }
}

struct DockTiles: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = store.settings.accent.color
        HStack(spacing: DockMetrics.spacing) {
            ForEach(store.widgets) { item in
                WidgetHost(item: item)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if store.widgets.isEmpty { EmptyDockTile() }
        }
        .padding(DockMetrics.barPadding)
        .background { if store.settings.floating { WindowDragArea() } }
        .environment(\.palette, Palette.resolve(store.settings.theme, scheme))
        .environment(\.dockAccent, accent)
        .tint(accent)
    }
}

/// The fixed bar behind the scrolling tiles.
struct DockBackgroundRoot: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.resolve(store.settings.theme, scheme)
        DockBackground(theme: store.settings.theme, isDark: palette.isDark,
                       radius: DockMetrics.barRadius * store.settings.size.scale)
    }
}

struct DockBackground: View {
    var theme: DockTheme
    var isDark: Bool
    var radius: CGFloat = DockMetrics.barRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            switch theme {
            case .glass:
                VisualEffect(material: .hudWindow, appearance: .darkAqua)
                Color.black.opacity(0.08)
            case .dark:
                VisualEffect(material: .hudWindow, appearance: .darkAqua)
                Color.black.opacity(0.62)
            case .light, .system:
                VisualEffect(material: isDark ? .hudWindow : .popover, appearance: isDark ? .darkAqua : .aqua)
                (isDark ? Color.black.opacity(0.62) : Color.white.opacity(0.35))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(isDark ? Color.white.opacity(theme == .glass ? 0.22 : 0.1) : Color.black.opacity(0.08), lineWidth: 1))
    }
}

/// Lets the user drag the borderless panel around by its background when free placement is on.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct EmptyDockTile: View {
    @Environment(\.palette) private var p
    var body: some View {
        Tile(width: 220) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.system(size: 22))
                Text("Add your first widget").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(p.secondary)
        }
        .onTapGesture { SettingsWindowController.shared.show(.widgets) }
    }
}

/// Tracks the widget being dragged along the dock so drop targets can reorder live.
final class DockDragState: ObservableObject {
    static let shared = DockDragState()
    static let prefix = "dockside-widget:"
    @Published var dragging: UUID?
}

/// Moves the dragged widget into the hovered widget's slot as the pointer passes over it.
struct ReorderDropDelegate: DropDelegate {
    let target: UUID
    let drag: DockDragState

    func validateDrop(info: DropInfo) -> Bool {
        drag.dragging != nil && info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = drag.dragging, dragged != target else { return }
        let store = Store.shared
        var list = store.widgets
        guard let from = list.firstIndex(where: { $0.id == dragged }),
              let to = list.firstIndex(where: { $0.id == target }) else { return }
        list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        withAnimation(.spring(duration: 0.3)) { store.widgets = list }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        drag.dragging = nil
        return true
    }
}

struct WidgetHost: View {
    let item: WidgetItem
    @ObservedObject private var store = Store.shared
    @ObservedObject private var drag = DockDragState.shared
    @State private var hover = false

    var body: some View {
        content
            .scaleEffect(hover && store.settings.hoverEffects ? 1.03 : 1)
            .brightness(hover && store.settings.hoverEffects ? 0.03 : 0)
            .opacity(drag.dragging == item.id ? 0.35 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.35), value: hover)
            .onHover { hover = $0 }
            .onDrag {
                drag.dragging = item.id
                return NSItemProvider(object: (DockDragState.prefix + item.id.uuidString) as NSString)
            }
            .onDrop(of: [.plainText], delegate: ReorderDropDelegate(target: item.id, drag: drag))
            .contextMenu { menu }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .clock: ClockWidget()
        case .worldClock: WorldClockWidget(item: item)
        case .weather: WeatherWidget()
        case .nowPlaying: NowPlayingWidget()
        case .apps: AppsWidget()
        case .folder: FolderWidget(item: item)
        case .runningApps: RunningAppsWidget()
        case .search: SearchWidget()
        case .downloads: DownloadsWidget()
        case .fileShelf: FileShelfWidget()
        case .bookmarks: BookmarksWidget()
        case .trash: TrashWidget()
        case .calendar: CalendarWidget()
        case .reminders: RemindersWidget()
        case .todos: TodosWidget()
        case .pomodoro: PomodoroWidget()
        case .water: WaterWidget()
        case .progress: ProgressWidget(item: item)
        case .countdown: CountdownWidget(item: item)
        case .notes: NotesWidget()
        case .cpu, .memory, .battery, .disk: StatWidget(kind: item.kind)
        case .network: NetworkWidget()
        case .toggles: TogglesWidget()
        case .volume: VolumeWidget()
        case .clipboard: ClipboardWidget()
        case .screenshot: ScreenshotWidget()
        case .voiceMemo: VoiceMemoWidget()
        case .emoji: EmojiWidget()
        case .colorPicker: ColorPickerWidget()
        case .calculator: CalculatorWidget()
        case .github: GitHubWidget()
        case .claude: ClaudeWidget()
        }
    }

    @ViewBuilder private var menu: some View {
        Text(item.kind.title)
        Button { store.move(item.id, by: -1) } label: { Label("Move Left", systemImage: "arrow.left") }
            .disabled(store.widgets.first?.id == item.id)
        Button { store.move(item.id, by: 1) } label: { Label("Move Right", systemImage: "arrow.right") }
            .disabled(store.widgets.last?.id == item.id)
        Button(role: .destructive) { store.remove(item.id) } label: { Label("Remove \(item.kind.title)", systemImage: "minus.circle") }
        Divider()
        Picker("Profile", selection: Binding(get: { store.data.activeProfileID }, set: { store.data.activeProfileID = $0 })) {
            ForEach(store.data.profiles) { p in Text(p.name).tag(Optional(p.id)) }
        }
        Button("Customize Widgets…") { SettingsWindowController.shared.show(.widgets) }
        Button("Appearance…") { SettingsWindowController.shared.show(.appearance) }
        Divider()
        Button("Hide Dockside") { AppDelegate.shared?.setDockVisible(false) }
    }
}
