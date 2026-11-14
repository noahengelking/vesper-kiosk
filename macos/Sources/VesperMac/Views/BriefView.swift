import SwiftUI

struct MorningBriefView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.vesperPalette) private var palette

    var body: some View {
        ZStack {
            palette.background
            RadialGradient(
                colors: [palette.accent.opacity(0.14), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 900
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 9) {
                        Rectangle().fill(palette.accent).frame(width: 28, height: 1)
                        Text("MORNING BRIEF")
                            .vesperLabel(size: 11)
                            .tracking(3)
                            .foregroundStyle(palette.accent)
                    }
                    Spacer()
                    Button { state.mode = .dashboard } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.dim)
                            .frame(width: 36, height: 36)
                            .background(Circle().stroke(palette.line, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                }

                Spacer()

                Text(greeting)
                    .font(.system(size: 54, weight: .ultraLight, design: .rounded))
                    .foregroundStyle(palette.foreground)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.dim)
                    .padding(.top, 8)

                HStack(alignment: .top, spacing: 22) {
                    briefCard {
                        HStack(spacing: 18) {
                            Image(systemName: state.weather?.symbol ?? "cloud.sun.fill")
                                .font(.system(size: 39, weight: .ultraLight))
                                .foregroundStyle(palette.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(state.weather.map { VFormat.temperature($0.temperature) } ?? "—")
                                    .font(.system(size: 34, weight: .light, design: .rounded))
                                    .foregroundStyle(palette.foreground)
                                Text(state.weather?.condition ?? "Weather is loading")
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundStyle(palette.dim)
                            }
                        }
                    }

                    briefCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NEXT")
                                .vesperLabel(size: 9)
                                .foregroundStyle(palette.dim)
                            if let event = state.nextEvent {
                                Text(event.title)
                                    .font(.system(size: 20, weight: .regular, design: .rounded))
                                    .foregroundStyle(palette.foreground)
                                    .lineLimit(2)
                                Text(VFormat.relative(event.start))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(palette.accent)
                            } else {
                                Text("Nothing on the calendar")
                                    .font(.system(size: 17, weight: .regular, design: .rounded))
                                    .foregroundStyle(palette.foreground)
                                Text("A clear runway for a focus block.")
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(palette.dim)
                            }
                        }
                    }

                    briefCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TODAY'S TINY FACT")
                                .vesperLabel(size: 9)
                                .foregroundStyle(palette.dim)
                            Text(state.morningFact)
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundStyle(palette.foreground.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 40)

                HStack(spacing: 12) {
                    Button {
                        state.mode = .dashboard
                        state.startFocus()
                    } label: {
                        Text("Start \(state.settings.focusLength) min focus")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.background)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(palette.accent))
                    }
                    .buttonStyle(PressScaleStyle())

                    Button {
                        state.mode = .dashboard
                    } label: {
                        Text("Open dashboard")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.dim)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 13)
                            .background(Capsule().stroke(palette.line, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                }
                .padding(.top, 36)

                Spacer()
            }
            .padding(.horizontal, 70)
            .padding(.vertical, 52)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning."
        case 12..<18: return "Good afternoon."
        default: return "Good evening."
        }
    }

    private func briefCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20).fill(palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.line, lineWidth: 1))
    }
}
