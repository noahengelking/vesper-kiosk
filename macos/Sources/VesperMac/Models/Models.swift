import Foundation
import AppKit

struct SpotifySnapshot: Equatable {
    var isRunning = false
    var isPlaying = false
    var title = ""
    var artist = ""
    var album = ""
    var duration: TimeInterval = 0
    var progress: TimeInterval = 0
    var volume: Int = 0
    var artworkURL: String?
    var trackID = ""
    var isShuffling = false
    var isRepeating = false
    var capturedAt = Date()

    static let stopped = SpotifySnapshot()

    var effectiveProgress: TimeInterval {
        guard isPlaying, duration > 0 else { return progress }
        return min(duration, progress + Date().timeIntervalSince(capturedAt))
    }

    var progressFraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, effectiveProgress / duration))
    }
}

struct WeatherSnapshot: Equatable {
    struct Hour: Equatable, Identifiable {
        let id = UUID()
        let date: Date
        let temperature: Double
        let precipitationChance: Int
        let code: Int
    }

    struct Day: Equatable, Identifiable {
        let id = UUID()
        let date: Date
        let high: Double
        let low: Double
        let precipitationChance: Int
        let code: Int
    }

    var city = ""
    var temperature = 0.0
    var apparentTemperature = 0.0
    var humidity = 0
    var windSpeed = 0.0
    var weatherCode = 0
    var isDay = true
    var precipitationChance = 0
    var airQuality: Int?
    var sunrise: Date?
    var sunset: Date?
    var hours: [Hour] = []
    var days: [Day] = []
    var updatedAt = Date()

    var condition: String { WeatherCode.label(weatherCode) }
    var symbol: String { WeatherCode.symbol(weatherCode, isDay: isDay) }
}

enum WeatherCode {
    static func label(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }

    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.min.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

struct CalendarEvent: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor

    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
}

struct LyricLine: Equatable, Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String
}

enum DashboardMode: String, CaseIterable, Equatable {
    case dashboard
    case lyrics
    case focus
    case brief
}

enum SecondHandStyle: String, CaseIterable, Identifiable {
    case smooth = "Smooth"
    case ticking = "Ticking"
    case hidden = "Hidden"

    var id: String { rawValue }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case dark = "Dark"
    case light = "Light"

    var id: String { rawValue }
}
