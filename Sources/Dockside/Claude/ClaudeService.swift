import Foundation
import Security
import SwiftUI

// MARK: - API key (Keychain)

enum Keychain {
    private static let service = "app.dockside.mac.anthropic"
    private static let account = "api-key"

    static func get() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String) -> Bool {
        delete()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}

// MARK: - Models

enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"
    case fable = "claude-fable-5-1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opus: "Opus 5.5"
        case .sonnet: "Sonnet 5.5"
        case .haiku: "Haiku 5.5"
        case .fable: "Fable 5.1"
        }
    }

    var subtitle: String {
        switch self {
        case .opus: String(localized: "Default · capable and balanced")
        case .sonnet: String(localized: "Fast everyday model")
        case .haiku: String(localized: "Fastest, lowest cost")
        case .fable: String(localized: "Most capable · slower, pricier")
        }
    }

    /// Haiku has no server-side refusal fallback, so the parameter is left off for it.
    var supportsFallback: Bool { self != .haiku }

    static func displayName(for id: String) -> String {
        ClaudeModel(rawValue: id)?.title ?? id
    }
}

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: String                 // "user" or "assistant"
    var text = ""
    var thinking = ""
    /// The assistant's content blocks exactly as the API returned them; sent back unchanged on later turns.
    var content: Data?
    var model: String?
    var error: String?
    var note: String?
    var date = Date()
}

struct Conversation: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = "New chat"
    var messages: [ChatMessage] = []
    var updated = Date()
}

enum ClaudeError: LocalizedError {
    case noKey
    case http(Int, String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .noKey: "Add your Anthropic API key to chat."
        case .http(401, _): "Your API key was rejected. Update it in the Chat tab’s key settings."
        case .http(429, let m): "Rate limited — try again in a moment. \(m)"
        case .http(529, _): "Claude is overloaded right now. Try again shortly."
        case .http(let code, let m): "Request failed (\(code)). \(m)"
        case .api(let m): m
        }
    }
}

// MARK: - Chat

/// Streams conversations with the Claude Messages API over raw HTTP (Swift has no official SDK).
final class ClaudeChat: ObservableObject {
    static let shared = ClaudeChat()

