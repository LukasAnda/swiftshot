import SwiftUI

/// The app's small design system: one accent (persimmon), warm neutrals, an 4 pt spacing grid,
/// SF Pro for text and SF Rounded for numbers. Liquid Glass on iOS 26+, materials before.
enum Theme {
    static let accent = Color("AccentColor")
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")

    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
    }
    enum Radius {
        static let card: CGFloat = 24, tile: CGFloat = 20, small: CGFloat = 12
    }

    /// Content never stretches wider than this on iPad; the rest becomes margin.
    static let readableWidth: CGFloat = 720

    /// The screenshots' fixed "today": Monday 21 September 2026, midday in UTC (so it is
    /// the same day in every time zone a simulator might be set to).
    static let today = Date(timeIntervalSince1970: 1_790_000_000)
    static var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
}

extension Font {
    /// Big figures (streaks, percentages): SF Rounded, tabular.
    static func figure(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

extension Date.FormatStyle {
    /// Date formats pinned to UTC, so the fixed dates read the same on every simulator.
    var utc: Date.FormatStyle {
        var s = self
        s.timeZone = TimeZone(identifier: "UTC")!
        return s
    }
}

// MARK: Liquid Glass with a material fallback

extension View {
    /// Liquid Glass on iOS 26+, a thin material with a hairline edge before.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .background(tint.map { AnyShapeStyle($0.opacity(0.35)) } ?? AnyShapeStyle(.clear), in: shape)
                .overlay(shape.stroke(.white.opacity(0.35), lineWidth: 0.5))
        }
    }

    /// The single prominent action of a screen.
    @ViewBuilder
    func primaryButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.extraLarge)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
        }
    }

    /// A quieter companion to `primaryButton()`.
    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.extraLarge)
        } else {
            buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
        }
    }

    /// Groups glass shapes so they share one sampling region (and blend when close).
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 12) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// A solid content card.
    func card(padding: CGFloat = Theme.Space.l, radius: CGFloat = Theme.Radius.card) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: radius, style: .continuous))
    }

    /// Small uppercase label above a group.
    func eyebrow() -> some View {
        font(.footnote.weight(.semibold)).textCase(.uppercase).kerning(0.6).foregroundStyle(.secondary)
    }
}

/// Warm canvas with a soft persimmon glow at the top: gives the glass something to refract.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    var height: CGFloat = 420
    var body: some View {
        ZStack(alignment: .top) {
            Theme.canvas
            LinearGradient(colors: [Theme.accent.opacity(scheme == .dark ? 0.32 : 0.22), Theme.accent.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: height)
            Ellipse()
                .fill(Color(red: 1.0, green: 0.72, blue: 0.40).opacity(scheme == .dark ? 0.14 : 0.30))
                .frame(width: 420, height: 260)
                .blur(radius: 70)
                .offset(x: 140, y: -60)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
    }
}

/// Progress ring in the accent colour; a filled check once complete.
struct ProgressRing: View {
    let progress: Double
    var size: CGFloat = 32
    var lineWidth: CGFloat = 4
    var body: some View {
        ZStack {
            if progress >= 1 {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
                Circle().trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Centres content and caps its width on wide screens (iPad, landscape).
struct Readable<Content: View>: View {
    var maxWidth: CGFloat = Theme.readableWidth
    @ViewBuilder var content: Content
    var body: some View {
        content.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }
}
