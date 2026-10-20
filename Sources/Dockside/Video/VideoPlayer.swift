import AppKit
import SwiftUI
import WebKit

enum VideoSource: String, CaseIterable, Identifiable {
    case youtube, netflix, hotstar
    var id: String { rawValue }

    var title: String {
        switch self {
        case .youtube: "YouTube"
        case .netflix: "Netflix"
        case .hotstar: "JioHotstar"
        }
    }

    var tint: Color {
        switch self {
        case .youtube: Color(red: 1, green: 0.13, blue: 0.13)
        case .netflix: Color(red: 0.9, green: 0.04, blue: 0.08)
        case .hotstar: Color(red: 0.07, green: 0.2, blue: 0.62)
        }
    }

    var home: URL {
        switch self {
        case .youtube: URL(string: "https://www.youtube.com")!
        case .netflix: URL(string: "https://www.netflix.com/browse")!
        case .hotstar: URL(string: "https://www.hotstar.com/in/home")!
        }
    }

    func search(_ query: String) -> URL {
        var c: URLComponents
        switch self {
        case .youtube:
            c = URLComponents(string: "https://www.youtube.com/results")!
            c.queryItems = [.init(name: "search_query", value: query)]
        case .netflix:
            c = URLComponents(string: "https://www.netflix.com/search")!
            c.queryItems = [.init(name: "q", value: query)]
        case .hotstar:
            // JioHotstar has no documented search URL; Explore is its search page.
            c = URLComponents(string: "https://www.hotstar.com/in/explore")!
            c.queryItems = [.init(name: "search_query", value: query)]
        }
        return c.url!
    }
}

enum VideoPlacement { case none, docked, floating }

struct YouTubeResult: Identifiable, Hashable {
    let id: String
    let title: String
    let channel: String
    let duration: String?
    let thumbnail: URL?
}

