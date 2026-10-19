import SwiftUI

// MARK: - Emoji

struct EmojiWidget: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p
    @State private var copied: String?
    @State private var showAll = false

    var body: some View {
        Tile(padding: 10) {
            LazyHGrid(rows: [GridItem(.fixed(22), spacing: 2), GridItem(.fixed(22), spacing: 2)], spacing: 2) {
                ForEach(store.data.emojis.prefix(7), id: \.self) { e in
                    Text(e)
                        .font(.system(size: 17))
                        .frame(width: 24, height: 22)
                        .scaleEffect(copied == e ? 1.35 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture { copy(e) }
                        .help("Copy \(e)")
                }
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(p.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(p.control))
                    .contentShape(Circle())
                    .onTapGesture { NSApp.activate(ignoringOtherApps: true); showAll = true }
            }
        }
        .popover(isPresented: $showAll, arrowEdge: store.settings.position == .top ? .bottom : .top) {
            EmojiPicker { e in
                copy(e)
                var list = store.data.emojis.filter { $0 != e }
                list.insert(e, at: 0)
                store.data.emojis = Array(list.prefix(7))
            }
            .frame(width: 320)
            .padding(16)
        }
    }

    private func copy(_ e: String) {
        Launcher.copy(e)
        withAnimation(.spring(duration: 0.25, bounce: 0.6)) { copied = e }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation { copied = nil } }
    }
}

private struct EmojiPicker: View {
    var onPick: (String) -> Void

    static let groups: [(String, String)] = [
        ("Smileys", "😀😃😄😁😆😅😂🤣😊😇🙂😉😍🥰😘😋😛😜🤪🤨🧐🤓😎🥳😏😒😔😢😭😤😡🤯😳🥵🥶😱🤔🤫🙄😴🤤😷🤒🤠🤡👻💀👽🤖"),
        ("Gestures", "👍👎👌✌️🤞🤟🤘🤙👈👉👆👇☝️✋🖐️🖖👋🤝🙏👏🙌💪✍️🫶"),
        ("Hearts", "❤️🧡💛💚💙💜🖤🤍🤎💔❣️💕💞💓💗💖💘💝"),
        ("Objects", "🔥✨⭐️🌟💫⚡️☀️🌈❄️🎉🎊🎁🏆🥇🎯🚀💡💻📱⌚️📷🎧🎵📌📎✅❌⚠️💯🆗🆕"),
        ("Food", "☕️🍵🍺🍷🍕🍔🍟🌮🍣🍩🍪🎂🍎🍓🍉🥑🌶️🍿"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(title: "Emoji", symbol: "face.smiling", tint: .yellow) {
                Button("All Symbols…") { NSApp.orderFrontCharacterPalette(nil) }.buttonStyle(.borderless).font(.system(size: 12))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.groups, id: \.0) { g in
                        Text(g.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 9), spacing: 2) {
                            ForEach(Array(g.1).map(String.init), id: \.self) { e in
                                Button { onPick(e) } label: { Text(e).font(.system(size: 22)).frame(width: 32, height: 32) }
                                    .buttonStyle(RowButtonStyle())
                            }
                        }
                    }
                }
            }
            .frame(height: 300)
            Text("Click to copy · added to your Dock favorites").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Color picker

struct ColorPickerWidget: View {
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p
    @State private var copied: String?

    var body: some View {
        Tile(padding: 10) {
            HStack(spacing: 10) {
                CircleIconButton(symbol: "eyedropper", size: 40,
                                 fill: nil, help: "Pick a color from the screen") { sample() }
                LazyHGrid(rows: [GridItem(.fixed(20), spacing: 4), GridItem(.fixed(20), spacing: 4)], spacing: 4) {
                    ForEach(store.data.recentColors.prefix(4), id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                            .overlay {
                                if copied == hex { Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(.white) }
                            }
                            .frame(width: 20, height: 20)
                            .onTapGesture { copy(hex) }
                            .help("\(hex) — click to copy")
                    }
                }
            }
        }
        .contextMenu {
            ForEach(store.data.recentColors, id: \.self) { hex in Button("Copy \(hex)") { copy(hex) } }
            Divider()
            Button("Clear Colors") { store.data.recentColors.removeAll() }
        }
    }

    private func sample() {
        NSColorSampler().show { color in
            guard let color else { return }
            let hex = color.hexString
            var list = store.data.recentColors.filter { $0 != hex }
            list.insert(hex, at: 0)
            store.data.recentColors = Array(list.prefix(8))
            copy(hex)
        }
    }

    private func copy(_ hex: String) {
        Launcher.copy(hex)
        withAnimation { copied = hex }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { withAnimation { if copied == hex { copied = nil } } }
    }
}

