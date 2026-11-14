import SwiftUI

struct PanelHeader<Trailing: View>: View {
    @Environment(\.vesperPalette) private var palette
    let title: String
    let trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .vesperLabel(size: 11)
                .foregroundStyle(palette.dim)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

struct PillSelector<Value: Hashable>: View {
    @Environment(\.vesperPalette) private var palette
    let values: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selection = item.1 }
                } label: {
                    Text(item.0)
                        .vesperLabel(size: 10)
                        .foregroundStyle(selection == item.1 ? palette.background : palette.dim)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(selection == item.1 ? palette.foreground : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().stroke(palette.line, lineWidth: 1))
    }
}

struct CircleControl: View {
    @Environment(\.vesperPalette) private var palette
    let symbol: String
    var size: CGFloat = 56
    var active = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.33, weight: .medium))
                .foregroundStyle(active ? palette.accent : palette.foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(palette.button.opacity(0.82)))
                .overlay(Circle().stroke(palette.line.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct SmallPillButton: View {
    @Environment(\.vesperPalette) private var palette
    let title: String
    var symbol: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title).vesperLabel(size: 10)
            }
            .foregroundStyle(palette.dim)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().stroke(palette.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ToastView: View {
    @Environment(\.vesperPalette) private var palette
    let text: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.red.opacity(0.85) : palette.accent)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.foreground)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
    }
}

struct FadeMask: ViewModifier {
    func body(content: Content) -> some View {
        content.mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct AirQualityLabel {
    static func text(_ value: Int) -> String {
        switch value {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy"
        default: return "Poor"
        }
    }
}
