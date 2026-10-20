import SwiftUI

/// Search YouTube, Netflix and JioHotstar, and watch in the dock tile or a floating picture-in-picture window.
struct WatchWidget: View {
    @ObservedObject private var player = VideoPlayer.shared
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p
    @State private var showSearch = false

    var body: some View {
        Group {
            if player.placement == .docked {
                dockedPlayer
            } else {
                summaryTile
            }
        }
        .popover(isPresented: $showSearch, arrowEdge: store.settings.position == .top ? .bottom : .top) {
            WatchSearch().frame(width: 420).padding(16)
        }
    }

    private func openSearch() {
        NSApp.activate(ignoringOtherApps: true)
        showSearch = true
    }

    /// The video playing live inside the dock bar.
    private var dockedPlayer: some View {
        Tile(padding: 4) {
            HStack(spacing: 6) {
                VideoSlot(placement: .docked)
                    .frame(width: 100, height: 56)
                    .overlay(alignment: .bottom) {
                        GeometryReader { g in
                            Rectangle().fill(Color.red).frame(width: g.size.width * player.progress, height: 2)
                        }
                        .frame(height: 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(spacing: 2) {
                    smallButton(player.isPlaying ? "pause.fill" : "play.fill", String(localized: "Play")) { player.togglePlay() }
                    smallButton("pip.exit", String(localized: "Picture in picture")) { player.setPlacement(.floating) }
                    smallButton("magnifyingglass", String(localized: "Search")) { openSearch() }
                }
                .padding(.trailing, 2)
            }
        }
    }

    /// Idle, or playing in the floating window.
    private var summaryTile: some View {
        Tile(width: 204, padding: 10) {
            HStack(spacing: 10) {
                SymbolBadge(symbol: player.isActive ? "pip.fill" : "play.rectangle.fill",
                            colors: [Color(red: 1, green: 0.3, blue: 0.3), Color(red: 0.78, green: 0.05, blue: 0.1)], size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.isActive ? (player.title.isEmpty ? String(localized: "Watching") : player.title) : String(localized: "Watch"))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary).lineLimit(1)
                    Text(player.isActive ? String(localized: "Playing in picture-in-picture") : "YouTube · Netflix · JioHotstar")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if player.isActive {
                    smallButton("dock.arrow.down.rectangle", String(localized: "Play in the dock")) { player.setPlacement(.docked) }
                }
            }
        }
        .onTapGesture(perform: openSearch)
    }

    private func smallButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(p.primary)
                .frame(width: 22, height: 18)
                .background(Capsule().fill(p.control))
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

private struct WatchSearch: View {
    @ObservedObject private var player = VideoPlayer.shared
    @Environment(\.dismissPopover) private var dismiss
    @State private var source: VideoSource = .youtube
    @State private var query = ""
    @State private var results: [YouTubeResult] = []
    @State private var loading = false
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(title: "Watch", symbol: "play.rectangle.fill", tint: .red) {
                if player.isActive {
                    Button { player.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                        .buttonStyle(.borderless).font(.system(size: 12))
                }
            }
            Picker("", selection: $source) {
                ForEach(VideoSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(source == .youtube ? "Search YouTube" : "Search \(source.title)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                    .onSubmit(submit)
                if loading { ProgressView().controlSize(.small) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))

            if source == .youtube {
                youtubeResults
            } else {
                streamingHelp
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: source) { results = []; failed = false }
    }

    private var youtubeResults: some View {
        Group {
            if failed {
                Label("Couldn’t load YouTube results. Check your connection and try again.", systemImage: "wifi.exclamationmark")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            } else if results.isEmpty {
                Text("Search, then click a result to play it right in the dock. Use the picture-in-picture button to float it over any app.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(results) { r in resultRow(r) }
                    }
                }
                .frame(height: 360)
            }
        }
    }

    private func resultRow(_ r: YouTubeResult) -> some View {
        HStack(spacing: 10) {
            Button { player.play(r, placement: .docked); dismiss() } label: {
                HStack(spacing: 10) {
                    AsyncImage(url: r.thumbnail) { img in img.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                        Color.primary.opacity(0.08)
                    }
                    .frame(width: 112, height: 63)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottomTrailing) {
                        Text(r.duration ?? String(localized: "LIVE"))
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(r.duration == nil ? Color.red : Color.black.opacity(0.75)))
                            .padding(4)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.title).font(.system(size: 12, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(r.channel).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(RowButtonStyle())
            Button { player.play(r, placement: .floating); dismiss() } label: {
                Image(systemName: "pip.enter").font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Play in picture-in-picture")
        }
    }

    private var streamingHelp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(source.title) opens in a floating window. Sign in once — Dockside remembers you. Start a show, then use Fit video to fill the window, or the dock button to watch it right in the dock.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { player.open(source); dismiss() } label: { Label("Open \(source.title)", systemImage: "play.tv") }
                    .buttonStyle(PillButtonStyle(tint: source.tint))
                Spacer()
            }
        }
    }

    private func submit() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        if source != .youtube {
            player.open(source, query: q)
            dismiss()
            return
        }
        loading = true
        failed = false
        Task {
            let found = try? await VideoPlayer.searchYouTube(q)
            await MainActor.run {
                loading = false
                results = found ?? []
                failed = found == nil
            }
        }
    }
}
