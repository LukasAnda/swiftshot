import SwiftUI

struct WelcomeView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.canvas.ignoresSafeArea()
                if geo.size.width > 700 && geo.size.height > geo.size.width {
                    // iPad portrait: a large hero, the pitch below it.
                    VStack(alignment: .leading, spacing: 0) {
                        AppMark()
                        Spacer()
                        StreakHero(k: 1.45).frame(maxWidth: .infinity)
                        Spacer()
                        VStack(alignment: .leading, spacing: Theme.Space.xxl) { pitch(titleSize: 48); actions.frame(maxWidth: 420) }
                            .frame(maxWidth: 600)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                    .padding(.horizontal, 72)
                    .padding(.vertical, Theme.Space.xl)
                } else if geo.size.width > 900 {
                    // iPad landscape: the pitch on the leading side, the hero beside it.
                    VStack(alignment: .leading, spacing: 0) {
                        AppMark()
                        Spacer()
                        HStack(spacing: 72) {
                            VStack(alignment: .leading, spacing: Theme.Space.xxl) { pitch(titleSize: 44); actions }
                                .frame(maxWidth: 440)
                            StreakHero(k: 1.3).frame(maxWidth: .infinity)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 72)
                    .padding(.vertical, Theme.Space.xl)
                    .frame(maxWidth: 1180)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        AppMark()
                        Spacer(minLength: Theme.Space.xl)
                        StreakHero()
                            .frame(maxWidth: .infinity)
                        Spacer(minLength: Theme.Space.xl)
                        pitch(titleSize: nil).padding(.bottom, Theme.Space.xl + 4)
                        actions
                    }
                    .padding(.horizontal, Theme.Space.xxl - 4)
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, Theme.Space.l)
                    .frame(maxWidth: 520)
                }
            }
        }
        .tint(Theme.accent)
    }

    private func pitch(titleSize: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("A steady rhythm for the things that matter.")
                .font(titleSize.map { .system(size: $0, weight: .bold) } ?? .system(.largeTitle, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Check in once a day, keep your streaks honest and see your week take shape.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.m) {
            Button { } label: {
                Text("Get started").font(.headline).frame(maxWidth: .infinity)
            }
            .primaryButton()
            Button { } label: {
                Text("I already have an account").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.vertical, Theme.Space.s)
        }
    }
}

/// The wordmark: a persimmon tile with a check, and the name.
struct AppMark: View {
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accent.gradient, in: .rect(cornerRadius: 8, style: .continuous))
            Text(verbatim: "Habits").font(.system(.title3, design: .rounded, weight: .bold))
        }
    }
}

/// A month-long streak as a stack of glass cards over warm light.
struct StreakHero: View {
    @Environment(\.colorScheme) private var scheme
    var k: CGFloat = 1

    var body: some View {
        ZStack {
            // The light the glass refracts.
            Circle()
                .fill(Theme.accent.opacity(scheme == .dark ? 0.75 : 0.85))
                .frame(width: 230 * k, height: 230 * k)
                .blur(radius: 50 * k)
                .offset(x: -50 * k, y: -30 * k)
            Circle()
                .fill(Color(red: 1.0, green: 0.70, blue: 0.35).opacity(scheme == .dark ? 0.55 : 0.75))
                .frame(width: 170 * k, height: 170 * k)
                .blur(radius: 45 * k)
                .offset(x: 90 * k, y: 70 * k)

            ZStack {
                StreakCard(k: k)
                Chip(icon: "trophy.fill", text: "Personal best", k: k)
                    .offset(x: 92 * k, y: -178 * k)
                Chip(icon: "drop.fill", text: "3 of 8 glasses", k: k)
                    .offset(x: -86 * k, y: 178 * k)
            }
        }
        .frame(height: 420 * k)
    }
}

private struct StreakCard: View {
    var k: CGFloat = 1
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "figure.run")
                    .font(.system(size: 15 * k, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32 * k, height: 32 * k)
                    .background(Theme.accent, in: .circle)
                Text("Morning run").font(k > 1 ? .title3.weight(.semibold) : .headline)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: 31.formatted())
                    .font(.system(size: 84 * k, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("days in a row").font((k > 1 ? Font.body : .subheadline).weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 6 * k) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 4) {
                        ZStack {
                            if i < 6 {
                                Circle().fill(Theme.accent)
                                Image(systemName: "checkmark").font(.system(size: 10 * k, weight: .heavy)).foregroundStyle(.white)
                            } else {
                                Circle().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                            }
                        }
                        .frame(width: 26 * k, height: 26 * k)
                        Text(verbatim: Theme.today.addingTimeInterval(-86_400 * Double(6 - i)).formatted(Date.FormatStyle.dateTime.weekday(.narrow).utc)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Theme.Space.xl * k)
        .frame(width: 290 * k, alignment: .leading)
        .glassSurface(in: .rect(cornerRadius: 34 * k, style: .continuous))
    }
}

private struct Chip: View {
    let icon: String
    let text: LocalizedStringKey
    var k: CGFloat = 1
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: icon).foregroundStyle(Theme.accent) }
            .font((k > 1 ? Font.subheadline : .footnote).weight(.semibold))
            .padding(.horizontal, 14 * k).padding(.vertical, 10 * k)
            .glassSurface(in: .capsule)
            .fixedSize()
    }
}

#Preview("Welcome") { WelcomeView() }
