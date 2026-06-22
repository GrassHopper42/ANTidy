import AppKit
import SwiftUI

extension CleanupCategory {
    var accentColor: Color {
        switch self {
        case .developer: Color(red: 0.22, green: 0.56, blue: 0.92)
        case .caches: Color(red: 0.17, green: 0.68, blue: 0.56)
        case .system: Color(red: 0.64, green: 0.48, blue: 0.88)
        case .largeFiles: Color(red: 0.92, green: 0.48, blue: 0.34)
        case .orphans: Color(red: 0.88, green: 0.64, blue: 0.22)
        case .duplicates: Color(red: 0.29, green: 0.68, blue: 0.82)
        }
    }
}

extension CleanupRisk {
    var tint: Color {
        switch self {
        case .safe: Color(red: 0.15, green: 0.66, blue: 0.42)
        case .probablySafe: Color(red: 0.26, green: 0.55, blue: 0.88)
        case .verifyFirst: Color(red: 0.88, green: 0.57, blue: 0.18)
        case .blocked: Color(red: 0.86, green: 0.24, blue: 0.28)
        }
    }
}

struct LiquidGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(tint)
                        .interactive(interactive),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 24, y: 12)
        }
    }
}

struct LiquidGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

extension View {
    func liquidGlassPanel(cornerRadius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassPanelModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    func liquidGlassButton(prominent: Bool = false) -> some View {
        modifier(LiquidGlassButtonModifier(prominent: prominent))
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(red: 0.84, green: 0.92, blue: 0.96),
                    Color(red: 0.95, green: 0.90, blue: 0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.toolbarStyle = .unifiedCompact
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
