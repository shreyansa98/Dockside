import SwiftUI
import AppKit

enum DockMetrics {
    static let tile: CGFloat = 64
    static let radius: CGFloat = 17
    static let barPadding: CGFloat = 8
    static let spacing: CGFloat = 8
    static let barRadius: CGFloat = 25
}

struct Palette {
    var tile: Color
    var tileHover: Color
    var stroke: Color
    var primary: Color
    var secondary: Color
    var control: Color
    var track: Color
    var isDark: Bool

    static let dark = Palette(
        tile: Color(white: 1, opacity: 0.065), tileHover: Color(white: 1, opacity: 0.10),
        stroke: Color(white: 1, opacity: 0.075), primary: .white, secondary: Color(white: 1, opacity: 0.55),
        control: Color(white: 1, opacity: 0.12), track: Color(white: 1, opacity: 0.12), isDark: true)

    static let glass = Palette(
        tile: Color(white: 1, opacity: 0.12), tileHover: Color(white: 1, opacity: 0.18),
        stroke: Color(white: 1, opacity: 0.16), primary: .white, secondary: Color(white: 1, opacity: 0.72),
        control: Color(white: 1, opacity: 0.2), track: Color(white: 1, opacity: 0.2), isDark: true)

    static let light = Palette(
        tile: Color(white: 1, opacity: 0.62), tileHover: Color(white: 1, opacity: 0.85),
        stroke: Color(white: 0, opacity: 0.06), primary: Color(white: 0.08), secondary: Color(white: 0, opacity: 0.5),
        control: Color(white: 0, opacity: 0.07), track: Color(white: 0, opacity: 0.09), isDark: false)
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.dark }
private struct AccentKey: EnvironmentKey { static let defaultValue = AccentChoice.orange.color }

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    var dockAccent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

// MARK: - Visual effect

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var appearance: NSAppearance.Name?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.appearance = appearance.flatMap(NSAppearance.init(named:))
    }
}

// MARK: - Tiles

struct Tile<Content: View>: View {
    @Environment(\.palette) private var p
    var width: CGFloat? = nil
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DockMetrics.radius, style: .continuous)
        content()
            .padding(.horizontal, padding)
            .frame(width: width, height: DockMetrics.tile)
            .frame(minWidth: DockMetrics.tile)
            .background(shape.fill(p.tile))
            .overlay(shape.strokeBorder(p.stroke, lineWidth: 1))
            .contentShape(shape)
    }
}

/// A tile that opens a popover with the expanded widget when clicked.
struct PopoverTile<Label: View, Pop: View>: View {
    var width: CGFloat? = nil
    var padding: CGFloat = 12
    var popoverWidth: CGFloat = 300
    @ViewBuilder var label: () -> Label
    @ViewBuilder var popover: () -> Pop

    @State private var shown = false
    @ObservedObject private var store = Store.shared

    var body: some View {
        Tile(width: width, padding: padding, content: label)
            .onTapGesture {
                NSApp.activate(ignoringOtherApps: true)
                shown.toggle()
            }
            .popover(isPresented: $shown, arrowEdge: store.settings.position == .top ? .bottom : .top) {
                popover()
                    .frame(width: popoverWidth)
                    .padding(16)
                    .environment(\.dismissPopover, { shown = false })
            }
    }
}

private struct DismissPopoverKey: EnvironmentKey { static let defaultValue: () -> Void = {} }

extension EnvironmentValues {
    var dismissPopover: () -> Void {
        get { self[DismissPopoverKey.self] }
        set { self[DismissPopoverKey.self] = newValue }
    }
}

struct PopoverHeader<Trailing: View>: View {
    var title: String
    var symbol: String
    var tint: Color
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            Text(title).font(.system(size: 15, weight: .semibold))
            Spacer()
            trailing()
        }
        .padding(.bottom, 4)
    }
}

extension PopoverHeader where Trailing == EmptyView {
    init(title: String, symbol: String, tint: Color) {
        self.init(title: title, symbol: symbol, tint: tint) { EmptyView() }
    }
}

// MARK: - Buttons

struct CircleIconButton: View {
    @Environment(\.palette) private var p
    var symbol: String
    var size: CGFloat = 34
    var fill: Color? = nil
    var foreground: Color? = nil
    var help: String = ""
    var action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(foreground ?? p.primary)
                .frame(width: size, height: size)
                .background(Circle().fill(fill ?? p.control))
                .overlay(Circle().fill(Color.white.opacity(hover ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
        .help(help)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// A subtle full-width row button used inside popovers.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hover ? 0.07 : 0)))
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(Capsule().fill(tint.gradient))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Gauges

struct RingGauge: View {
    @Environment(\.palette) private var p
    var value: Double
    var color: Color
    var lineWidth: CGFloat = 5
    var openBottom = true

    var body: some View {
        let span = openBottom ? 0.75 : 1.0
        ZStack {
            Circle()
                .trim(from: 0, to: span)
                .stroke(p.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: span * min(max(value, 0), 1))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .animation(.spring(duration: 0.6), value: value)
        }
        .rotationEffect(.degrees(openBottom ? 135 : -90))
    }
}

struct BarProgress: View {
    @Environment(\.palette) private var p
    var value: Double
    var color: Color? = nil
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(p.track)
                Capsule().fill(color ?? p.primary.opacity(0.85))
                    .frame(width: max(height, g.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// App-icon style rounded square with an SF Symbol, used where we can't show a real app icon.
struct SymbolBadge: View {
    var symbol: String
    var colors: [Color]
    var size: CGFloat = 40
    var foreground: Color = .white

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension NSColor {
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
