import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = AppSettings()
    private lazy var calendarService = CalendarService()
    private lazy var state = AppState(settings: settings, calendarService: calendarService)
    private lazy var takeover = TakeoverController(state: state)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        calendarService: calendarService
    )

    private var statusItem: NSStatusItem?
    private var statusTimer: Timer?
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--log-config") {
            fputs("bundle=\(Bundle.main.bundleIdentifier ?? "nil") appearance=\(settings.appearance.rawValue) raw=\(UserDefaults.standard.string(forKey: "vesper.appearance") ?? "nil")\n", stderr)
        }
        setUpStatusItem()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusTitle() }
        }
        RunLoop.main.add(statusTimer!, forMode: .common)


        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                self.settingsWindow.show()
                if let index = CommandLine.arguments.firstIndex(of: "--settings-screenshot"),
                   CommandLine.arguments.indices.contains(index + 1) {
                    let path = CommandLine.arguments[index + 1]
                    let delay = Self.doubleArgument("--screenshot-delay", default: 3.0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        let ok = self?.settingsWindow.captureScreenshot(to: path) ?? false
                        fputs(ok ? "settings screenshot written: \(path)\n" : "settings screenshot failed\n", stderr)
                        if CommandLine.arguments.contains("--quit-after-screenshot") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
                        }
                    }
                }
            }
        }

        if CommandLine.arguments.contains("--show-dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.takeover.show()
                if let modeIndex = CommandLine.arguments.firstIndex(of: "--mode"),
                   CommandLine.arguments.indices.contains(modeIndex + 1),
                   let mode = DashboardMode(rawValue: CommandLine.arguments[modeIndex + 1]) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        guard let self else { return }
                        if mode == .focus {
                            self.state.startFocus()
                        } else if mode == .lyrics {
                            self.state.openLyrics()
                        } else {
                            self.state.mode = mode
                        }
                    }
                }
                if let index = CommandLine.arguments.firstIndex(of: "--screenshot"),
                   CommandLine.arguments.indices.contains(index + 1) {
                    let path = CommandLine.arguments[index + 1]
                    let delay = Self.doubleArgument("--screenshot-delay", default: 5.0)
                    if CommandLine.arguments.contains("--volume-hud") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.2, delay - 0.7)) { [weak self] in
                            self?.state.showVolume()
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        let ok = self?.takeover.captureScreenshot(to: path) ?? false
                        if CommandLine.arguments.contains("--quit-after-screenshot") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
                        }
                        fputs(ok ? "screenshot written: \(path)\n" : "screenshot failed\n", stderr)
                    }
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: "Vesper")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.toolTip = "Vesper — click to open the dashboard"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        statusItem?.button?.title = " " + timeFormatter.string(from: Date())
        statusItem?.button?.toolTip = "Vesper — \(Date.now.formatted(date: .complete, time: .shortened))"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let openTitle = takeover.isVisible ? "Close Vesper" : "Take Over Display"
        let open = NSMenuItem(title: openTitle, action: #selector(toggleDashboard), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        if !takeover.isVisible {
            let showOn = NSMenuItem(title: "Show On", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for (index, screen) in NSScreen.screens.enumerated() {
                let item = NSMenuItem(
                    title: "\(screen.vesperName)  ·  \(Int(screen.frame.width))×\(Int(screen.frame.height))",
                    action: #selector(chooseScreen(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: index)
                item.state = screen.vesperDisplayID == settings.selectedDisplayID ? .on : .off
                submenu.addItem(item)
            }
            showOn.submenu = submenu
            menu.addItem(showOn)
        }

        menu.addItem(.separator())

        if state.focusEndsAt != nil {
            let end = NSMenuItem(title: "End Focus Session", action: #selector(endFocus), keyEquivalent: "")
            end.target = self
            menu.addItem(end)
        } else {
            let focus = NSMenuItem(title: "Start Focus · \(settings.focusLength) min", action: #selector(startFocus), keyEquivalent: "f")
            focus.target = self
            menu.addItem(focus)
        }

        if state.sleepEndsAt != nil {
            let cancel = NSMenuItem(title: "Cancel Sleep Timer", action: #selector(cancelSleep), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        } else {
            let sleep = NSMenuItem(title: "Sleep Timer", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for minutes in [15, 30, 45, 60, 90] {
                let item = NSMenuItem(title: "Fade out in \(minutes) min", action: #selector(startSleep(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = minutes
                submenu.addItem(item)
            }
            sleep.submenu = submenu
            menu.addItem(sleep)
        }

        let quick = NSMenu(title: "Spotify")
        let playPause = NSMenuItem(title: "Play / Pause", action: #selector(spotifyPlayPause), keyEquivalent: "")
        playPause.target = self
        quick.addItem(playPause)
        let next = NSMenuItem(title: "Next Track", action: #selector(spotifyNext), keyEquivalent: "")
        next.target = self
        quick.addItem(next)
        let openSpotify = NSMenuItem(title: "Open Spotify", action: #selector(openSpotify), keyEquivalent: "")
        openSpotify.target = self
        quick.addItem(openSpotify)
        let spotifyMenu = NSMenuItem(title: "Spotify", action: nil, keyEquivalent: "")
        spotifyMenu.submenu = quick
        menu.addItem(spotifyMenu)

        let lyrics = NSMenuItem(title: "Show Lyrics", action: #selector(showLyrics), keyEquivalent: "l")
        lyrics.target = self
        menu.addItem(lyrics)

        let brief = NSMenuItem(title: "Show Morning Brief", action: #selector(showBrief), keyEquivalent: "b")
        brief.target = self
        menu.addItem(brief)

        let ribbon = NSMenuItem(title: "Day Ribbon", action: #selector(toggleRibbon), keyEquivalent: "r")
        ribbon.target = self
        ribbon.state = settings.dayRibbon ? .on : .off
        menu.addItem(ribbon)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let about = NSMenuItem(title: "About Vesper", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Vesper", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func performOnDashboard(_ action: @escaping (AppState) -> Void) {
        if !takeover.isVisible {
            takeover.show()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            action(self.state)
        }
    }

    @objc private func toggleDashboard() {
        if takeover.isVisible { takeover.close() } else { takeover.show() }
    }

    @objc private func chooseScreen(_ sender: NSMenuItem) {
        guard let index = (sender.representedObject as? NSNumber)?.intValue,
              NSScreen.screens.indices.contains(index) else { return }
        let screen = NSScreen.screens[index]
        settings.selectedDisplayID = screen.vesperDisplayID
        if takeover.isVisible { takeover.close() }
        takeover.show(on: screen)
    }

    @objc private func startFocus() {
        performOnDashboard { $0.startFocus() }
    }

    @objc private func endFocus() {
        state.endFocus()
    }

    @objc private func startSleep(_ sender: NSMenuItem) {
        let minutes = (sender.representedObject as? Int) ?? 30
        state.startSleep(minutes: minutes)
        if takeover.isVisible { state.showToast("Sleep timer set for \(minutes) minutes") }
    }

    @objc private func cancelSleep() {
        state.cancelSleep()
    }

    @objc private func spotifyPlayPause() {
        Task {
            await state.refreshSpotify()
            state.togglePlayPause()
        }
    }

    @objc private func spotifyNext() {
        state.nextTrack()
    }

    @objc private func openSpotify() {
        Task { await SpotifyMenuBridge.open() }
    }

    @objc private func showLyrics() {
        Task {
            await state.refreshSpotify()
            if !takeover.isVisible { takeover.show() }
            try? await Task.sleep(for: .milliseconds(180))
            state.openLyrics()
        }
    }

    @objc private func showBrief() {
        performOnDashboard { state in
            state.mode = .brief
        }
    }

    @objc private func toggleRibbon() {
        settings.dayRibbon.toggle()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        takeover.close()
        NSApp.terminate(nil)
    }

    private static func doubleArgument(_ name: String, default defaultValue: Double) -> Double {
        guard let index = CommandLine.arguments.firstIndex(of: name),
              CommandLine.arguments.indices.contains(index + 1),
              let value = Double(CommandLine.arguments[index + 1]) else { return defaultValue }
        return value
    }
}

enum SpotifyMenuBridge {
    static func open() async {
        await MainActor.run {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
