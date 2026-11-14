import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let city = "vesper.city"
        static let latitude = "vesper.latitude"
        static let longitude = "vesper.longitude"
        static let zones = "vesper.clockZones"
        static let appearance = "vesper.appearance"
        static let secondHand = "vesper.secondHand"
        static let dayRibbon = "vesper.dayRibbon"
        static let lyricsOffset = "vesper.lyricsOffset"
        static let focusLength = "vesper.focusLength"
        static let selectedDisplay = "vesper.selectedDisplay"
        static let showBrief = "vesper.showMorningBrief"
    }

    @Published var city: String {
        didSet { defaults.set(city, forKey: Key.city) }
    }

    @Published var latitude: Double {
        didSet { defaults.set(latitude, forKey: Key.latitude) }
    }

    @Published var longitude: Double {
        didSet { defaults.set(longitude, forKey: Key.longitude) }
    }

    @Published var clockZones: [String] {
        didSet { defaults.set(clockZones, forKey: Key.zones) }
    }

    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    @Published var secondHand: SecondHandStyle {
        didSet { defaults.set(secondHand.rawValue, forKey: Key.secondHand) }
    }

    @Published var dayRibbon: Bool {
        didSet { defaults.set(dayRibbon, forKey: Key.dayRibbon) }
    }

    @Published var lyricsOffset: Double {
        didSet { defaults.set(lyricsOffset, forKey: Key.lyricsOffset) }
    }

    @Published var focusLength: Int {
        didSet { defaults.set(focusLength, forKey: Key.focusLength) }
    }

    @Published var selectedDisplayID: UInt32? {
        didSet { defaults.set(selectedDisplayID.map { Int($0) }, forKey: Key.selectedDisplay) }
    }

    @Published var showMorningBrief: Bool {
        didSet { defaults.set(showMorningBrief, forKey: Key.showBrief) }
    }

    private let defaults = UserDefaults.standard

    init() {
        city = defaults.string(forKey: Key.city) ?? "London"
        latitude = defaults.object(forKey: Key.latitude) as? Double ?? 51.5072
        longitude = defaults.object(forKey: Key.longitude) as? Double ?? -0.1276

        let localZone = TimeZone.current.identifier
        let defaultZones = ["Europe/Berlin", localZone, "Australia/Sydney"]
        var zones = (defaults.array(forKey: Key.zones) as? [String]) ?? defaultZones
        if zones.count != 3 { zones = defaultZones }
        if zones[1] == "GMT" || zones[1] == "Etc/GMT" { zones[1] = localZone }
        clockZones = zones

        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .auto
        secondHand = SecondHandStyle(rawValue: defaults.string(forKey: Key.secondHand) ?? "") ?? .smooth
        dayRibbon = defaults.object(forKey: Key.dayRibbon) as? Bool ?? false
        lyricsOffset = defaults.object(forKey: Key.lyricsOffset) as? Double ?? 0
        focusLength = defaults.object(forKey: Key.focusLength) as? Int ?? 25
        if let selected = defaults.object(forKey: Key.selectedDisplay) as? Int, selected > 0 {
            selectedDisplayID = UInt32(selected)
        } else {
            selectedDisplayID = nil
        }
        showMorningBrief = defaults.object(forKey: Key.showBrief) as? Bool ?? true
    }

    var centerZoneID: String { clockZones[1] }

    func resetDisplayDefaults() {
        city = "London"
        latitude = 51.5072
        longitude = -0.1276
        clockZones = ["Europe/Berlin", TimeZone.current.identifier, "Australia/Sydney"]
        appearance = .auto
        secondHand = .smooth
        dayRibbon = false
        lyricsOffset = 0
        focusLength = 25
    }
}