// MARK: - Calculator & converter

enum Calc {
    static func evaluate(_ input: String) -> Double? {
        let s = input.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: ",", with: "").lowercased()
        var p = Parser(chars: Array(s))
        guard let v = p.expression(), p.atEnd, v.isFinite else { return nil }
        return v
    }

    static func format(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 8
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private struct Parser {
        var chars: [Character]
        var i = 0

        var atEnd: Bool {
            mutating get { skip(); return i >= chars.count }
        }

        mutating func skip() { while i < chars.count, chars[i] == " " { i += 1 } }

        mutating func eat(_ c: Character) -> Bool {
            skip()
            if i < chars.count, chars[i] == c { i += 1; return true }
            return false
        }

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while true {
                if eat("+") { guard let r = term() else { return nil }; v += r }
                else if eat("-") { guard let r = term() else { return nil }; v -= r }
                else { return v }
            }
        }

        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while true {
                if eat("*") { guard let r = power() else { return nil }; v *= r }
                else if eat("/") { guard let r = power() else { return nil }; v /= r }
                else if eat("%") {
                    // "50%" alone means 0.5; "a % b" is modulo.
                    let save = i
                    if let r = power() { v = v.truncatingRemainder(dividingBy: r) } else { i = save; v /= 100 }
                }
                else { return v }
            }
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if eat("^") { guard let e = power() else { return nil }; return pow(base, e) }
            return base
        }

        mutating func unary() -> Double? {
            if eat("-") { return unary().map { -$0 } }
            if eat("+") { return unary() }
            return primary()
        }

        mutating func primary() -> Double? {
            skip()
            if eat("(") {
                let v = expression()
                guard eat(")") else { return nil }
                return v
            }
            var s = ""
            while i < chars.count, chars[i].isNumber || chars[i] == "." { s.append(chars[i]); i += 1 }
            if !s.isEmpty { return Double(s) }
            var name = ""
            while i < chars.count, chars[i].isLetter { name.append(chars[i]); i += 1 }
            switch name {
            case "pi": return .pi
            case "e": return M_E
            case "sqrt", "sin", "cos", "tan", "log", "ln", "abs":
                guard eat("("), let v = expression(), eat(")") else { return nil }
                switch name {
                case "sqrt": return sqrt(v)
                case "sin": return sin(v)
                case "cos": return cos(v)
                case "tan": return tan(v)
                case "log": return log10(v)
                case "ln": return log(v)
                default: return abs(v)
                }
            default: return nil
            }
        }
    }
}

struct CalculatorWidget: View {
    @Environment(\.palette) private var p

    var body: some View {
        PopoverTile(width: DockMetrics.tile, padding: 0, popoverWidth: 320) {
            SymbolBadge(symbol: "plus.forwardslash.minus", colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 0.95, green: 0.45, blue: 0.1)], size: 42)
        } popover: {
            CalculatorPopover()
        }
    }
}

private struct CalculatorPopover: View {
    @State private var expr = ""
    @State private var history: [(String, String)] = []
    @State private var category = 0
    @State private var amount = "1"
    @State private var from = 0
    @State private var to = 1
    @FocusState private var focused: Bool

    static let units: [(String, [(String, Dimension)])] = [
        ("Length", [("m", UnitLength.meters), ("km", UnitLength.kilometers), ("cm", UnitLength.centimeters),
                    ("mm", UnitLength.millimeters), ("mi", UnitLength.miles), ("yd", UnitLength.yards),
                    ("ft", UnitLength.feet), ("in", UnitLength.inches)]),
        ("Weight", [("kg", UnitMass.kilograms), ("g", UnitMass.grams), ("lb", UnitMass.pounds), ("oz", UnitMass.ounces), ("st", UnitMass.stones)]),
        ("Temp", [("°C", UnitTemperature.celsius), ("°F", UnitTemperature.fahrenheit), ("K", UnitTemperature.kelvin)]),
        ("Speed", [("km/h", UnitSpeed.kilometersPerHour), ("mph", UnitSpeed.milesPerHour), ("m/s", UnitSpeed.metersPerSecond), ("kn", UnitSpeed.knots)]),
        ("Volume", [("L", UnitVolume.liters), ("mL", UnitVolume.milliliters), ("gal", UnitVolume.gallons), ("cup", UnitVolume.cups), ("fl oz", UnitVolume.fluidOunces)]),
        ("Data", [("MB", UnitInformationStorage.megabytes), ("GB", UnitInformationStorage.gigabytes), ("TB", UnitInformationStorage.terabytes),
                  ("KB", UnitInformationStorage.kilobytes), ("MiB", UnitInformationStorage.mebibytes), ("GiB", UnitInformationStorage.gibibytes)]),
    ]

