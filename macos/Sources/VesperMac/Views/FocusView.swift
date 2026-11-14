import SwiftUI

struct FocusScreenView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.vesperPalette) private var palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, state.focusEndsAt?.timeIntervalSince(context.date) ?? 0)
            let total = max(1, state.focusTotal)
            let fraction = min(1, max(0, 1 - remaining / total))

            ZStack {
                palette.background
                RadialGradient(
                    colors: [palette.accent.opacity(0.12), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 700
                )

                VStack(spacing: 30) {
                    Spacer()
                    Text("FOCUS")
                        .vesperLabel(size: 12)
                        .tracking(5)
                        .foregroundStyle(palette.accent)

                    ZStack {
                        Circle()
                            .stroke(palette.line, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: fraction)
                            .stroke(palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: fraction)

                        VStack(spacing: 10) {
                            Text(timerString(remaining))
                                .font(.system(size: 92, weight: .ultraLight, design: .rounded))
                                .foregroundStyle(palette.foreground)
                                .monospacedDigit()
                            Text("\(Int(total / 60)) minute session")
                                .vesperLabel(size: 10)
                                .foregroundStyle(palette.dim)
                        }
                    }
                    .frame(width: 330, height: 330)

                    Text("Music keeps playing. Two-finger tap to pause, or press F to end the session.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(palette.dim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)

                    Button {
                        state.endFocus()
                    } label: {
                        Text("End focus")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.background)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(palette.foreground))
                    }
                    .buttonStyle(PressScaleStyle())
                    Spacer()
                }
            }
        }
    }

    private func timerString(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
