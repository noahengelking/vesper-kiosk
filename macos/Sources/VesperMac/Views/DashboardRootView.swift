import SwiftUI

struct DashboardRootView: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void

    var body: some View {
        let palette = state.palette

        ZStack {
            palette.background.ignoresSafeArea()

            if state.mode == .dashboard {
                dashboard
                    .transition(.opacity)
            } else if state.mode == .lyrics {
                LyricsScreenView()
                    .environmentObject(state)
                    .transition(.opacity)
            } else if state.mode == .focus {
                FocusScreenView()
                    .environmentObject(state)
                    .transition(.opacity)
            } else {
                MorningBriefView()
                    .environmentObject(state)
                    .transition(.opacity)
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.dim)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(palette.line, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    .help("Close Vesper (Esc)")
                }
                Spacer()
            }
            .padding(16)

            if let volume = state.volumeHUD {
                VStack {
                    Spacer()
                    VolumePillView(value: volume.value) { state.setVolume($0) }
                        .transition(.opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.96)))
                        .padding(.bottom, 26)
                }
                .zIndex(20)
            }

            if state.gestureHintVisible && state.volumeHUD == nil {
                VStack {
                    Spacer()
                    GestureHintView()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 28)
                }
                .zIndex(18)
            }

            if let toast = state.toast {
                VStack {
                    ToastView(text: toast.text, isError: toast.kind == .error)
                        .padding(.top, 18)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(30)
            }
        }
        .environmentObject(calendarServiceForEnvironment)
        .environment(\.vesperPalette, palette)
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .animation(.easeInOut(duration: 0.35), value: state.mode)
        .animation(.easeOut(duration: 0.24), value: state.volumeHUD)
        .animation(.easeOut(duration: 0.28), value: state.gestureHintVisible)
        .animation(.easeOut(duration: 0.22), value: state.toast?.text)
        .onAppear { state.setDashboardActive(true) }
        .onDisappear { state.setDashboardActive(false) }
    }

    private var calendarServiceForEnvironment: CalendarService {
        state.calendarService
    }

    private var dashboard: some View {
        VStack(spacing: 1) {
            if state.settings.dayRibbon {
                DayRibbonView()
                    .environmentObject(state)
            }

            HStack(spacing: 1) {
                ClockTileView()
                    .environmentObject(state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                SpotifyTileView()
                    .environmentObject(state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 1) {
                CalendarTileView()
                    .environmentObject(state)
                    .environmentObject(state.calendarService)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                WeatherTileView()
                    .environmentObject(state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(state.palette.line)
    }
}
