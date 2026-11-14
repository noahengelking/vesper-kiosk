import Foundation
import SwiftUI
import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    struct VolumeHUD: Equatable, Identifiable {
        let id = UUID()
        let value: Int
    }

    enum ToastKind {
        case info
        case error
    }

    let settings: AppSettings
    let calendarService: CalendarService

    @Published private(set) var spotify = SpotifySnapshot.stopped
    @Published private(set) var artwork: NSImage?
    @Published private(set) var ambientColors: [Color] = [
        Color(hex: 0x30251A),
        Color(hex: 0x15110D)
    ]
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var lyricsResult = LyricsResult(synced: false, lines: [])
    @Published private(set) var lyricsLoading = false
    @Published private(set) var lyricsError: String?
    @Published var mode: DashboardMode = .dashboard
    @Published var selectedCalendarDate = Date()
    @Published var monthAnchor = Date()
    @Published var focusEndsAt: Date?
    @Published var focusStartedAt: Date?
    @Published var focusTotal: TimeInterval = 0
    @Published var sleepEndsAt: Date?
    @Published private(set) var volumeHUD: VolumeHUD?
    @Published private(set) var toast: (text: String, kind: ToastKind)?
    @Published private(set) var dashboardActive = false
    @Published private(set) var gestureHintVisible = false

    private let spotifyService = SpotifyService()
    private let weatherService = WeatherService()
    private let lyricsService = LyricsService()
    private var spotifyLoop: Task<Void, Never>?
    private var weatherLoop: Task<Void, Never>?
    private var calendarLoop: Task<Void, Never>?
    private var volumeTask: Task<Void, Never>?
    private var volumeHideTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var lastArtworkURL: String?
    private var lastLyricsKey = ""
    private var started = false
    private var gestureHintShown = false
    private var targetVolume = 50
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, calendarService: CalendarService) {
        self.settings = settings
        self.calendarService = calendarService

        settings.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { self.objectWillChange.send() }
            }
            .store(in: &cancellables)

        settings.$city
            .combineLatest(settings.$latitude, settings.$longitude)
            .dropFirst()
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                Task { @MainActor in await self?.refreshWeather() }
            }
            .store(in: &cancellables)

        calendarService.$hasAccess
            .dropFirst()
            .sink { [weak self] granted in
                guard granted else { return }
                Task { @MainActor in self?.reloadCalendar() }
            }
            .store(in: &cancellables)
    }

    var palette: VesperPalette {
        switch settings.appearance {
        case .dark:
            return .dark
        case .light:
            return .light
        case .auto:
            return isDaylight ? .light : .dark
        }
    }

    var isDaylight: Bool {
        if let weather, Date().timeIntervalSince(weather.updatedAt) < 3600 {
            return weather.isDay
        }
        let hour = Calendar.current.component(.hour, from: Date())
        return (7..<19).contains(hour)
    }

    var centerTimeZone: TimeZone {
        TimeZone(identifier: settings.clockZones[1]) ?? .current
    }

    var nextEvent: CalendarEvent? {
        let now = Date()
        return events
            .filter { !$0.isAllDay && $0.end > now }
            .min { $0.start < $1.start }
    }

    var now: Date { Date() }

    var advice: String {
        if let focusEndsAt {
            return "Focus in progress — \(durationString(focusEndsAt.timeIntervalSinceNow)) remaining."
        }
        if let sleepEndsAt {
            return "Sleep timer set — Spotify fades out in \(durationString(sleepEndsAt.timeIntervalSinceNow))."
        }
        if let event = nextEvent {
            let minutes = max(0, Int(event.start.timeIntervalSinceNow / 60))
            if minutes <= 120 {
                return "Next: \(event.title) in \(durationString(TimeInterval(minutes * 60)))."
            }
        }
        if let weather, weather.precipitationChance >= 50 {
            return "Rain is likely — keep an umbrella nearby."
        }
        return "All clear. Use the menu bar or a two-finger tap to start something."
    }

    var morningFact: String {
        Self.funFacts[(Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0) % Self.funFacts.count]
    }

    func setDashboardActive(_ active: Bool) {
        guard dashboardActive != active else { return }
        dashboardActive = active
        if active {
            start()
        } else {
            stopLoops()
        }
    }

    private func start() {
        if !started {
            started = true
            Task { [weak self] in
                guard let self else { return }
                await self.refreshSpotify()
                await self.refreshWeather()
            }
            reloadCalendar()
            showGestureHintIfNeeded()
            if settings.showMorningBrief,
               Calendar.current.component(.hour, from: Date()) < 12,
               !hasShownBriefToday() {
                mode = .brief
                markBriefShown()
            }
        }
        startSpotifyLoop()
        startWeatherLoop()
        startCalendarLoop()
    }

    private func startSpotifyLoop() {
        spotifyLoop?.cancel()
        spotifyLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSpotify()
                try? await Task.sleep(for: .seconds(2.0))
            }
        }
    }

    private func startWeatherLoop() {
        guard weatherLoop == nil else { return }
        weatherLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshWeather()
                try? await Task.sleep(for: .seconds(900))
            }
        }
    }

    private func startCalendarLoop() {
        guard calendarLoop == nil else { return }
        calendarLoop = Task { [weak self] in
            while !Task.isCancelled {
                self?.reloadCalendar()
                try? await Task.sleep(for: .seconds(180))
            }
        }
    }

    private func stopLoops() {
        spotifyLoop?.cancel(); spotifyLoop = nil
        weatherLoop?.cancel(); weatherLoop = nil
        calendarLoop?.cancel(); calendarLoop = nil
        artworkTask?.cancel(); artworkTask = nil
        lyricsTask?.cancel(); lyricsTask = nil
    }

    func refreshSpotify() async {
        let snapshot = await spotifyService.readSnapshot()
        spotify = snapshot
        targetVolume = snapshot.volume

        if let url = snapshot.artworkURL, url != lastArtworkURL {
            lastArtworkURL = url
            loadArtwork(from: url)
        }

        if !snapshot.isRunning || snapshot.title.isEmpty {
            artwork = nil
            lastArtworkURL = nil
        }

        if mode == .lyrics, !snapshot.title.isEmpty, !lyricsLoading {
            let key = lyricsKey(for: snapshot)
            if key != lastLyricsKey { loadLyrics(force: true) }
        }
    }

    func refreshWeather() async {
        do {
            let result = try await weatherService.fetch(
                latitude: settings.latitude,
                longitude: settings.longitude,
                city: settings.city
            )
            guard dashboardActive else { return }
            weather = result
        } catch {
            // Keep the last good observation. The dashboard never blocks on weather.
        }
    }

    func reloadCalendar() {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: monthAnchor)?.start ?? Date()
        let start = calendar.date(byAdding: .day, value: -10, to: monthStart) ?? monthStart
        let end = calendar.date(byAdding: .day, value: 50, to: monthStart) ?? monthStart
        events = calendarService.fetchEvents(from: start, to: end)
    }

    func requestCalendarAccess() {
        Task {
            let granted = await calendarService.requestAccess()
            if granted {
                reloadCalendar()
                showToast("Calendar connected")
            } else {
                showToast("Calendar access was not granted", kind: .error)
            }
        }
    }

    func moveMonth(by value: Int) {
        guard let date = Calendar.current.date(byAdding: .month, value: value, to: monthAnchor) else { return }
        monthAnchor = date
        selectedCalendarDate = date
        reloadCalendar()
    }

    func selectToday() {
        monthAnchor = Date()
        selectedCalendarDate = Date()
        reloadCalendar()
    }

    func events(on day: Date) -> [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) || ($0.start < day && $0.end > day) }
    }

    func togglePlayPause() {
        guard spotify.isRunning else {
            Task { await spotifyService.openSpotify() }
            return
        }
        spotify.progress = spotify.effectiveProgress
        spotify.capturedAt = Date()
        spotify.isPlaying.toggle()
        Task {
            await spotifyService.playPause()
            try? await Task.sleep(for: .milliseconds(280))
            await refreshSpotify()
        }
    }

    func nextTrack() {
        Task {
            await spotifyService.nextTrack()
            try? await Task.sleep(for: .milliseconds(320))
            await refreshSpotify()
        }
    }

    func previousTrack() {
        Task {
            await spotifyService.previousTrack()
            try? await Task.sleep(for: .milliseconds(320))
            await refreshSpotify()
        }
    }

    func seek(toFraction fraction: Double) {
        guard spotify.duration > 0 else { return }
        let clamped = min(1, max(0, fraction))
        spotify.progress = spotify.duration * clamped
        spotify.capturedAt = Date()
        Task { await spotifyService.seek(to: spotify.duration * clamped) }
    }

    func toggleShuffle() {
        spotify.isShuffling.toggle()
        let enabled = spotify.isShuffling
        Task { await spotifyService.setShuffling(enabled) }
    }

    func toggleRepeat() {
        spotify.isRepeating.toggle()
        let enabled = spotify.isRepeating
        Task { await spotifyService.setRepeating(enabled) }
    }

    func openLyrics() {
        guard spotify.isRunning, !spotify.title.isEmpty else {
            showToast("Start Spotify before opening lyrics", kind: .error)
            return
        }
        mode = .lyrics
        loadLyrics(force: false)
    }

    func closeLyrics() {
        mode = .dashboard
    }

    func loadLyrics(force: Bool) {
        guard spotify.isRunning, !spotify.title.isEmpty else { return }
        let key = lyricsKey(for: spotify)
        guard force || key != lastLyricsKey || lyricsResult.lines.isEmpty else { return }
        lastLyricsKey = key
        lyricsTask?.cancel()
        lyricsLoading = true
        lyricsError = nil
        lyricsResult = LyricsResult(synced: false, lines: [])

        let title = spotify.title
        let artist = spotify.artist
        let album = spotify.album
        let duration = spotify.duration
        lyricsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await lyricsService.fetch(title: title, artist: artist, album: album, duration: duration)
                guard !Task.isCancelled else { return }
                self.lyricsResult = result
                self.lyricsLoading = false
                if result.instrumental {
                    self.lyricsError = "This track is instrumental."
                } else if result.lines.isEmpty {
                    self.lyricsError = "No synced lyrics found for this track."
                }
            } catch let error as LyricsServiceError {
                guard !Task.isCancelled else { return }
                self.lyricsLoading = false
                self.lyricsError = error.errorDescription
            } catch {
                guard !Task.isCancelled else { return }
                self.lyricsLoading = false
                self.lyricsError = "Could not load lyrics. Check your connection."
            }
        }
    }

    func currentLyricIndex(at progress: TimeInterval) -> Int? {
        guard lyricsResult.synced, !lyricsResult.lines.isEmpty else { return nil }
        let adjusted = progress + settings.lyricsOffset
        var index: Int?
        for (i, line) in lyricsResult.lines.enumerated() {
            if line.time <= adjusted { index = i } else { break }
        }
        return index ?? 0
    }

    func adjustVolume(by delta: Int) {
        guard spotify.isRunning else { return }
        targetVolume = min(100, max(0, targetVolume + delta))
        spotify.volume = targetVolume
        volumeHUD = VolumeHUD(value: targetVolume)
        volumeHideTask?.cancel()
        volumeHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.volumeHUD = nil
        }
        volumeTask?.cancel()
        let value = targetVolume
        volumeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(45))
            guard !Task.isCancelled else { return }
            await self?.spotifyService.setVolume(value)
        }
    }

    func setVolume(_ value: Int) {
        let clamped = min(100, max(0, value))
        let delta = clamped - targetVolume
        if delta != 0 { adjustVolume(by: delta) }
    }

    func showVolume() {
        guard spotify.isRunning else { return }
        volumeHUD = VolumeHUD(value: spotify.volume)
        volumeHideTask?.cancel()
        volumeHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.volumeHUD = nil
        }
    }

    func startFocus(minutes: Int? = nil) {
        let length = minutes ?? settings.focusLength
        focusStartedAt = Date()
        focusTotal = TimeInterval(length * 60)
        focusEndsAt = focusStartedAt!.addingTimeInterval(focusTotal)
        mode = .focus
        focusTask?.cancel()
        focusTask = Task { [weak self] in
            guard let self else { return }
            let seconds = TimeInterval(length * 60)
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self.focusEndsAt = nil
            self.focusStartedAt = nil
            self.mode = .dashboard
            self.showToast("Focus session complete")
        }
    }

    func endFocus() {
        focusTask?.cancel()
        focusTask = nil
        focusEndsAt = nil
        focusStartedAt = nil
        if mode == .focus { mode = .dashboard }
    }

    func startSleep(minutes: Int) {
        sleepEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTask?.cancel()
        sleepTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            await self.fadeOutAndPause()
            self.sleepEndsAt = nil
            self.showToast("Sleep timer finished — Spotify paused")
        }
    }

    func cancelSleep() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepEndsAt = nil
    }

    private func fadeOutAndPause() async {
        let fresh = await spotifyService.readSnapshot()
        guard fresh.isPlaying else { return }
        spotify = fresh
        let start = fresh.volume
        for value in stride(from: start, through: 4, by: -8) {
            await spotifyService.setVolume(value)
            spotify.volume = value
            try? await Task.sleep(for: .milliseconds(500))
        }
        await spotifyService.playPause()
        await spotifyService.setVolume(start)
        spotify.volume = start
        spotify.isPlaying = false
    }

    func toggleDayRibbon() {
        settings.dayRibbon.toggle()
    }

    func navigate(_ direction: Int) {
        if mode == .lyrics {
            if direction > 0 { mode = .dashboard } else { openLyrics() }
        } else {
            mode = direction > 0 ? .lyrics : .dashboard
        }
    }

    func showToast(_ text: String, kind: ToastKind = .info) {
        toast = (text, kind)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func showGestureHintIfNeeded() {
        guard !gestureHintShown else { return }
        gestureHintShown = true
        gestureHintVisible = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            withAnimation(.easeOut(duration: 0.5)) { self?.gestureHintVisible = false }
        }
    }

    private func loadArtwork(from urlString: String) {
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            guard let url = URL(string: urlString) else { return }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 12
                let (data, _) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, let image = NSImage(data: data) else { return }
                let colors = ImageColors.analyze(image)
                await MainActor.run {
                    guard self?.lastArtworkURL == urlString else { return }
                    self?.artwork = image
                    self?.ambientColors = colors
                }
            } catch {
                // Artwork is decorative. Keep the fallback ambience.
            }
        }
    }

    private func lyricsKey(for snapshot: SpotifySnapshot) -> String {
        "\(snapshot.title)|\(snapshot.artist)|\(snapshot.album)|\(Int(snapshot.duration))"
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        let minutes = value / 60
        let secs = value % 60
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m \(secs)s"
    }

    private func hasShownBriefToday() -> Bool {
        let key = "vesper.briefShown." + Self.dayKey(Date())
        return UserDefaults.standard.bool(forKey: key)
    }

    private func markBriefShown() {
        UserDefaults.standard.set(true, forKey: "vesper.briefShown." + Self.dayKey(Date()))
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static let funFacts = [
        "A day on Venus is longer than a year on Venus.",
        "Octopuses have three hearts and blue blood.",
        "The first computer programmer was Ada Lovelace, in 1843.",
        "Honey found in Egyptian tombs was still edible after thousands of years.",
        "The Eiffel Tower grows by about 15 centimetres in summer heat.",
        "A group of flamingos is called a flamboyance.",
        "There are more possible chess games than atoms in the observable universe.",
        "The Moon is slowly drifting about 3.8cm farther from Earth each year.",
        "Bananas are berries, but strawberries are not.",
        "A bolt of lightning is roughly five times hotter than the Sun's surface."
    ]
}