    @Published var conversations: [Conversation] = []
    @Published var currentID: UUID?
    @Published var streaming = false
    @Published var hasKey = ClaudeChat.storedKey() != nil
    @Published var model: ClaudeModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: "claudeModel") }
    }

    private var task: Task<Void, Never>?
    private let file: URL

    static let systemPrompt = """
    You are Claude, chatting with the user through Dockside, a widget dock on their Mac. Keep answers concise and \
    well formatted in Markdown. When the user asks for something visual or interactive — a web page, app, game, \
    chart, diagram, SVG or a formatted document — reply with one complete, self-contained file in a single fenced \
    code block tagged html, svg or markdown. Dockside shows that block as a live artifact the user can open. Put all \
    CSS and JavaScript inline in HTML artifacts and load libraries only from cdnjs.cloudflare.com or cdn.jsdelivr.net.
    """

    private init() {
        model = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "claudeModel") ?? "") ?? .opus
        file = AppPaths.support.appendingPathComponent("claude-chats.json")
        if let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode([Conversation].self, from: d) {
            conversations = c
        }
        currentID = conversations.first?.id
    }

    var current: Conversation? { conversations.first { $0.id == currentID } }

    /// The Keychain key, or the standard ANTHROPIC_API_KEY environment variable when Dockside is launched with one.
    static func storedKey() -> String? {
        Keychain.get() ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Honors ANTHROPIC_BASE_URL (e.g. a proxy); defaults to the Claude API.
    static var baseURL: String {
        ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"].flatMap { $0.isEmpty ? nil : $0 } ?? "https://api.anthropic.com"
    }

    private func save() {
        let keep = conversations.filter { !$0.messages.isEmpty }.prefix(100)
        if let d = try? JSONEncoder().encode(Array(keep)) { try? d.write(to: file, options: .atomic) }
    }

    func setKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { Keychain.delete() } else { Keychain.set(k) }
        hasKey = Self.storedKey() != nil
    }

    func newChat() {
        stop()
        if let c = current, c.messages.isEmpty { return }
        let c = Conversation()
        conversations.insert(c, at: 0)
        currentID = c.id
    }

    func select(_ id: UUID) {
        stop()
        currentID = id
    }

    func delete(_ id: UUID) {
        if currentID == id { stop() }
        conversations.removeAll { $0.id == id }
        if currentID == id { currentID = conversations.first?.id }
        save()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func index(of id: UUID) -> Int? { conversations.firstIndex { $0.id == id } }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !streaming else { return }
        if currentID == nil || index(of: currentID!) == nil {
            let c = Conversation()
            conversations.insert(c, at: 0)
            currentID = c.id
        }
        guard let convID = currentID, let ci = index(of: convID) else { return }

        if conversations[ci].messages.isEmpty { conversations[ci].title = String(text.prefix(60)) }
        conversations[ci].messages.append(ChatMessage(role: "user", text: text))
        let reply = ChatMessage(role: "assistant", model: model.rawValue)
        conversations[ci].messages.append(reply)
        conversations[ci].updated = Date()
        // Most recent conversation first.
        let conv = conversations.remove(at: ci)
        conversations.insert(conv, at: 0)

        guard let key = Self.storedKey() else {
            update(convID, reply.id) { $0.error = ClaudeError.noKey.localizedDescription }
            return
        }

        let history = Self.apiMessages(conv.messages)
        let m = model
        streaming = true
        let replyID = reply.id
        task = Task { [weak self] in
            guard let self else { return }
            await self.stream(convID: convID, msgID: replyID, key: key, model: m, messages: history)
            await MainActor.run {
                self.streaming = false
                self.save()
            }
        }
    }

    /// Builds the request history: each answered user turn plus the assistant's original content blocks.
    /// Unanswered or failed turns are skipped so roles keep alternating.
    static func apiMessages(_ msgs: [ChatMessage]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var i = 0
        while i < msgs.count {
            let m = msgs[i]
            guard m.role == "user" else { i += 1; continue }
            let next = i + 1 < msgs.count ? msgs[i + 1] : nil
            let isPending = next?.role == "assistant" && next?.content == nil && next?.error == nil && next?.text.isEmpty == true
                && i + 2 >= msgs.count
            if let next, next.role == "assistant", let data = next.content,
               let blocks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                out.append(["role": "user", "content": m.text])
                out.append(["role": "assistant", "content": blocks])
            } else if isPending {
                out.append(["role": "user", "content": m.text])
            }
            i += 1
        }
        return out
    }

    private func update(_ convID: UUID, _ msgID: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let ci = index(of: convID), let mi = conversations[ci].messages.firstIndex(where: { $0.id == msgID }) else { return }
        change(&conversations[ci].messages[mi])
    }

    private func stream(convID: UUID, msgID: UUID, key: String, model: ClaudeModel, messages: [[String: Any]]) async {
        var req = URLRequest(url: URL(string: Self.baseURL + "/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 64000,
            "stream": true,
            "system": Self.systemPrompt,
            "thinking": ["type": "adaptive", "display": "summarized"],
            "output_config": ["effort": "medium"],
            "cache_control": ["type": "ephemeral"],
            "messages": messages,
        ]
        if model.supportsFallback {
            // On a policy decline, the API re-runs the request on Anthropic's recommended fallback model.
            body["fallbacks"] = "default"
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        var blocks: [Int: [String: Any]] = [:]
        var stopReason: String?
        var stopCategory: String?
        var served: String?
        var fallbackTo: String?
        var lastFlush = Date.distantPast

        func render() -> (String, String) {
            let ordered = blocks.keys.sorted().compactMap { blocks[$0] }
            let text = ordered.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            let thinking = ordered.filter { $0["type"] as? String == "thinking" }.compactMap { $0["thinking"] as? String }
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
            return (text, thinking)
        }

        func flush(force: Bool = false) async {
            guard force || Date().timeIntervalSince(lastFlush) > 0.05 else { return }
            lastFlush = Date()
            let (text, thinking) = render()
            await MainActor.run { self.update(convID, msgID) { $0.text = text; $0.thinking = thinking } }
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                var data = Data()
                for try await b in bytes { data.append(b) }
                throw ClaudeError.http(status, Self.errorMessage(data))
            }
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:"),
                      let d = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
                      let ev = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let type = ev["type"] as? String else { continue }
                switch type {
                case "message_start":
                    served = (ev["message"] as? [String: Any])?["model"] as? String
                case "content_block_start":
                    guard let i = ev["index"] as? Int, let block = ev["content_block"] as? [String: Any] else { break }
                    blocks[i] = block
                    if block["type"] as? String == "fallback" {
                        fallbackTo = (block["to"] as? [String: Any])?["model"] as? String
                    }
                case "content_block_delta":
                    guard let i = ev["index"] as? Int, let delta = ev["delta"] as? [String: Any], var block = blocks[i] else { break }
                    switch delta["type"] as? String {
                    case "text_delta": block["text"] = (block["text"] as? String ?? "") + (delta["text"] as? String ?? "")
                    case "thinking_delta": block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                    case "signature_delta": block["signature"] = delta["signature"]
                    default: break
                    }
                    blocks[i] = block
                    await flush()
                case "message_delta":
                    let delta = ev["delta"] as? [String: Any]
                    stopReason = delta?["stop_reason"] as? String ?? stopReason
                    let details = (delta?["stop_details"] ?? ev["stop_details"]) as? [String: Any]
                    stopCategory = details?["category"] as? String ?? stopCategory
                case "error":
                    let e = ev["error"] as? [String: Any]
                    throw ClaudeError.api(e?["message"] as? String ?? "The response stream failed.")
                default:
                    break
                }
            }
            await flush(force: true)
            let finalBlocks = Self.echoable(blocks.keys.sorted().compactMap { blocks[$0] })
            let reason = stopReason
            let category = stopCategory
            let servedModel = fallbackTo ?? served
            let fellBackTo = fallbackTo
            await MainActor.run {
                self.update(convID, msgID) { m in
                    m.model = servedModel ?? m.model
                    if reason == "refusal" {
                        // Nothing usable came back; keep it out of the history and let the user rephrase.
                        m.error = "Claude declined this request\(category.map { " (\($0))" } ?? "")."
                        return
                    }
                    m.content = try? JSONSerialization.data(withJSONObject: finalBlocks)
                    if reason == "max_tokens" { m.note = "Reached the length limit." }
                    if let f = fellBackTo { m.note = "Answered by \(ClaudeModel.displayName(for: f))." }
                }
                ArtifactStore.shared.capture(from: self.conversations.first { $0.id == convID }?.messages.first { $0.id == msgID }, chatID: convID)
            }
        } catch {
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            let message = error.localizedDescription
            await flush(force: true)
            await MainActor.run {
                self.update(convID, msgID) { m in
                    if cancelled { m.note = "Stopped." ; m.error = m.text.isEmpty ? "Stopped." : nil }
                    else { m.error = message }
                }
            }
        }
    }

    /// After a mid-output fallback, thinking and tool blocks before the last fallback marker aren't sent back.
    static func echoable(_ blocks: [[String: Any]]) -> [[String: Any]] {
        guard let last = blocks.lastIndex(where: { $0["type"] as? String == "fallback" }) else { return blocks }
        let drop: Set<String> = ["thinking", "redacted_thinking", "tool_use", "server_tool_use"]
        return blocks.enumerated().filter { i, b in i >= last || !drop.contains(b["type"] as? String ?? "") }.map(\.element)
    }

    private static func errorMessage(_ data: Data) -> String {
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = j["error"] as? [String: Any], let m = e["message"] as? String { return m }
        return String(data: data, encoding: .utf8)?.prefix(200).description ?? ""
    }
}

