import SwiftUI

private enum WeatherTab: String, CaseIterable, Hashable {
    case now = "NOW"
    case daily = "DAILY"
    case hourly = "HOURLY"
}

struct WeatherTileView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.vesperPalette) private var palette
    private var _tab = State<WeatherTab>(initialValue: .now)
    private var tab: WeatherTab {
        get { _tab.wrappedValue }
        nonmutating set { _tab.wrappedValue = newValue }
    }
    private var tabBinding: Binding<WeatherTab> { _tab.projectedValue }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader("Weather / \(state.settings.city)") {
                    PillSelector(
                        values: WeatherTab.allCases.map { ($0.rawValue, $0) },
                        selection: tabBinding
                    )
                }

                Spacer(minLength: 14)

                if let weather = state.weather {
                    Group {
                        switch tab {
                        case .now:
                            current(weather, size: proxy.size)
                        case .daily:
                            daily(weather)
                        case .hourly:
                            hourly(weather)
                        }
                    }
                    .transition(.opacity)
                } else {
                    waiting
                }
            }
            .padding(.horizontal, max(24, proxy.size.width * 0.035))
            .padding(.vertical, max(20, proxy.size.height * 0.055))
        }
        .background(palette.panel)
        .animation(.easeOut(duration: 0.2), value: tab)
    }

    private func current(_ weather: WeatherSnapshot, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(VFormat.temperature(weather.temperature))
                        .font(.system(size: min(92, size.height * 0.23), weight: .ultraLight, design: .rounded))
                        .foregroundStyle(palette.foreground)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    HStack(spacing: 9) {
                        Image(systemName: weather.symbol)
                            .font(.system(size: 21, weight: .light))
                            .foregroundStyle(palette.accent)
                        Text(weather.condition)
                            .font(.system(size: 20, weight: .regular, design: .rounded))
                            .foregroundStyle(palette.foreground)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    metric("Feels like", VFormat.temperature(weather.apparentTemperature))
                    metric("Humidity", "\(weather.humidity)%")
                    metric("Wind", "\(Int(weather.windSpeed.rounded())) km/h")
                    if let air = weather.airQuality {
                        metric("Air quality", "AQI \(air) · \(AirQualityLabel.text(air))")
                    }
                }
                .frame(width: min(290, size.width * 0.35))
            }

            Spacer(minLength: 18)

            HStack(spacing: 12) {
                Image(systemName: "umbrella")
                    .foregroundStyle(weather.precipitationChance >= 50 ? palette.accent : palette.dim)
                Text(weather.precipitationChance >= 50
                     ? "\(weather.precipitationChance)% chance of rain — keep an umbrella nearby"
                     : "\(weather.precipitationChance)% chance of rain today")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(weather.precipitationChance >= 50 ? palette.accent : palette.dim)
                Spacer()
                if let sunrise = weather.sunrise, let sunset = weather.sunset {
                    Image(systemName: "sunrise.fill")
                        .foregroundStyle(palette.dim)
                    Text("\(VFormat.eventTime(sunrise))  ·  \(VFormat.eventTime(sunset))")
                        .font(.vesperLabel(9))
                        .foregroundStyle(palette.dim)
                        .monospacedDigit()
                }
            }
            .padding(.top, 13)
            .overlay(alignment: .top) {
                Rectangle().fill(palette.line).frame(height: 1)
            }
        }
    }

    private func daily(_ weather: WeatherSnapshot) -> some View {
        VStack(spacing: 0) {
            ForEach(weather.days.prefix(5)) { day in
                HStack(spacing: 14) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.vesperLabel(10))
                        .foregroundStyle(palette.dim)
                        .frame(width: 46, alignment: .leading)
                    Image(systemName: WeatherCode.symbol(day.code, isDay: true))
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(palette.accent.opacity(0.9))
                        .frame(width: 24)
                    Text(WeatherCode.label(day.code))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(palette.foreground.opacity(0.85))
                    Spacer()
                    if day.precipitationChance > 0 {
                        Text("\(day.precipitationChance)%")
                            .font(.vesperLabel(9))
                            .foregroundStyle(palette.dim)
                            .frame(width: 38, alignment: .trailing)
                    }
                    Text(VFormat.temperature(day.high))
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.foreground)
                        .frame(width: 48, alignment: .trailing)
                    Text(VFormat.temperature(day.low))
                        .font(.system(size: 16, weight: .regular, design: .monospaced))
                        .foregroundStyle(palette.dim)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.line.opacity(0.7)).frame(height: 1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func hourly(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(weather.hours.prefix(10)) { hour in
                        VStack(spacing: 10) {
                            Text(hour.date.formatted(.dateTime.hour()))
                                .font(.vesperLabel(9))
                                .foregroundStyle(palette.dim)
                            Image(systemName: WeatherCode.symbol(hour.code, isDay: true))
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(palette.accent.opacity(0.9))
                                .frame(height: 24)
                            Text(VFormat.temperature(hour.temperature))
                                .font(.system(size: 18, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.foreground)
                            Text("\(hour.precipitationChance)%")
                                .font(.vesperLabel(8))
                                .foregroundStyle(hour.precipitationChance >= 50 ? palette.accent : palette.dim)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 17)
                        .background(RoundedRectangle(cornerRadius: 16).fill(palette.button.opacity(0.55)))
                    }
                }
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 0)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(palette.dim)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(palette.foreground.opacity(0.9))
                .monospacedDigit()
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.line.opacity(0.75)).frame(height: 1)
        }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: "cloud.sun")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(palette.dim)
            Text("Weather is loading")
                .font(.system(size: 22, weight: .light, design: .rounded))
                .foregroundStyle(palette.foreground)
            Text("Vesper fetches a local forecast from Open-Meteo. Check the location in Settings.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(palette.dim)
                .frame(maxWidth: 380, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }
}
