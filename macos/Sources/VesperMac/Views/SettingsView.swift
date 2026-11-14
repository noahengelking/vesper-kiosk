import SwiftUI
import EventKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var calendarService: CalendarService
    private var _showResetConfirmation = State<Bool>(initialValue: false)
    private var showResetConfirmation: Bool {
        get { _showResetConfirmation.wrappedValue }
        nonmutating set { _showResetConfirmation.wrappedValue = newValue }
    }
    private var showResetBinding: Binding<Bool> { _showResetConfirmation.projectedValue }

    private var palette: VesperPalette {
        switch settings.appearance {
        case .dark: return .dark
        case .light: return .light
        case .auto:
            let hour = Calendar.current.component(.hour, from: Date())
            return (7..<19).contains(hour) ? .light : .dark
        }
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    settingsCard("Appearance") {
                        settingRow("Theme") {
                            PillSelector(
                                values: AppearanceMode.allCases.map { ($0.rawValue, $0) },
                                selection: $settings.appearance
                            )
                        }
                        settingRow("Second hand") {
                            PillSelector(
                                values: SecondHandStyle.allCases.map { ($0.rawValue, $0) },
                                selection: $settings.secondHand
                            )
                        }
                        toggleRow("Top-edge day ribbon", isOn: $settings.dayRibbon)
                        toggleRow("Show morning brief once a day", isOn: $settings.showMorningBrief)
                    }

                    settingsCard("Location & Weather") {
                        HStack(spacing: 14) {
                            field("City") {
                                TextField("London", text: $settings.city)
                                    .textFieldStyle(.plain)
                            }
                            field("Latitude") {
                                TextField("51.5072", value: $settings.latitude, format: .number.precision(.fractionLength(4)))
                                    .textFieldStyle(.plain)
                            }
                            field("Longitude") {
                                TextField("-0.1276", value: $settings.longitude, format: .number.precision(.fractionLength(4)))
                                    .textFieldStyle(.plain)
                            }
                        }
                        Text("Open-Meteo needs coordinates; the city name is only used as a label.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(palette.dim)
                    }

                    settingsCard("Clocks") {
                        ForEach(0..<3, id: \.self) { index in
                            settingRow(index == 1 ? "Centre clock" : (index == 0 ? "Left clock" : "Right clock")) {
                                Picker("", selection: zoneBinding(index)) {
                                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { identifier in
                                        Text(identifier.replacingOccurrences(of: "_", with: " ")).tag(identifier)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 260)
                                .controlSize(.small)
                            }
                        }
                    }

                    settingsCard("Focus & Controls") {
                        settingRow("Default focus length") {
                            Stepper("\(settings.focusLength) min", value: $settings.focusLength, in: 5...120, step: 5)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                        }
                        settingRow("Lyrics offset") {
                            HStack(spacing: 10) {
                                Slider(value: $settings.lyricsOffset, in: -3...3, step: 0.5)
                                    .frame(width: 170)
                                Text("\(settings.lyricsOffset >= 0 ? "+" : "")\(String(format: "%.1f", settings.lyricsOffset))s")
                                    .font(.vesperLabel(10))
                                    .foregroundStyle(palette.dim)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }

                    settingsCard("Magical Trackpad") {
                        gestureRow("Two-finger tap", "Play / pause Spotify")
                        gestureRow("Two-finger swipe ←  →", "Move between dashboard and lyrics")
                        gestureRow("Two-finger swipe ↕ at right edge", "Adjust Spotify volume in the bottom pill")
                        gestureRow("Three-finger swipe ←  →", "Same as a two-finger swipe")
                        gestureRow("Three-finger swipe ↑ / ↓", "Start focus / close Vesper")
                        Text("Vesper reads native Magic Trackpad touches inside its takeover window. No external gesture daemon or accessibility permission is required.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(palette.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    settingsCard("Calendar") {
                        HStack(spacing: 12) {
                            Image(systemName: calendarService.hasAccess ? "checkmark.circle.fill" : "calendar.badge.exclamationmark")
                                .foregroundStyle(calendarService.hasAccess ? palette.accent : palette.dim)
                            Text(calendarService.hasAccess ? "Calendar connected" : "Calendar access not connected")
                                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                                .foregroundStyle(palette.foreground)
                            Spacer()
                            if !calendarService.hasAccess {
                                Button("Connect") {
                                    Task {
                                        _ = await calendarService.requestAccess()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Button("Privacy Settings") {
                                    calendarService.openPrivacySettings()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    HStack {
                        Button("Reset visual defaults") { showResetConfirmation = true }
                            .buttonStyle(.bordered)
                        Spacer()
                        Text("Vesper for macOS · native Swift")
                            .font(.vesperLabel(9))
                            .foregroundStyle(palette.dim.opacity(0.65))
                    }
                    .padding(.bottom, 22)
                }
                .padding(32)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .confirmationDialog("Reset visual defaults?", isPresented: showResetBinding) {
            Button("Reset", role: .destructive) { settings.resetDisplayDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your calendar, Spotify, and account data are untouched.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VESPER / SETTINGS")
                .vesperLabel(size: 10)
                .foregroundStyle(palette.accent)
            Text("Make it yours.")
                .font(.system(size: 34, weight: .ultraLight, design: .rounded))
                .foregroundStyle(palette.foreground)
            Text("The menu bar app keeps Vesper out of your way until you need it.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(palette.dim)
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .vesperLabel(size: 10)
                .foregroundStyle(palette.dim)
            content()
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 18).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.line, lineWidth: 1))
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 20) {
            Text(label)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(palette.foreground.opacity(0.9))
            Spacer(minLength: 16)
            content()
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(palette.foreground.opacity(0.9))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(palette.accent)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .vesperLabel(size: 9)
                .foregroundStyle(palette.dim)
            content()
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(palette.foreground)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.button.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.line, lineWidth: 1))
        }
    }

    private func gestureRow(_ gesture: String, _ action: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(gesture)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(palette.foreground)
                .frame(width: 220, alignment: .leading)
            Text(action)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(palette.dim)
            Spacer()
        }
    }

    private func zoneBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { settings.clockZones[index] },
            set: { settings.clockZones[index] = $0 }
        )
    }
}