// MARK: - Local artifacts

struct LocalArtifact: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var kind: String          // html, svg, markdown
    var created = Date()
    var chatID: UUID?
    var sourceKey: String     // message id + block index, to avoid duplicates
    var file: String
}

/// Artifacts Claude produced in Dockside chats, saved as standalone HTML pages.
final class ArtifactStore: ObservableObject {
    static let shared = ArtifactStore()
    @Published var items: [LocalArtifact] = []

    let dir: URL
    private let index: URL

    private init() {
        dir = AppPaths.support.appendingPathComponent("Artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        index = dir.appendingPathComponent("index.json")
        if let d = try? Data(contentsOf: index), let i = try? JSONDecoder().decode([LocalArtifact].self, from: d) {
            items = i.filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.file).path) }
        }
    }

    func url(_ a: LocalArtifact) -> URL { dir.appendingPathComponent(a.file) }

    func artifact(forKey key: String) -> LocalArtifact? { items.first { $0.sourceKey == key } }

    private func persist() {
        if let d = try? JSONEncoder().encode(items) { try? d.write(to: index, options: .atomic) }
    }

    /// Saves every artifact-worthy code block in a finished assistant message.
    func capture(from message: ChatMessage?, chatID: UUID?) {
        guard let message, message.error == nil else { return }
        for (i, seg) in MarkdownSegments.parse(message.text).enumerated() {
            guard case .code(let lang, let body, true) = seg, let kind = Self.kind(lang), body.count > 40 else { continue }
            let key = "\(message.id.uuidString)-\(i)"
            guard artifact(forKey: key) == nil else { continue }
            let html = Self.page(kind: kind, source: body)
            let a = LocalArtifact(title: Self.title(kind: kind, source: body), kind: kind, chatID: chatID,
                                  sourceKey: key, file: "\(UUID().uuidString).html")
            try? html.write(to: url(a), atomically: true, encoding: .utf8)
            items.insert(a, at: 0)
        }
        persist()
    }

    func delete(_ a: LocalArtifact) {
        try? FileManager.default.removeItem(at: url(a))
        items.removeAll { $0.id == a.id }
        persist()
    }

    func rename(_ a: LocalArtifact, to title: String) {
        guard let i = items.firstIndex(of: a) else { return }
        items[i].title = title
        persist()
    }

    static func kind(_ lang: String) -> String? {
        switch lang.lowercased() {
        case "html", "htm": "html"
        case "svg": "svg"
        case "markdown", "md": "markdown"
        default: nil
        }
    }

    static func title(kind: String, source: String) -> String {
        if kind == "html", let r = source.range(of: #"<title>([^<]{1,80})</title>"#, options: [.regularExpression, .caseInsensitive]) {
            return String(source[r]).replacingOccurrences(of: #"</?title>"#, with: "", options: [.regularExpression, .caseInsensitive])
        }
        if kind == "markdown", let line = source.split(separator: "\n").first(where: { $0.hasPrefix("#") }) {
            return line.drop { $0 == "#" || $0 == " " }.prefix(80).description
        }
        return kind == "svg" ? "SVG graphic" : (kind == "markdown" ? "Document" : "Web page")
    }

    static func page(kind: String, source: String) -> String {
        switch kind {
        case "html":
            if source.range(of: "<html", options: .caseInsensitive) != nil { return source }
            return """
            <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>body{font-family:-apple-system,system-ui,sans-serif;margin:0}</style></head><body>
            \(source)
            </body></html>
            """
        case "svg":
            return """
            <!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;height:100%}
            body{display:grid;place-items:center;background:#fff}svg{max-width:100%;max-height:100vh}</style></head>
            <body>\(source)</body></html>
            """
        default:
            let escaped = source.replacingOccurrences(of: "</script", with: "<\\/script")
            return """
            <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
            <script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
            <style>
            :root{color-scheme:light dark}
            body{font:16px/1.6 -apple-system,system-ui,sans-serif;max-width:760px;margin:40px auto;padding:0 24px}
            pre{background:rgba(127,127,127,.12);padding:12px;border-radius:8px;overflow:auto}
            code{font-family:ui-monospace,Menlo,monospace;font-size:.9em}
            table{border-collapse:collapse}td,th{border:1px solid rgba(127,127,127,.3);padding:6px 10px}
            </style></head><body><article id="out"></article>
            <script type="text/markdown" id="md">\(escaped)</script>
            <script>
            var src=document.getElementById('md').textContent;
            document.getElementById('out').innerHTML=window.marked?marked.parse(src):'<pre>'+src.replace(/</g,'&lt;')+'</pre>';
            </script></body></html>
            """
        }
    }
}

// MARK: - Markdown segmentation

enum MarkdownSegments {
    enum Segment: Equatable {
        case text(String)
        case code(lang: String, body: String, closed: Bool)
    }

    /// Splits a reply into prose and fenced code blocks (an unclosed fence means the block is still streaming).
    static func parse(_ s: String) -> [Segment] {
        var out: [Segment] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        var lang: String?
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let l = lang {
                if trimmed.hasPrefix("```") {
                    out.append(.code(lang: l, body: code.joined(separator: "\n"), closed: true))
                    code = []
                    lang = nil
                } else {
                    code.append(line)
                }
            } else if trimmed.hasPrefix("```") {
                if !prose.isEmpty { out.append(.text(prose.joined(separator: "\n"))); prose = [] }
                lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else {
                prose.append(line)
            }
        }
        if let l = lang { out.append(.code(lang: l, body: code.joined(separator: "\n"), closed: false)) }
        if !prose.isEmpty { out.append(.text(prose.joined(separator: "\n"))) }
        return out
    }
}
