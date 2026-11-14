import SwiftUI
import AppKit

struct SpotifyTileView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.vesperPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                palette.panel
                ambientBackground

                VStack(alignment: .leading, spacing: 0) {
                    PanelHeader("Spotify / Mac") {
                        HStack(spacing: 8) {
                            SmallPillButton(title: "Lyrics", symbol: "text.quote") {
                                state.openLyrics()
                            }
                            SmallPillButton(title: "Open", symbol: "arrow.up.forward.app") {
                                Task { await SpotifyMenuBridge.open() }
                            }
                        }
                    }

                    if state.spotify.isRunning, !state.spotify.title.isEmpty {
                        nowPlaying(in: proxy.size)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, max(24, proxy.size.width * 0.035))
                .padding(.vertical, max(20, proxy.size.height * 0.055))
            }
            .clipped()
        }
        .background(palette.panel)
    }

    private var ambientBackground: some View {
        ZStack {
            RadialGradient(
                colors: [state.ambientColors.first?.opacity(0.46) ?? .clear, .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 580
            )
            RadialGradient(
                colors: [state.ambientColors.last?.opacity(0.24) ?? .clear, .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 520
            )
        }
        .blur(radius: 18)
        .opacity(state.spotify.isRunning ? 1 : 0)
        .animation(.easeInOut(duration: 0.8), value: state.spotify.trackID)
    }

    private func nowPlaying(in size: CGSize) -> some View {
        let artSize = min(size.width * 0.22, size.height * 0.43)

        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 14)

            HStack(spacing: max(18, size.width * 0.027)) {
                AlbumArtwork(image: state.artwork, size: artSize)

                VStack(alignment: .leading, spacing: 9) {
                    Text(state.spotify.title)
                        .font(.system(size: min(34, size.width * 0.037), weight: .light, design: .rounded))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text(state.spotify.artist)
                        .font(.system(size: 19, weight: .regular, design: .rounded))
                        .foregroundStyle(palette.dim)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Image(systemName: "airplayaudio")
                            .font(.system(size: 9, weight: .semibold))
                        Text("on this Mac")
                            .font(.vesperLabel(9))
                            .tracking(1.8)
                    }
                    .foregroundStyle(palette.accent)
                    .padding(.top, 2)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 9) {
                    Image(systemName: state.spotify.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .symbolEffect(.variableColor.iterative, isActive: state.spotify.isPlaying)
                    Text(state.spotify.isPlaying ? "PLAYING" : "PAUSED")
                        .font(.vesperLabel(8))
                        .tracking(2)
                        .foregroundStyle(palette.dim)
                }
                .padding(.top, 3)
            }
            .frame(height: artSize)

            Spacer(minLength: 14)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                SpotifyProgressBar(
                    duration: state.spotify.duration,
                    progress: state.spotify.effectiveProgress,
                    onSeek: { state.seek(toFraction: $0) }
                )
            }

            Spacer(minLength: 12)

            controls
                .frame(maxWidth: .infinity)
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            CircleControl(
                symbol: "shuffle",
                size: 52,
                active: state.spotify.isShuffling,
                action: state.toggleShuffle
            )

            CircleControl(symbol: "backward.fill", size: 54, action: state.previousTrack)

            CircleControl(
                symbol: state.spotify.isPlaying ? "pause.fill" : "play.fill",
                size: 72,
                action: state.togglePlayPause
            )

            CircleControl(symbol: "forward.fill", size: 54, action: state.nextTrack)

            CircleControl(
                symbol: "repeat",
                size: 52,
                active: state.spotify.isRepeating,
                action: state.toggleRepeat
            )
        }
    }

    private var emptyState: some View {
        HStack(spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(palette.button)
                Image(systemName: "music.note")
                    .font(.system(size: 42, weight: .ultraLight))
                    .foregroundStyle(palette.dim)
            }
            .frame(width: 148, height: 148)

            VStack(alignment: .leading, spacing: 10) {
                Text("Spotify is ready when you are")
                    .font(.system(size: 27, weight: .light, design: .rounded))
                    .foregroundStyle(palette.foreground)
                Text("Open Spotify on this Mac, start a track, then return here for native controls and synced lyrics.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420, alignment: .leading)
                Button {
                    Task { await SpotifyMenuBridge.open() }
                } label: {
                    Text("Open Spotify")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.background)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(palette.accent))
                }
                .buttonStyle(PressScaleStyle())
                .padding(.top, 5)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }
}

struct AlbumArtwork: View {
    @Environment(\.vesperPalette) private var palette
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(
                        colors: [palette.buttonStrong, palette.button],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .ultraLight))
                        .foregroundStyle(palette.dim)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(12, size * 0.075), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(12, size * 0.075), style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.38), radius: 26, y: 12)
    }
}

private struct SpotifyProgressBar: View {
    @Environment(\.vesperPalette) private var palette
    let duration: TimeInterval
    let progress: TimeInterval
    let onSeek: (Double) -> Void

    private var _dragFraction = State<Double?>(initialValue: nil)
    private var dragFraction: Double? {
        get { _dragFraction.wrappedValue }
        nonmutating set { _dragFraction.wrappedValue = newValue }
    }

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        guard duration > 0 else { return 0 }
        return min(1, max(0, progress / duration))
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.line.opacity(0.9))
                        .frame(height: 5)

                    Capsule()
                        .fill(palette.accent)
                        .frame(width: max(5, proxy.size.width * fraction), height: 5)

                    Circle()
                        .fill(palette.foreground)
                        .frame(width: dragFraction == nil ? 10 : 14, height: dragFraction == nil ? 10 : 14)
                        .offset(x: max(0, proxy.size.width * fraction - (dragFraction == nil ? 5 : 7)))
                        .shadow(color: .black.opacity(0.35), radius: 3)
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            dragFraction = min(1, max(0, gesture.location.x / max(1, proxy.size.width)))
                        }
                        .onEnded { gesture in
                            let value = min(1, max(0, gesture.location.x / max(1, proxy.size.width)))
                            dragFraction = value
                            onSeek(value)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                dragFraction = nil
                            }
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(VFormat.duration(dragFraction.map { duration * $0 } ?? progress))
                Spacer()
                Text(VFormat.duration(duration))
            }
            .font(.vesperLabel(10))
            .tracking(1.6)
            .foregroundStyle(palette.dim)
            .monospacedDigit()
        }
    }
}
