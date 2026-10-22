import SwiftUI

struct WelcomeView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                Text("Build habits that stick")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text("Small steps every day add up to big changes.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button {
                } label: {
                    Text("Get started")
                        .font(.headline)
                        .frame(maxWidth: 420)
                        .padding()
                        .background(.white, in: .capsule)
                        .foregroundStyle(.indigo)
                }
            }
            .padding(32)
        }
    }
}

#Preview("Welcome") { WelcomeView() }
