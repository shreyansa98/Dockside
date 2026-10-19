import SwiftUI

// MARK: - Weather

struct WeatherWidget: View {
    @ObservedObject private var weather = WeatherService.shared
    @Environment(\.palette) private var p

    var body: some View {
        PopoverTile(padding: 16, popoverWidth: 300) {
            if let w = weather.current {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(w.temperature)°")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(p.primary)
                        Text(w.city.isEmpty ? "Today" : w.city)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(p.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 76, alignment: .leading)
                    }
                    HStack(spacing: 14) {
                        ForEach(w.days.dropFirst().prefix(3)) { d in
                            VStack(spacing: 3) {
                                Text(d.weekday).font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                                Image(systemName: d.symbol)
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 14))
                                    .frame(height: 16)
                                Text("\(d.high)°").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.primary)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if weather.loading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor) }
                    Text(weather.error ?? "Weather").font(.system(size: 12, weight: .medium)).foregroundStyle(p.secondary)
                }
                .frame(width: 180)
            }
        } popover: {
            WeatherDetail()
        }
    }
}

struct WeatherDetail: View {
    @ObservedObject private var weather = WeatherService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let w = weather.current {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.city.isEmpty ? "Current Location" : w.city).font(.system(size: 15, weight: .semibold))
                        Text("\(w.temperature)°").font(.system(size: 48, weight: .light, design: .rounded))
                        Text(w.condition).font(.system(size: 13, weight: .medium))
                        if let today = w.days.first {
                            Text("H:\(today.high)°  L:\(today.low)°").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 44))
                }
                HStack(spacing: 8) {
                    stat("thermometer.medium", "Feels like", "\(w.feelsLike)°")
                    stat("humidity.fill", "Humidity", "\(w.humidity)%")
                    stat("wind", "Wind", "\(w.wind) \(Store.shared.settings.fahrenheit ? "mph" : "km/h")")
                }
                Divider()
                VStack(spacing: 6) {
                    ForEach(w.days) { d in
                        HStack {
                            Text(Calendar.current.isDateInToday(d.date) ? "Today" : d.date.formatted(.dateTime.weekday(.wide)))
                                .font(.system(size: 12, weight: .medium)).frame(width: 90, alignment: .leading)
                            Image(systemName: d.symbol).symbolRenderingMode(.multicolor).frame(width: 24)
                            Spacer()
                            Text("\(d.low)°").foregroundStyle(.secondary).font(.system(size: 12)).monospacedDigit()
                            Capsule().fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 60, height: 4)
                            Text("\(d.high)°").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        }
                    }
                }
                HStack {
                    Text("Updated \(Formatters.relative.localizedString(for: w.updated, relativeTo: Date()))")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Button { weather.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                }
            } else {
                Text(weather.error ?? "Loading weather…").foregroundStyle(.secondary)
                Button("Retry") { weather.refresh() }
            }
        }
    }

    private func stat(_ symbol: String, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Now playing

struct NowPlayingWidget: View {
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p
    @State private var showInfo = false

    private var sourceName: String { music.player?.displayName ?? store.settings.musicSource.title }

    var body: some View {
        Tile(padding: 8) {
            HStack(spacing: 12) {
                artwork
                    .onTapGesture { music.openPlayer() }
                    .help("Open \(sourceName)")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(music.title.isEmpty ? "Not Playing" : music.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.primary)
                            .lineLimit(1)
                        if music.jsBlockedBrowser != nil {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(music.artist.isEmpty ? sourceName : music.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.secondary)
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        let v = music.duration > 0 ? music.livePosition / music.duration : 0
                        BarProgress(value: v, height: 4)
                            .padding(.top, 4)
                            .overlay {
                                GeometryReader { g in
                                    Color.clear.contentShape(Rectangle())
                                        .gesture(DragGesture(minimumDistance: 0).onEnded { e in
                                            if music.duration > 0 { music.seek(to: max(0, min(1, e.location.x / g.size.width))) }
                                        })
                                }
                            }
                    }
                }
                .frame(width: 128, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { NSApp.activate(ignoringOtherApps: true); showInfo = true }
                .popover(isPresented: $showInfo, arrowEdge: store.settings.position == .top ? .bottom : .top) {
                    NowPlayingSourcePopover().frame(width: 300).padding(16)
                }
                HStack(spacing: 6) {
                    CircleIconButton(symbol: "backward.fill", size: 34, help: "Previous") { music.previous() }
                    CircleIconButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 42,
                                     help: music.isPlaying ? "Pause" : "Play") { music.playPause() }
                    CircleIconButton(symbol: "forward.fill", size: 34, help: "Next") { music.next() }
                }
                .padding(.trailing, 4)
            }
        }
    }

    @ViewBuilder private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        Group {
            if let img = music.artwork {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: placeholderColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: isYouTube ? "play.circle.fill" : "music.note")
                        .font(.system(size: isYouTube ? 24 : 20, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private var isYouTube: Bool {
        if case .youtube = music.player { return true }
        return music.player == nil && (store.settings.musicSource == .youtubeMusic || store.settings.musicSource == .automatic)
    }

    private var placeholderColors: [Color] {
        if isYouTube { return [Color(red: 1, green: 0.15, blue: 0.15), Color(red: 0.75, green: 0.05, blue: 0.1)] }
        if music.player == .spotify || (music.player == nil && store.settings.musicSource == .spotify) {
            return [Color(red: 0.2, green: 0.85, blue: 0.4), Color(red: 0.1, green: 0.6, blue: 0.3)]
        }
        return [Color(red: 0.98, green: 0.24, blue: 0.4), Color(red: 0.98, green: 0.45, blue: 0.3)]
    }
}

struct NowPlayingSourcePopover: View {
    @ObservedObject private var music = MusicService.shared
    @ObservedObject private var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(title: "Now Playing", symbol: "music.note", tint: .red)
            Picker("Source", selection: $store.settings.musicSource) {
                ForEach(MusicSource.allCases) { Text($0.title).tag($0) }
            }
            if let b = music.jsBlockedBrowser {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Allow \(b) to be controlled", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                    Text(b == "Safari"
                         ? "In Safari, open Settings ▸ Advanced and enable “Show features for web developers”, then choose Develop ▸ Allow JavaScript from Apple Events."
                         : "In \(b), choose View ▸ Developer ▸ Allow JavaScript from Apple Events. Until then, Dockside uses media keys (needs Accessibility access).")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1)))
            } else if store.settings.musicSource == .youtubeMusic {
                Text("Play music.youtube.com in Chrome, Brave, Edge or Safari. The first time, macOS asks to let Dockside control your browser.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !music.album.isEmpty {
                Label(music.album, systemImage: "square.stack").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Open \(music.player?.displayName ?? store.settings.musicSource.title)") { music.openPlayer() }
                    .buttonStyle(PillButtonStyle(tint: .red))
                Spacer()
            }
        }
    }
}
