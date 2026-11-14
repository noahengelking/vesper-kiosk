import SwiftUI

struct ClockTileView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.vesperPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let big = min(width * 0.29, height * 0.47)
            let small = min(width * 0.155, height * 0.25)

            VStack(alignment: .leading, spacing: 0) {
                PanelHeader("Time / Magic Trackpad") {
                    HStack(spacing: 7) {
                        Image(systemName: "hand.draw")
                        Text("SWIPE TO SWITCH")
                    }
                    .font(.vesperLabel(9))
                    .tracking(1.8)
                    .foregroundStyle(palette.dim.opacity(0.8))
                }

                Spacer(minLength: 12)

                HStack(alignment: .center, spacing: 0) {
                    ZonedClockView(
                        zoneID: state.settings.clockZones[0],
                        size: small,
                        style: state.settings.secondHand,
                        emphasis: .side
                    )
                    .frame(maxWidth: .infinity)

                    ZonedClockView(
                        zoneID: state.settings.clockZones[1],
                        size: big,
                        style: state.settings.secondHand,
                        emphasis: .center
                    )
                    .frame(maxWidth: .infinity)

                    ZonedClockView(
                        zoneID: state.settings.clockZones[2],
                        size: small,
                        style: state.settings.secondHand,
                        emphasis: .side
                    )
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 18)

                VStack(spacing: 7) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(VFormat.day(context.date))
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(palette.dim)
                    }

                    Text(state.advice)
                        .font(.system(size: 13.5, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.accent)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, max(24, width * 0.035))
            .padding(.vertical, max(20, height * 0.055))
        }
        .background(palette.panel)
    }
}

private enum ClockEmphasis {
    case center
    case side
}

private struct ZonedClockView: View {
    @Environment(\.vesperPalette) private var palette
    let zoneID: String
    let size: CGFloat
    let style: SecondHandStyle
    let emphasis: ClockEmphasis

    private var zone: TimeZone { TimeZone(identifier: zoneID) ?? .current }

    var body: some View {
        VStack(spacing: emphasis == .center ? 10 : 8) {
            TimelineView(.animation(minimumInterval: style == .smooth ? 1.0 / 30.0 : 1.0)) { context in
                VStack(spacing: 10) {
                    AnalogClockFace(date: context.date, zone: zone, style: style, emphasis: emphasis)
                        .frame(width: size, height: size)

                    Text(VFormat.zoneName(zoneID))
                        .font(.vesperLabel(emphasis == .center ? 10 : 8.5))
                        .tracking(emphasis == .center ? 3.4 : 2.6)
                        .foregroundStyle(palette.dim)
                        .lineLimit(1)

                    Text(VFormat.clock(context.date, zone: zone))
                        .font(.system(
                            size: emphasis == .center ? 26 : 17,
                            weight: emphasis == .center ? .regular : .light,
                            design: .monospaced
                        ))
                        .foregroundStyle(emphasis == .center ? palette.foreground : palette.dim)
                        .monospacedDigit()

                    if emphasis == .center {
                        Text(VFormat.clock(context.date, zone: zone, seconds: true))
                            .font(.vesperLabel(9))
                            .tracking(2)
                            .foregroundStyle(palette.dim.opacity(0.6))
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

private struct AnalogClockFace: View {
    @Environment(\.vesperPalette) private var palette
    let date: Date
    let zone: TimeZone
    let style: SecondHandStyle
    let emphasis: ClockEmphasis

    var body: some View {
        Canvas { context, size in
            let diameter = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = diameter / 2 - 1.5
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
            let hour = Double(parts.hour ?? 0)
            let minute = Double(parts.minute ?? 0)
            let second = Double(parts.second ?? 0)
            let smoothSecond = style == .smooth
                ? second + Double(parts.nanosecond ?? 0) / 1_000_000_000
                : floor(second)

            let face = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            context.fill(face, with: .color(palette.background.opacity(emphasis == .center ? 0.48 : 0.32)))
            context.stroke(face, with: .color(palette.line.opacity(0.78)), lineWidth: 1)

            for tick in 0..<60 {
                let major = tick % 5 == 0
                let angle = CGFloat(tick) * .pi / 30 - .pi / 2
                let inner = radius * (major ? 0.78 : 0.855)
                let outer = radius * 0.925
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                context.stroke(
                    path,
                    with: .color(major ? palette.foreground.opacity(0.78) : palette.dim.opacity(0.38)),
                    style: StrokeStyle(lineWidth: major ? (emphasis == .center ? 1.8 : 1.2) : 0.75, lineCap: .round)
                )
            }

            let hourValue: Double = hour.truncatingRemainder(dividingBy: 12) + minute / 60.0
            let minuteValue: Double = minute + smoothSecond / 60.0
            let hourRadians: Double = hourValue * Double.pi / 6.0 - Double.pi / 2.0
            let minuteRadians: Double = minuteValue * Double.pi / 30.0 - Double.pi / 2.0
            let secondRadians: Double = smoothSecond * Double.pi / 30.0 - Double.pi / 2.0
            let hourAngle: CGFloat = CGFloat(hourRadians)
            let minuteAngle: CGFloat = CGFloat(minuteRadians)
            let secondAngle: CGFloat = CGFloat(secondRadians)

            drawHand(in: &context, center: center, angle: hourAngle, length: radius * 0.48, tail: radius * 0.08, width: emphasis == .center ? 3.0 : 2.1, color: palette.foreground)
            drawHand(in: &context, center: center, angle: minuteAngle, length: radius * 0.70, tail: radius * 0.11, width: emphasis == .center ? 2.1 : 1.5, color: palette.foreground)

            if style != .hidden {
                drawHand(in: &context, center: center, angle: secondAngle, length: radius * 0.76, tail: radius * 0.14, width: emphasis == .center ? 1.1 : 0.8, color: palette.accent)
            }

            let dotSize = emphasis == .center ? 7.0 : 5.0
            let dot = Path(ellipseIn: CGRect(
                x: center.x - dotSize / 2,
                y: center.y - dotSize / 2,
                width: dotSize,
                height: dotSize
            ))
            context.fill(dot, with: .color(palette.accent))
        }
        .drawingGroup()
    }

    private func drawHand(
        in context: inout GraphicsContext,
        center: CGPoint,
        angle: CGFloat,
        length: CGFloat,
        tail: CGFloat,
        width: CGFloat,
        color: Color
    ) {
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        var path = Path()
        path.move(to: CGPoint(x: center.x - direction.x * tail, y: center.y - direction.y * tail))
        path.addLine(to: CGPoint(x: center.x + direction.x * length, y: center.y + direction.y * length))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
