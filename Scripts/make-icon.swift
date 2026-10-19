// Renders the Dockside app icon to a 1024px PNG. Usage: swift make-icon.swift <out.png>
import SwiftUI
import AppKit

struct Icon: View {
    let size: CGFloat = 1024

    var body: some View {
        // macOS icon grid: 824pt artwork centered in a 1024 canvas.
        let art = size * 0.805
        ZStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.97, green: 0.96, blue: 0.9), Color(red: 0.66, green: 0.79, blue: 0.5), Color(red: 0.24, green: 0.44, blue: 0.26)],
                               startPoint: .top, endPoint: .bottom)
                // Rolling hills
                Ellipse().fill(Color(red: 0.42, green: 0.6, blue: 0.34).opacity(0.7))
                    .frame(width: art * 1.1, height: art * 0.5).offset(x: -art * 0.25, y: art * 0.28)
                Ellipse().fill(Color(red: 0.3, green: 0.5, blue: 0.28).opacity(0.75))
                    .frame(width: art * 1.0, height: art * 0.45).offset(x: art * 0.3, y: art * 0.34)

                HStack(spacing: art * 0.035) {
                    RoundedRectangle(cornerRadius: art * 0.045, style: .continuous).fill(Color.white.opacity(0.13))
                        .overlay(
                            VStack(spacing: 0) {
                                Text("10:42").font(.system(size: art * 0.085, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                Text("WED").font(.system(size: art * 0.035, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                            }
                        )
                        .frame(width: art * 0.3)
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.14), lineWidth: art * 0.022)
                        Circle().trim(from: 0, to: 0.68)
                            .stroke(Color(red: 0.25, green: 0.9, blue: 0.45), style: StrokeStyle(lineWidth: art * 0.022, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .padding(art * 0.03)
                    .frame(width: art * 0.17)
                    RoundedRectangle(cornerRadius: art * 0.035, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.45), Color(red: 1, green: 0.55, blue: 0.25)], startPoint: .top, endPoint: .bottom))
                        .overlay(Image(systemName: "music.note").font(.system(size: art * 0.07, weight: .bold)).foregroundStyle(.white))
                        .frame(width: art * 0.17)
                }
                .padding(art * 0.035)
                .frame(height: art * 0.25)
                .background(RoundedRectangle(cornerRadius: art * 0.075, style: .continuous).fill(Color.black.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: art * 0.075, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, art * 0.13)
                .padding(.horizontal, art * 0.08)
            }
            .frame(width: art, height: art)
            .clipShape(RoundedRectangle(cornerRadius: art * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 20, y: 12)
        }
        .frame(width: size, height: size)
    }
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
MainActor.assumeIsolated {
    let r = ImageRenderer(content: Icon())
    r.scale = 1
    guard let cg = r.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