    private var result: String? { Calc.evaluate(expr).map(Calc.format) }

    private var converted: String {
        let list = Self.units[category].1
        guard let v = Calc.evaluate(amount), list.indices.contains(from), list.indices.contains(to) else { return "—" }
        let m = Measurement(value: v, unit: list[from].1).converted(to: list[to].1)
        return Calc.format(m.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(title: "Calculator", symbol: "plus.forwardslash.minus", tint: .orange)
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(history.suffix(3).indices, id: \.self) { i in
                    let h = history.suffix(3)[i]
                    Text("\(h.0) = \(h.1)").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                }
                TextField("2 * (3 + 4) ^ 2", text: $expr)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onSubmit {
                        if let r = result { history.append((expr, r)); expr = r.replacingOccurrences(of: ",", with: "") }
                    }
                Text(result.map { "= \($0)" } ?? " ")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

            Divider()
            Text("Convert").font(.system(size: 13, weight: .semibold))
            Picker("", selection: $category) {
                ForEach(Self.units.indices, id: \.self) { Text(Self.units[$0].0).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: category) { from = 0; to = 1 }
            HStack {
                TextField("1", text: $amount).textFieldStyle(.roundedBorder).frame(width: 70)
                unitPicker($from)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                unitPicker($to)
            }
            HStack {
                Spacer()
                Text("\(converted) \(Self.units[category].1[safe: to]?.0 ?? "")")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .textSelection(.enabled)
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func unitPicker(_ sel: Binding<Int>) -> some View {
        Picker("", selection: sel) {
            ForEach(Self.units[category].1.indices, id: \.self) { Text(Self.units[category].1[$0].0).tag($0) }
        }
        .labelsHidden()
        .frame(width: 80)
    }
}

// MARK: - GitHub

struct GitHubWidget: View {
    @ObservedObject private var gh = GitHubService.shared
    @ObservedObject private var store = Store.shared
    @Environment(\.palette) private var p

    var body: some View {
        PopoverTile(width: 196, padding: 10, popoverWidth: 300) {
            HStack(spacing: 10) {
                Group {
                    if let a = gh.profile?.avatar {
                        AsyncImage(url: a) { $0.resizable() } placeholder: { Color.gray.opacity(0.3) }
                    } else {
                        SymbolBadge(symbol: "chevron.left.forwardslash.chevron.right", colors: [Color(white: 0.3), Color(white: 0.15)], size: 42)
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(gh.profile.map { "@\($0.login)" } ?? "GitHub").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary).lineLimit(1)
                    if let pr = gh.profile {
                        HStack(spacing: 8) {
                            Label("\(pr.followers)", systemImage: "person.2.fill")
                            Label("\(pr.repos)", systemImage: "book.closed.fill")
                        }
                        .labelStyle(CompactLabel())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(p.primary)
                    } else {
                        Text(store.settings.githubUser.isEmpty ? "Set username" : (gh.error ?? "Loading…"))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(p.primary)
                    }
                }
                Spacer(minLength: 0)
            }
        } popover: {
            GitHubPopover()
        }
        .onAppear { gh.load() }
        .onChange(of: store.settings.githubUser) { gh.load(force: true) }
    }
}

struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9)).opacity(0.6)
            configuration.title
        }
    }
}

private struct GitHubPopover: View {
    @ObservedObject private var gh = GitHubService.shared
    @ObservedObject private var store = Store.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PopoverHeader(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", tint: .gray) {
                Button { gh.load(force: true) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }
            TextField("GitHub username", text: $store.settings.githubUser).textFieldStyle(.roundedBorder)
            if let p = gh.profile {
                HStack {
                    stat("Followers", p.followers)
                    stat("Following", p.following)
                    stat("Repos", p.repos)
                }
                Text("Recently updated").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(gh.repos) { r in
                    Button { Launcher.open(url: r.url) } label: {
                        HStack {
                            Text(r.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer()
                            if let l = r.language { Text(l).font(.system(size: 10)).foregroundStyle(.secondary) }
                            Label("\(r.stars)", systemImage: "star.fill").labelStyle(CompactLabel()).font(.system(size: 11))
                        }
                    }.buttonStyle(RowButtonStyle())
                }
                Button("Open Profile") { Launcher.open(url: "https://github.com/\(p.login)") }.buttonStyle(PillButtonStyle(tint: .gray))
            }
        }
    }

    private func stat(_ t: String, _ v: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(v)").font(.system(size: 18, weight: .bold, design: .rounded))
            Text(t).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}
