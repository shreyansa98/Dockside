import SwiftUI
import AppKit
import WebKit

enum ClaudeTab: String, CaseIterable, Identifiable {
    case chat, artifacts, web
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chat: String(localized: "Chat")
        case .artifacts: String(localized: "Artifacts")
        case .web: String(localized: "claude.ai")
        }
    }
}

final class ClaudeNav: ObservableObject {
    static let shared = ClaudeNav()
    @Published var tab: ClaudeTab = .chat
    @Published var openArtifact: UUID?
    @Published var focusInput = 0
}

enum ClaudeBrand {
    static let coral = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let coralDeep = Color(red: 0.74, green: 0.36, blue: 0.24)
}

struct ClaudeBadge: View {
    var size: CGFloat = 40
    var body: some View {
        SymbolBadge(symbol: "sparkle", colors: [ClaudeBrand.coral, ClaudeBrand.coralDeep], size: size)
    }
}

// MARK: - Window

/// A floating, resizable panel for Claude, opened from the dock widget or with ⌃⌥C.
final class ClaudeWindowController: NSObject, NSWindowDelegate {
    static let shared = ClaudeWindowController()
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if let p = panel, p.isVisible, p.isKeyWindow { p.orderOut(nil) } else { show() }
    }

    func show(_ tab: ClaudeTab? = nil) {
        if let tab { ClaudeNav.shared.tab = tab }
        if panel == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        ClaudeNav.shared.focusInput += 1
    }

    func ask(_ question: String) {
        show(.chat)
        ClaudeChat.shared.newChat()
        ClaudeChat.shared.send(question)
    }

    private func build() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.title = "Claude"
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .floating
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        p.minSize = NSSize(width: 420, height: 480)
        p.delegate = self
        p.contentViewController = NSHostingController(rootView: ClaudeRootView())
        if !p.setFrameUsingName("DocksideClaude") {
            if let s = NSScreen.screens.first?.visibleFrame {
                p.setFrame(NSRect(x: s.midX - 280, y: s.minY + 170, width: 560, height: min(700, s.height - 190)), display: false)
            }
        }
        p.setFrameAutosaveName("DocksideClaude")
        panel = p
    }
}

// MARK: - Root

struct ClaudeRootView: View {
    @ObservedObject private var nav = ClaudeNav.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Picker("", selection: $nav.tab) {
                    ForEach(ClaudeTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 270)
                Spacer()
            }
            .padding(.top, 6)
            .frame(height: 38)

