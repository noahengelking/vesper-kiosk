import Foundation

actor WeatherService {
    private let decoder = JSONDecoder()

    func fetch(latitude: Double, longitude: Double, city: String) async throws -> WeatherSnapshot {
        let forecast = try await fetchForecast(latitude: latitude, longitude: longitude)
        var snapshot = forecast
        snapshot.city = city
        snapshot.airQuality = try? await fetchAirQuality(latitude: latitude, longitude: longitude)
        return snapshot
    }

    private func fetchForecast(latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5")
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("VesperMac/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try decoder.decode(ForecastPayload.self, from: data )
        return payload.snapshot()
    }

    private func fetchAirQuality(latitude: Double, longitude: Double) async throws -> Int? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "us_aqi"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        struct AirPayload: Decodable {
            struct Current: Decodable { let us_aqi: Double? }
            let current: Current
        }
        return try decoder.decode(AirPayload.self, from: data).current.us_aqi.map { Int($0.rounded()) }
    }
}

private struct ForecastPayload: Decodable {
    struct Current: Decodable {
        let time: String
        let temperature_2m: Double
        let relative_humidity_2m: Int
        let apparent_temperature: Double
        let is_day: Int
        let precipitation: Double
        let weather_code: Int
        let wind_speed_10m: Double
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let precipitation_probability: [Int?]
        let weather_code: [Int]
    }

    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let sunrise: [String]
        let sunset: [String]
        let precipitation_probability_max: [Int?]
    }

    let current: Current
    let hourly: Hourly
    let daily: Daily

    func snapshot() -> WeatherSnapshot {
        let parser = WeatherDateParser()
        let now = parser.parse(current.time) ?? Date()
        var result = WeatherSnapshot()
        result.temperature = current.temperature_2m
        result.apparentTemperature = current.apparent_temperature
        result.humidity = current.relative_humidity_2m
        result.windSpeed = current.wind_speed_10m
        result.weatherCode = current.weather_code
        result.isDay = current.is_day == 1
        result.updatedAt = now

        let currentHour = Calendar.current.component(.hour, from: now)
        let start = max(0, min(hourly.time.count - 1, currentHour))
        for index in start..<min(hourly.time.count, start + 12) {
            guard let date = parser.parse(hourly.time[index]) else { continue }
            result.hours.append(.init(
                date: date,
                temperature: hourly.temperature_2m[index],
                precipitationChance: hourly.precipitation_probability[index] ?? 0,
                code: hourly.weather_code[index]
            ))
        }

        for index in 0..<daily.time.count {
            guard let date = parser.parse(daily.time[index]) else { continue }
            if index < 2, let chance = daily.precipitation_probability_max[index] {
                result.precipitationChance = chance
            }
            if index == 0 {
                result.sunrise = parser.parse(daily.sunrise[index])
                result.sunset = parser.parse(daily.sunset[index])
            }
            result.days.append(.init(
                date: date,
                high: daily.temperature_2m_max[index],
                low: daily.temperature_2m_min[index],
                precipitationChance: daily.precipitation_probability_max[index] ?? 0,
                code: daily.weather_code[index]
            ))
        }
        return result
    }
}

private final class WeatherDateParser {
    private let full: DateFormatter
    private let day: DateFormatter

    init() {
        full = DateFormatter()
        full.locale = Locale(identifier: "en_US_POSIX")
        full.timeZone = .current
        full.dateFormat = "yyyy-MM-dd'T'HH:mm"

        day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = .current
        day.dateFormat = "yyyy-MM-dd"
    }

    func parse(_ value: String) -> Date? {
        full.date(from: value) ?? day.date(from: value)
    }
}
