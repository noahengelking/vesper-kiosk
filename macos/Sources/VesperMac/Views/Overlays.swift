import SwiftUI
import AppKit

struct DayRibbonView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.vesperPalette) private var palette

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            GeometryReader { proxy in
                let labelWidth: CGFloat = 82
                let timelineWidth = max(1, proxy.size.width - labelWidth - 18)
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: context.date)
                let nowFraction = min(1, max(0, context.date.timeIntervalSince(startOfDay) / 86_400))
                let visibleEvents = state.events.filter {
                    !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: context.date)
                }

                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.panel)
                    Rectangle().fill(palette.line).frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)

                    Text("TODAY")
                        .vesperLabel(size: 9)
                        .foregroundStyle(palette.dim)
                        .frame(width: labelWidth, alignment: .leading)
                        .padding(.leading, 24)

                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(palette.line.opacity(0.55))
                            .frame(height: 1)

                        ForEach(visibleEvents) { event in
                            let start = event.start.timeIntervalSince(startOfDay) / 86_400
                            let end = event.end.timeIntervalSince(startOfDay) / 86_400
                            let x = timelineWidth * min(1, max(0, start))
                            let width = max(3, timelineWidth * max(0, end - start))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: event.color).opacity(0.65))
                                .frame(width: width, height: 9)
                                .offset(x: x)
                                .help(event.title)
                        }

                        Rectangle()
                            .fill(palette.accent)
                            .frame(width: 1.5, height: 24)
                            .offset(x: timelineWidth * nowFraction)

                        Circle()
                            .fill(palette.accent)
                            .frame(width: 7, height: 7)
                            .offset(x: timelineWidth * nowFraction - 2.75)
                    }
                    .frame(width: timelineWidth, height: 27)
                    .offset(x: labelWidth)

                    if visibleEvents.isEmpty {
                        Text("Nothing scheduled")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(palette.dim.opacity(0.6))
                            .offset(x: labelWidth + 10, y: -4)
                    }
                }
            }
        }
        .frame(height: 48)
    }
}

struct VolumePillView: View {
    @Environment(\.vesperPalette) private var palette
    let value: Int
    let onChange: (Int) -> Void

    private var _dragValue = State<Int?>(initialValue: nil)
    private var dragValue: Int? {
        get { _dragValue.wrappedValue }
        nonmutating set { _dragValue.wrappedValue = newValue }
    }

    private var displayed: Int { dragValue ?? value }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: displayed == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.foreground)
                .frame(width: 22)

            Text("SPOTIFY VOLUME")
                .vesperLabel(size: 9)
                .foregroundStyle(palette.dim)
                .fixedSize()

            GeometryReader { proxy in
                let fraction = CGFloat(displayed) / 100
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.line)
                        .frame(height: 5)
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: max(5, proxy.size.width * fraction), height: 5)
                    Circle()
                        .fill(palette.foreground)
                        .frame(width: 13, height: 13)
                        .offset(x: max(0, min(proxy.size.width - 13, proxy.size.width * fraction - 6.5)))
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let fraction = min(1, max(0, gesture.location.x / max(1, proxy.size.width)))
                            let next = Int((fraction * 100).rounded())
                            dragValue = next
                            onChange(next)
                        }
                        .onEnded { _ in
                            dragValue = nil
                        }
                )
            }
            .frame(height: 22)

            Text("\(displayed)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.foreground)
                .frame(width: 32, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 22)
        .frame(width: 640, height: 58)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(palette.background.opacity(palette.isDark ? 0.58 : 0.52)))
        .overlay(Capsule().stroke(palette.line.opacity(0.95), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
    }
}

struct GestureHintView: View {
    @Environment(\.vesperPalette) private var palette

    var body: some View {
        HStack(spacing: 18) {
            hint("hand.tap", "Two-finger tap", "play / pause")
            divider
            hint("arrow.left.and.right", "Swipe ← →", "switch view")
            divider
            hint("speaker.wave.2", "Right edge ↕", "volume")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private var divider: some View {
        Rectangle().fill(palette.line).frame(width: 1, height: 20)
    }

    private func hint(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.foreground)
                Text(subtitle)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.dim)
            }
        }
    }
}