            Divider()
            ZStack {
                ChatView().opacity(nav.tab == .chat ? 1 : 0).allowsHitTesting(nav.tab == .chat)
                ArtifactsView().opacity(nav.tab == .artifacts ? 1 : 0).allowsHitTesting(nav.tab == .artifacts)
                ClaudeWebView().opacity(nav.tab == .web ? 1 : 0).allowsHitTesting(nav.tab == .web)
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Chat

struct ChatView: View {
    @ObservedObject private var chat = ClaudeChat.shared
    @ObservedObject private var nav = ClaudeNav.shared
    @State private var input = ""
    @State private var editingKey = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if !chat.hasKey || editingKey {
                KeySetupView(onDone: { editingKey = false })
            } else if let conv = chat.current, !conv.messages.isEmpty {
                messages(conv)
            } else {
                emptyState
            }
            if chat.hasKey && !editingKey { composer }
        }
        .onChange(of: nav.focusInput) { focused = true }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(ClaudeModel.allCases) { m in
                    Button { chat.model = m } label: {
                        if m == chat.model { Label("\(m.title) — \(m.subtitle)", systemImage: "checkmark") }
                        else { Text("\(m.title) — \(m.subtitle)") }
                    }
                }
            } label: {
                Label(chat.model.title, systemImage: "cpu")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Menu {
                if chat.conversations.filter({ !$0.messages.isEmpty }).isEmpty { Text("No chats yet") }
                ForEach(chat.conversations.filter { !$0.messages.isEmpty }.prefix(30)) { c in
                    Button(c.title) { chat.select(c.id) }
                }
                Divider()
                if let id = chat.currentID {
                    Button("Delete This Chat", role: .destructive) { chat.delete(id) }
                }
                Button("API Key…") { editingKey = true }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("History")

            Button { chat.newChat(); focused = true } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.borderless)
                .help("New chat")
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ClaudeBadge(size: 56)
            Text("What can I help with?").font(.system(size: 20, weight: .semibold))
            VStack(spacing: 8) {
                ForEach(["Summarize what I copied", "Build a pomodoro timer web app", "Draw an SVG of a mountain sunset",
                         "Write a weekly plan as a document"], id: \.self) { s in
                    Button {
                        let prompt = s == "Summarize what I copied"
                            ? "Summarize this:\n\n" + (NSPasteboard.general.string(forType: .string) ?? "")
                            : s
                        chat.send(prompt)
                    } label: {
                        Text(s).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func messages(_ conv: Conversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(conv.messages) { m in
                        MessageRow(message: m, isStreaming: chat.streaming && m.id == conv.messages.last?.id)
                            .id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: conv.messages.last?.text) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: conv.messages.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Claude", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...8)
                    .focused($focused)
                    .onSubmit(send)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
                if chat.streaming {
                    CircleIconButton(symbol: "stop.fill", size: 34, fill: Color.primary.opacity(0.15), foreground: .primary, help: "Stop") {
                        chat.stop()
                    }
                } else {
                    CircleIconButton(symbol: "arrow.up", size: 34, fill: input.isEmpty ? Color.gray.opacity(0.4) : ClaudeBrand.coral,
                                     foreground: .white, help: "Send (Return)") { send() }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
            Text("Return to send · ⌥Return for a new line")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .padding(.bottom, 6)
        }
        .onAppear { focused = true }
    }

    private func send() {
        let t = input
        input = ""
        chat.send(t)
    }
}

private struct KeySetupView: View {
    @ObservedObject private var chat = ClaudeChat.shared
    var onDone: () -> Void
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            HStack(spacing: 12) {
                ClaudeBadge(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat with Claude from your dock").font(.system(size: 16, weight: .semibold))
                    Text("Uses the Claude API with your own key, stored in your Keychain.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            SecureField("sk-ant-…", text: $key)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Button("Save Key", action: save).buttonStyle(PillButtonStyle(tint: ClaudeBrand.coral))
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Get an API key") { Launcher.open(url: "https://console.anthropic.com/settings/keys") }
                    .buttonStyle(.borderless)
                Spacer()
                if chat.hasKey {
                    Button("Remove Key", role: .destructive) { chat.setKey(""); onDone() }.buttonStyle(.borderless)
                    Button("Cancel", action: onDone).buttonStyle(.borderless)
                }
            }
            Divider().padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 6) {
                Text("Prefer your Claude subscription?").font(.system(size: 12, weight: .semibold))
                Text("API usage is billed to your Anthropic Console account, separately from a Claude Pro or Max plan. The claude.ai tab uses your regular subscription and shows all your artifacts.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open claude.ai") { ClaudeNav.shared.tab = .web }.buttonStyle(.borderless)
            }
            Spacer()
        }
        .padding(24)
    }

    private func save() {
        chat.setKey(key)
        key = ""
        onDone()
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    @State private var showThinking = false

    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.08)))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ClaudeBadge(size: 20)
                    if isStreaming && message.text.isEmpty {
                        Text(message.thinking.isEmpty ? "Thinking…" : "Thinking").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        ProgressView().controlSize(.small)
                    }
                }
                if !message.thinking.isEmpty {
                    DisclosureGroup(isExpanded: $showThinking) {
                        Text(message.thinking).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(isStreaming && message.text.isEmpty ? "Reasoning…" : "Reasoning")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(MarkdownSegments.parse(message.text).enumerated()), id: \.offset) { i, seg in
                    switch seg {
                    case .text(let t):
                        MarkdownText(source: t)
                    case .code(let lang, let body, let closed):
                        if let kind = ArtifactStore.kind(lang), body.count > 40 {
                            ArtifactCard(kind: kind, source: body, closed: closed, key: "\(message.id.uuidString)-\(i)")
                        } else {
                            CodeBlock(lang: lang, code: body)
                        }
                    }
                }
                if let error = message.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                if let note = message.note, message.error == nil {
                    Text(note).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Block-level Markdown: headings, bullets and paragraphs, with inline styling via AttributedString.
struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                if p.hasPrefix("#") {
                    let level = p.prefix { $0 == "#" }.count
                    inline(String(p.drop { $0 == "#" || $0 == " " }))
                        .font(.system(size: level == 1 ? 18 : level == 2 ? 16 : 14, weight: .semibold))
                        .padding(.top, 4)
                } else {
                    inline(p).font(.system(size: 14))
                }
            }
        }
        .textSelection(.enabled)
    }

    private var paragraphs: [String] {
        source.components(separatedBy: "\n\n").flatMap { block -> [String] in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            // Keep headings on their own line; lists and prose stay together.
            var out: [String] = []
            var buf: [String] = []
            for l in lines {
                if l.hasPrefix("#") {
                    if !buf.isEmpty { out.append(buf.joined(separator: "\n")); buf = [] }
                    out.append(l)
                } else {
                    let t = l.trimmingCharacters(in: .whitespaces)
                    buf.append(t.hasPrefix("- ") || t.hasPrefix("* ") ? "•  " + t.dropFirst(2) : l)
                }
            }
            if !buf.isEmpty { out.append(buf.joined(separator: "\n")) }
            return out
        }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func inline(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let a = try? AttributedString(markdown: s, options: opts) { return Text(a) }
        return Text(s)
    }
}

