import SwiftUI
import AppKit

struct CalendarTileView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var calendarService: CalendarService
    @Environment(\.vesperPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader("Calendar") {
                    HStack(spacing: 8) {
                        Button {
                            state.moveMonth(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 32, height: 32)
                                .background(Circle().stroke(palette.line, lineWidth: 1))
                        }
                        .buttonStyle(PressScaleStyle())

                        Button {
                            state.selectToday()
                        } label: {
                            Text("TODAY")
                                .vesperLabel(size: 9)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Capsule().stroke(palette.line, lineWidth: 1))
                        }
                        .buttonStyle(PressScaleStyle())

                        Button {
                            state.moveMonth(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 32, height: 32)
                                .background(Circle().stroke(palette.line, lineWidth: 1))
                        }
                        .buttonStyle(PressScaleStyle())
                    }
                    .foregroundStyle(palette.dim)
                }

                Spacer(minLength: 18)

                HStack(alignment: .top, spacing: max(18, proxy.size.width * 0.025)) {
                    MonthGrid(
                        month: state.monthAnchor,
                        selectedDate: state.selectedCalendarDate,
                        events: state.events,
                        onSelect: { date in state.selectedCalendarDate = date }
                    )
                    .frame(width: proxy.size.width * 0.52)

                    Rectangle()
                        .fill(palette.line)
                        .frame(width: 1)
                        .padding(.vertical, 3)

                    AgendaView(date: state.selectedCalendarDate, events: state.events(on: state.selectedCalendarDate))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)

                if !calendarService.hasAccess {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(palette.accent)
                        Text("Connect Calendar to see your real events")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.dim)
                        Spacer()
                        Button("Connect") { state.requestCalendarAccess() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.accent)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, max(24, proxy.size.width * 0.035))
            .padding(.vertical, max(20, proxy.size.height * 0.055))
        }
        .background(palette.panel)
    }
}

private struct MonthGrid: View {
    @Environment(\.vesperPalette) private var palette
    let month: Date
    let selectedDate: Date
    let events: [CalendarEvent]
    let onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private var calendar: Calendar { .current }
    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: month)?.start ?? month
    }
    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: month)?.count ?? 30
    }
    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday + 5) % 7
    }

    var body: some View {
        VStack(spacing: 11) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 21, weight: .regular, design: .rounded))
                .foregroundStyle(palette.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                    Text(day)
                        .font(.vesperLabel(8))
                        .foregroundStyle(palette.dim.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }

                ForEach(0..<leadingBlanks, id: \.self) { _ in
                    Color.clear.frame(height: 30)
                }

                ForEach(1...daysInMonth, id: \.self) { day in
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                        dayCell(date)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(date)
        let hasEvents = events.contains { calendar.isDate($0.start, inSameDayAs: date) }

        return Button {
            onSelect(date)
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(selected ? palette.background : (today ? palette.accent : palette.foreground.opacity(0.84)))
                    .frame(width: 28, height: 26)
                    .background {
                        if selected {
                            Circle().fill(palette.foreground)
                        } else if today {
                            Circle().stroke(palette.accent, lineWidth: 1)
                        }
                    }

                Circle()
                    .fill(palette.accent)
                    .frame(width: 3, height: 3)
                    .opacity(hasEvents ? 0.9 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AgendaView: View {
    @Environment(\.vesperPalette) private var palette
    let date: Date
    let events: [CalendarEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(VFormat.day(date))
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(palette.foreground)

            if events.isEmpty {
                Text("Nothing planned")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.dim)
                    .padding(.top, 2)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 11) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(nsColor: event.color))
                                    .frame(width: 3)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.title)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(palette.foreground)
                                        .lineLimit(2)
                                    Text(event.isAllDay ? "All day" : "\(VFormat.eventTime(event.start)) – \(VFormat.eventTime(event.end))")
                                        .font(.vesperLabel(9))
                                        .foregroundStyle(palette.dim)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.trailing, 8)
                }
                .scrollIndicators(.hidden)
            }

            Spacer(minLength: 0)
        }
    }
}