/// One web view that plays YouTube, Netflix or JioHotstar and moves between the dock tile and the PiP window.
final class VideoPlayer: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let shared = VideoPlayer()

    let webView: WKWebView
    @Published private(set) var placement: VideoPlacement = .none
    @Published private(set) var source: VideoSource?
    @Published var title = ""
    @Published var isPlaying = false
    @Published var error: String?
    @Published var position: Double = 0
    @Published var duration: Double = 0

    var isActive: Bool { placement != .none }
    var progress: Double { duration > 0 ? min(1, position / duration) : 0 }
    private var progressTimer: Timer?
    /// True while WebKit shows a page's video full screen. WebKit moves the web view into its own window then,
    /// so Dockside must not move it anywhere until full screen ends.
    @Published private(set) var inFullscreen = false
    private var fullscreenObserver: NSKeyValueObservation?

    static let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"

    /// Reports play/pause from any <video> on any page, so the dock knows what's playing.
    private static let stateScript = """
    (function(){
      function post(m){ try { webkit.messageHandlers.dockside.postMessage(m); } catch (e) {} }
      ['play','playing'].forEach(function(t){ document.addEventListener(t, function(e){ if (e.target && e.target.tagName === 'VIDEO') post({type:'state', playing:true}); }, true); });
      ['pause','ended'].forEach(function(t){ document.addEventListener(t, function(e){ if (e.target && e.target.tagName === 'VIDEO') post({type:'state', playing:false}); }, true); });
      document.addEventListener('error', function(e){ var v = e.target; if (v && v.tagName === 'VIDEO' && v.error) post({type:'diag', text:'video error ' + v.error.code + ' ' + (v.error.message || '')}); }, true);
      ['encrypted','waitingforkey'].forEach(function(t){ document.addEventListener(t, function(e){ post({type:'diag', text:t}); }, true); });
      window.addEventListener('unhandledrejection', function(e){ var r = e.reason || {}; post({type:'diag', text:'rejection ' + (r.name || '') + ' ' + (r.message || r)}); });
      var ce = console.error; console.error = function(){ post({type:'diag', text:'console ' + [].slice.call(arguments).join(' ').slice(0, 300)}); ce.apply(console, arguments); };
    })();
    """

    /// The largest <video> on the page; streaming sites render one main player.
    private static let mainVideoJS = "[...document.querySelectorAll('video')].sort(function(a,b){return b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight;})[0]"

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 270), configuration: config)
        webView.customUserAgent = Self.safariUA
        webView.setValue(false, forKey: "drawsBackground")
        super.init()
        let ucc = config.userContentController
        ucc.add(self, name: "dockside")
        ucc.addUserScript(WKUserScript(source: Self.stateScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView.navigationDelegate = self
        webView.uiDelegate = self

        fullscreenObserver = webView.observe(\.fullscreenState, options: [.initial, .new]) { [weak self] web, _ in
            let busy = web.fullscreenState != .notInFullscreen
            DispatchQueue.main.async {
                guard let self, self.inFullscreen != busy else { return }
                self.inFullscreen = busy
                // The PiP window floats above WebKit's full-screen window, so it steps aside until full screen ends.
                PiPWindowController.shared.setSuspended(busy)
            }
        }

        // YouTube's own controls are hidden, so poll its time for Dockside's progress bars.
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.pollProgress() }

        NotificationCenter.default.addObserver(forName: .docksideDockDidHide, object: nil, queue: .main) { [weak self] _ in
            // Keep the picture when the dock slides away mid-video.
            guard let self, self.placement == .docked, self.isPlaying, !self.inFullscreen,
                  Store.shared.settings.videoPopOutOnHide else { return }
            self.setPlacement(.floating)
        }
    }

    // MARK: Playback

    func play(_ video: YouTubeResult, placement target: VideoPlacement = .docked) {
        source = .youtube
        currentYouTubeID = video.id
        title = video.title
        error = nil
        isPlaying = false
        webView.loadHTMLString(Self.youtubeHTML(videoID: video.id), baseURL: URL(string: "https://www.youtube-nocookie.com/"))
        setPlacement(target)
    }

    /// Opens a streaming site in the floating window; the user signs in once and browses or searches there.
    func open(_ source: VideoSource, query: String? = nil) {
        self.source = source
        title = source.title
        error = nil
        isPlaying = false
        let url = query.map { source.search($0) } ?? source.home
        webView.load(URLRequest(url: url))
        setPlacement(.floating)
    }

    func togglePlay() {
        if source == .youtube {
            webView.evaluateJavaScript("if (window.player && player.getPlayerState) { player.getPlayerState() === 1 ? player.pauseVideo() : player.playVideo(); }")
        } else {
            webView.evaluateJavaScript("(function(){ var v = \(Self.mainVideoJS); if (v) { v.paused ? v.play() : v.pause(); } })()")
        }
        isPlaying.toggle()
    }

    private func pollProgress() {
        guard isActive else { return }
        let js = source == .youtube
            ? "window.player && player.getCurrentTime ? [player.getCurrentTime(), player.getDuration()] : null"
            : "(function(){ var v = \(Self.mainVideoJS); return v ? [v.currentTime, isFinite(v.duration) ? v.duration : 0] : null; })()"
        webView.evaluateJavaScript(js) { [weak self] r, _ in
            guard let a = r as? [Double], a.count == 2 else { return }
            self?.position = a[0]
            self?.duration = a[1]
        }
    }

    func seek(to fraction: Double) {
        let t = duration * min(max(fraction, 0), 1)
        position = t
        if source == .youtube {
            webView.evaluateJavaScript("window.player && player.seekTo(\(t), true)")
        } else {
            webView.evaluateJavaScript("(function(){ var v = \(Self.mainVideoJS); if (v) v.currentTime = \(t); })()")
        }
    }

    /// Makes the page's main video fill the window, hiding the site around it.
    func fitVideo() {
        webView.evaluateJavaScript("""
        (function(){
          var v = \(Self.mainVideoJS); if (!v) return 'none';
          document.documentElement.style.background = '#000'; document.body.style.background = '#000';
          v.style.cssText += ';position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;z-index:2147483647!important;object-fit:contain!important;background:#000!important';
          return 'ok';
        })()
        """)
    }

    func stop() {
        guard webView.fullscreenState == .notInFullscreen else {
            // Unloading the page mid full screen leaves WebKit's full-screen window half torn down.
            webView.closeAllMediaPresentations { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.finishStop() }
            }
            return
        }
        finishStop()
    }

    private func finishStop() {
        webView.evaluateJavaScript("document.querySelectorAll('video').forEach(function(v){ v.pause(); })")
        webView.load(URLRequest(url: URL(string: "about:blank")!))
        isPlaying = false
        title = ""
        position = 0
        duration = 0
        source = nil
        setPlacement(.none)
    }

    func setPlacement(_ p: VideoPlacement) {
        placement = p
        if p == .floating { PiPWindowController.shared.show(for: source) } else { PiPWindowController.shared.hide() }
    }

    func openInBrowser() {
        if let u = webView.url, u.scheme?.hasPrefix("http") == true, source != .youtube { NSWorkspace.shared.open(u) }
        else if source == .youtube, let id = currentYouTubeID { NSWorkspace.shared.open(URL(string: "https://www.youtube.com/watch?v=\(id)")!) }
    }

    private var currentYouTubeID: String?
    /// Recent page errors, for diagnosing streaming sites.
    static var diagLog: [String] = []

    static func youtubeHTML(videoID: String) -> String {
        let safeID = videoID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:fixed;inset:0;width:100%;height:100%}</style></head>
        <body><div id="p"></div>
        <script>
        function post(m){ try { webkit.messageHandlers.dockside.postMessage(m); } catch (e) {} }
        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('p', {
            width: '100%', height: '100%', videoId: '\(safeID)', host: 'https://www.youtube-nocookie.com',
            playerVars: { autoplay: 1, playsinline: 1, rel: 0, modestbranding: 1, controls: 0, iv_load_policy: 3, fs: 0, disablekb: 1 },
            events: {
              onReady: function(e) { e.target.playVideo(); post({type: 'ready', title: (e.target.getVideoData() || {}).title || ''}); },
              onStateChange: function(e) { post({type: 'state', playing: e.data === 1}); },
              onError: function(e) { post({type: 'error', code: e.data}); }
            }
          });
        }
        </script>
        <script src="https://www.youtube.com/iframe_api"></script>
        </body></html>
        """
    }

    // MARK: WebKit

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let type = m["type"] as? String else { return }
        DispatchQueue.main.async {
            switch type {
            case "state": self.isPlaying = m["playing"] as? Bool ?? false
            case "diag":
                guard let t = m["text"] as? String else { break }
                Self.diagLog = (Self.diagLog + [t]).suffix(60)
                if t.hasPrefix("video error"), let s = self.source, s != .youtube {
                    self.error = String(localized: "\(s.title) couldn’t play this video (\(t)). Try Open in browser.")
                }
            case "ready":
                if let t = m["title"] as? String, !t.isEmpty { self.title = t }
            case "error":
                let code = m["code"] as? Int ?? 0
                self.error = code == 101 || code == 150
                    ? String(localized: "This video can’t be played outside YouTube.")
                    : String(localized: "YouTube couldn’t play this video.")
            default: break
            }
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if source != .youtube { error = nil }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if source != .youtube, let t = webView.title, !t.isEmpty { title = t }
    }

    // Streaming sites open sign-in and player pages in new windows; keep them in the same view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Pages that open a blank window and fill it in later would otherwise wipe the current page.
        if let u = action.request.url, u.scheme?.hasPrefix("http") == true { webView.load(URLRequest(url: u)) }
        return nil
    }

    // MARK: YouTube search (no API key: reads the data embedded in YouTube's results page)

    static func searchYouTube(_ query: String) async throws -> [YouTubeResult] {
        var req = URLRequest(url: VideoSource.youtube.search(query))
        req.setValue(safariUA, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8),
              let start = html.range(of: "var ytInitialData = "),
              let end = html.range(of: ";</script>", range: start.upperBound..<html.endIndex),
              let json = try JSONSerialization.jsonObject(with: Data(html[start.upperBound..<end.lowerBound].utf8)) as Any?
        else { throw URLError(.cannotParseResponse) }

        var out: [YouTubeResult] = []
        func text(_ any: Any?) -> String? {
            guard let d = any as? [String: Any] else { return nil }
            if let s = d["simpleText"] as? String { return s }
            return (d["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        }
        func walk(_ node: Any) {
            if let d = node as? [String: Any] {
                if let v = d["videoRenderer"] as? [String: Any], let id = v["videoId"] as? String {
                    let thumbs = (v["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
                    out.append(YouTubeResult(id: id, title: text(v["title"]) ?? "", channel: text(v["ownerText"]) ?? "",
                                             duration: text(v["lengthText"]),
                                             thumbnail: (thumbs?.last?["url"] as? String).flatMap(URL.init(string:))))
                }
                d.values.forEach(walk)
            } else if let a = node as? [Any] {
                a.forEach(walk)
            }
        }
        walk(json)
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }
}

extension Notification.Name {
    static let docksideDockDidHide = Notification.Name("DocksideDockDidHide")
}

// MARK: - Hosting the shared web view

/// A slot the shared web view moves into when the player's placement matches.
struct VideoSlot: NSViewRepresentable {
    let placement: VideoPlacement
    @ObservedObject var player = VideoPlayer.shared

    final class Container: NSView {
        override func layout() {
            super.layout()
            subviews.forEach { $0.frame = bounds }
        }
    }

    func makeNSView(context: Context) -> Container {
        let v = Container()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.cgColor
        return v
    }

    func updateNSView(_ v: Container, context: Context) {
        let web = player.webView
        // While WebKit is entering, in or leaving full screen the web view lives in WebKit's own window.
        // Pulling it back here mid-transition corrupts AppKit's view tree (and crashes on the next resize).
        guard !player.inFullscreen, web.fullscreenState == .notInFullscreen else { return }
        if player.placement == placement, web.superview !== v {
            web.removeFromSuperview()
            web.frame = v.bounds
            web.autoresizingMask = [.width, .height]
            v.addSubview(web)
        }
    }
}

// MARK: - Floating PiP window

final class PiPWindowController: NSObject, NSWindowDelegate {
    static let shared = PiPWindowController()
    private var panel: NSPanel?

    func show(for source: VideoSource?) {
        if panel == nil { build() }
        guard let p = panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        if source == .youtube {
            p.contentAspectRatio = NSSize(width: 16, height: 9)
            if !p.isVisible { p.setFrame(NSRect(x: vf.maxX - 500, y: vf.minY + 120, width: 480, height: 270), display: false) }
        } else {
            // Setting resize increments is how AppKit drops an aspect ratio. Never assign a 0:0 aspect ratio:
            // AppKit traps on it when a full-screen switch re-fits the window to the screen.
            p.contentResizeIncrements = NSSize(width: 1, height: 1)
            if !p.isVisible || p.frame.width < 700 {
                p.setFrame(NSRect(x: vf.midX - 460, y: vf.minY + 120, width: 920, height: min(580, vf.height - 140)), display: false)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }

    /// Turns the window invisible and click-through while a video is full screen. It stays ordered in, because
    /// WebKit returns the video to it when full screen ends.
    func setSuspended(_ suspended: Bool) {
        panel?.alphaValue = suspended ? 0 : 1
        panel?.ignoresMouseEvents = suspended
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.title = "Dockside Video"
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { p.standardWindowButton($0)?.isHidden = true }
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.backgroundColor = .black
        p.minSize = NSSize(width: 240, height: 135)
        p.delegate = self
        p.contentViewController = NSHostingController(rootView: PiPView())
        panel = p
    }

    func windowWillClose(_ notification: Notification) {
        VideoPlayer.shared.stop()
    }
}

private struct PiPView: View {
    @ObservedObject private var player = VideoPlayer.shared
    @State private var hover = false

    var body: some View {
        ZStack {
            VideoSlot(placement: .floating)
            if let message = player.error {
                VStack(spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "Open in browser")) { player.openInBrowser() }
                        .buttonStyle(PillButtonStyle(tint: player.source?.tint ?? .red))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.75)))
                .padding(20)
            }
            if hover {
                VStack {
                    HStack(spacing: 6) {
                        pipButton("xmark", String(localized: "Close")) { player.stop() }
                        Text(player.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .lineLimit(1).shadow(radius: 2)
                        Spacer()
                        if player.source != .youtube {
                            pipButton("arrow.up.left.and.arrow.down.right", String(localized: "Fit video")) { player.fitVideo() }
                            pipButton("chevron.left", String(localized: "Back")) { player.webView.goBack() }
                        }
                        pipButton("safari", String(localized: "Open in browser")) { player.openInBrowser() }
                        pipButton("dock.arrow.down.rectangle", String(localized: "Play in the dock")) { player.setPlacement(.docked) }
                    }
                    .padding(8)
                    .background(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom))
                    .background(WindowDragArea())
                    Spacer()
                    HStack(spacing: 10) {
                        pipButton(player.isPlaying ? "pause.fill" : "play.fill", String(localized: "Play")) { player.togglePlay() }
                        if player.duration > 0 {
                            Text(Formatters.duration(player.position)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            Scrubber(value: player.progress) { player.seek(to: $0) }
                            Text(Formatters.duration(player.duration)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        } else {
                            Spacer()
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                }
                .transition(.opacity)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }

    private func pipButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(0.55)))
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

/// A thin draggable progress bar for video.
struct Scrubber: View {
    var value: Double
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3))
                Capsule().fill(Color.white).frame(width: max(4, g.size.width * value))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { e in onSeek(e.location.x / max(1, g.size.width)) })
        }
        .frame(height: 16)
    }
}