private struct CodeBlock: View {
    let lang: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button { Launcher.copy(code); copied = true } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct ArtifactCard: View {
    let kind: String
    let source: String
    let closed: Bool
    let key: String
    @ObservedObject private var store = ArtifactStore.shared
    @State private var showCode = false

    var body: some View {
        let saved = store.artifact(forKey: key)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SymbolBadge(symbol: kind == "svg" ? "photo" : kind == "markdown" ? "doc.richtext" : "safari",
                            colors: [ClaudeBrand.coral.opacity(0.8), ClaudeBrand.coralDeep], size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved?.title ?? ArtifactStore.title(kind: kind, source: source))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(closed ? "\(kind.uppercased()) artifact · \(source.split(separator: "\n").count) lines"
                                : "Writing \(kind.uppercased())… \(source.split(separator: "\n").count) lines")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if !closed {
                    ProgressView().controlSize(.small)
                } else if let saved {
                    Button("Open") {
                        ClaudeNav.shared.openArtifact = saved.id
                        ClaudeNav.shared.tab = .artifacts
                    }
                    .buttonStyle(PillButtonStyle(tint: ClaudeBrand.coral))
                }
                Button { showCode.toggle() } label: { Image(systemName: "chevron.left.forwardslash.chevron.right") }
                    .buttonStyle(.borderless).help(showCode ? "Hide code" : "Show code")
            }
            .padding(12)
            if showCode {
                Divider()
                CodeBlock(lang: kind, code: source).padding(8)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}

// MARK: - Artifacts

struct ArtifactsView: View {
    @ObservedObject private var store = ArtifactStore.shared
    @ObservedObject private var nav = ClaudeNav.shared
    @State private var link = ""

    var body: some View {
        if let id = nav.openArtifact, let a = store.items.first(where: { $0.id == id }) {
            ArtifactDetail(artifact: a)
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your claude.ai artifacts").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 8) {
                        webButton("Chat artifacts", "square.on.square", "https://claude.ai/artifacts")
                        webButton("Claude Code artifacts", "chevron.left.forwardslash.chevron.right", "https://claude.ai/code/artifacts")
                    }
                    HStack {
                        TextField("Paste an artifact link (claude.ai/…)", text: $link)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(openLink)
                        Button("Open", action: openLink).disabled(link.isEmpty)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))

                HStack {
                    Text("Made in Dockside").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.open(store.dir) }.buttonStyle(.borderless).font(.system(size: 12))
                }
                if store.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles.rectangle.stack").font(.system(size: 30)).foregroundStyle(.tertiary)
                        Text("Ask Claude in the Chat tab for a web page, chart, SVG or document — it shows up here.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(store.items) { a in
                            Button { nav.openArtifact = a.id } label: { ArtifactTile(artifact: a) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Open in Browser") { NSWorkspace.shared.open(store.url(a)) }
                                    Button("Show in Finder") { Launcher.reveal(store.url(a).path) }
                                    Divider()
                                    Button("Delete", role: .destructive) { store.delete(a) }
                                }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func webButton(_ title: String, _ symbol: String, _ url: String) -> some View {
        Button {
            ClaudeWeb.shared.load(url)
            nav.tab = .web
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(ClaudeBrand.coral.opacity(0.14)))
                .foregroundStyle(ClaudeBrand.coralDeep)
        }
        .buttonStyle(.plain)
    }

    private func openLink() {
        var s = link.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        if !s.contains("://") { s = "https://" + s }
        ClaudeWeb.shared.load(s)
        nav.tab = .web
        link = ""
    }
}

private struct ArtifactTile: View {
    let artifact: LocalArtifact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [ClaudeBrand.coral.opacity(0.25), ClaudeBrand.coral.opacity(0.08)],
                                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: artifact.kind == "svg" ? "photo" : artifact.kind == "markdown" ? "doc.richtext" : "safari")
                    .font(.system(size: 26)).foregroundStyle(ClaudeBrand.coralDeep)
            }
            .frame(height: 86)
            Text(artifact.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text("\(artifact.kind.uppercased()) · \(Formatters.relative.localizedString(for: artifact.created, relativeTo: Date()))")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
    }
}

private struct ArtifactDetail: View {
    let artifact: LocalArtifact
    @ObservedObject private var store = ArtifactStore.shared
    @State private var title = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { ClaudeNav.shared.openArtifact = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).help("All artifacts")
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .onSubmit { store.rename(artifact, to: title) }
                Spacer()
                Button { NSWorkspace.shared.open(store.url(artifact)) } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless).help("Open in browser")
                Button {
                    if let s = try? String(contentsOf: store.url(artifact), encoding: .utf8) { Launcher.copy(s) }
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy source")
                Button { Launcher.reveal(store.url(artifact).path) } label: { Image(systemName: "folder") }
                    .buttonStyle(.borderless).help("Show in Finder")
                Button(role: .destructive) {
                    ClaudeNav.shared.openArtifact = nil
                    store.delete(artifact)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete")
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            Divider()
            FileWebView(url: store.url(artifact), readAccess: store.dir)
        }
        .onAppear { title = artifact.title }
        .onChange(of: artifact.id) { title = artifact.title }
    }
}

struct FileWebView: NSViewRepresentable {
    let url: URL
    let readAccess: URL

    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.loadFileURL(url, allowingReadAccessTo: readAccess)
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {
        if w.url?.standardizedFileURL != url.standardizedFileURL {
            w.loadFileURL(url, allowingReadAccessTo: readAccess)
        }
    }
}

// MARK: - claude.ai

/// One persistent web view so the claude.ai session and scroll state survive tab switches.
final class ClaudeWeb: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    static let shared = ClaudeWeb()

    let webView: WKWebView
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var loading = false
    @Published var url: URL?
    private var observers: [NSKeyValueObservation] = []
    private var popups: [NSWindow] = []
    private var loadedOnce = false

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        // Some sign-in pages refuse unknown embedded browsers; present as Safari.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observers = [
            webView.observe(\.canGoBack) { [weak self] w, _ in DispatchQueue.main.async { self?.canGoBack = w.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] w, _ in DispatchQueue.main.async { self?.canGoForward = w.canGoForward } },
            webView.observe(\.isLoading) { [weak self] w, _ in DispatchQueue.main.async { self?.loading = w.isLoading } },
            webView.observe(\.url) { [weak self] w, _ in DispatchQueue.main.async { self?.url = w.url } },
        ]
    }

    func loadHomeIfNeeded() {
        guard !loadedOnce else { return }
        load("https://claude.ai/new")
    }

    func load(_ s: String) {
        guard let u = URL(string: s) else { return }
        loadedOnce = true
        webView.load(URLRequest(url: u))
    }

    // Sign-in providers open popups; give them a real window so the login flow can complete.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 680), configuration: configuration)
        popup.customUserAgent = webView.customUserAgent
        popup.uiDelegate = self
        let win = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.contentView = popup
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.center()
        win.makeKeyAndOrderFront(nil)
        popups.append(win)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let w = popups.first(where: { $0.contentView === webView }) {
            w.close()
            popups.removeAll { $0 === w }
        }
    }

    // Links that leave Claude open in the default browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let u = action.request.url, let host = u.host,
           !(host.hasSuffix("claude.ai") || host.hasSuffix("anthropic.com") || host.hasSuffix("claudeusercontent.com")) {
            NSWorkspace.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

struct ClaudeWebView: View {
    @ObservedObject private var web = ClaudeWeb.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { web.webView.goBack() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).disabled(!web.canGoBack)
                Button { web.webView.goForward() } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).disabled(!web.canGoForward)
                Button {
                    if web.loading { web.webView.stopLoading() } else { web.webView.reload() }
                } label: {
                    Image(systemName: web.loading ? "xmark" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                Text(web.url?.absoluteString.replacingOccurrences(of: "https://", with: "") ?? "claude.ai")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                Menu {
                    Button("New Chat") { web.load("https://claude.ai/new") }
                    Button("Recent Chats") { web.load("https://claude.ai/recents") }
                    Button("Artifacts") { web.load("https://claude.ai/artifacts") }
                    Button("Claude Code Artifacts") { web.load("https://claude.ai/code/artifacts") }
                    Divider()
                    Button("Open in Browser") { if let u = web.url { NSWorkspace.shared.open(u) } }
                } label: { Image(systemName: "square.grid.2x2") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            Divider()
            WebViewHost(webView: web.webView)
        }
        .onAppear { web.loadHomeIfNeeded() }
    }
}

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
