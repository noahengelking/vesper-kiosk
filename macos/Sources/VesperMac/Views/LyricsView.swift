import SwiftUI
import AppKit

struct LyricsScreenView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.vesperPalette) private var palette

    var body: some View {
        ZStack {
            palette.background
            ambient

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let progress = state.spotify.isPlaying
                    ? min(state.spotify.duration, state.spotify.progress + Date().timeIntervalSince(state.spotify.capturedAt))
                    : state.spotify.progress
                lyricsLayout(progress: progress)
            }
        }
        .clipped()
    }

    private var ambient: some View {
        ZStack {
            RadialGradient(
                colors: [state.ambientColors.first?.opacity(0.18) ?? .clear, .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 900
            )
            RadialGradient(
                colors: [state.ambientColors.last?.opacity(0.12) ?? .clear, .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 800
            )
        }
        .blur(radius: 38)
    }

    private func lyricsLayout(progress: TimeInterval) -> some View {
        VStack(spacing: 0) {
            LyricsProgressBar(
                duration: state.spotify.duration,
                progress: progress,
                onSeek: { state.seek(toFraction: $0) }
            )
            .frame(height: 8)

            HStack(spacing: 22) {
                AlbumArtwork(image: state.artwork, size: 116)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Rectangle().fill(palette.accent).frame(width: 22, height: 1)
                        Text("LIVE LYRICS")
                            .vesperLabel(size: 10)
                            .foregroundStyle(palette.accent)
                    }
                    Text(state.spotify.title.isEmpty ? "Nothing playing" : state.spotify.title)
                        .font(.system(size: 31, weight: .light, design: .rounded))
                        .foregroundStyle(palette.foreground)
                        .lineLimit(1)
                    Text(state.spotify.artist)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(palette.dim)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    Button { state.closeLyrics() } label: {
                        HStack(spacing: 8) {
                            Text("BACK").vesperLabel(size: 9)
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(palette.dim)
                        .padding(.horizontal, 15)
                        .frame(height: 34)
                        .background(Capsule().stroke(palette.line, lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle())
                    Text("\(VFormat.duration(progress)) / \(VFormat.duration(state.spotify.duration))")
                        .font(.vesperLabel(10))
                        .foregroundStyle(palette.dim)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 54)
            .padding(.top, 30)
            .padding(.bottom, 22)

            ZStack {
                if state.lyricsLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching LRCLIB for synced lyrics…")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(palette.dim)
                    }
                } else if let error = state.lyricsError {
                    VStack(spacing: 12) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 38, weight: .ultraLight))
                            .foregroundStyle(palette.dim)
                        Text(error)
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(palette.dim)
                    }
                } else {
                    LyricsScroller(
                        lines: state.lyricsResult.lines,
                        synced: state.lyricsResult.synced,
                        progress: progress,
                        offset: state.settings.lyricsOffset,
                        onSeek: { time in
                            guard state.spotify.duration > 0 else { return }
                            state.seek(toFraction: time / state.spotify.duration)
                        }
                    )
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 54)

            HStack {
                Text("Two-finger swipe → to return")
                    .vesperLabel(size: 9)
                    .foregroundStyle(palette.dim.opacity(0.65))
                Spacer()
                Text("OFFSET \(state.settings.lyricsOffset >= 0 ? "+" : "")\(String(format: "%.1f", state.settings.lyricsOffset))s")
                    .vesperLabel(size: 9)
                    .foregroundStyle(palette.dim.opacity(0.65))
            }
            .padding(.horizontal, 54)
            .padding(.bottom, 24)
        }
    }
}

private struct LyricsProgressBar: View {
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
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(palette.line.opacity(0.6))
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: proxy.size.width * fraction)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragFraction = min(1, max(0, gesture.location.x / max(1, proxy.size.width)))
                    }
                    .onEnded { gesture in
                        let value = min(1, max(0, gesture.location.x / max(1, proxy.size.width)))
                        onSeek(value)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { dragFraction = nil }
                    }
            )
        }
    }
}

private struct LyricsScroller: View {
    @Environment(\.vesperPalette) private var palette
    let lines: [LyricLine]
    let synced: Bool
    let progress: TimeInterval
    let offset: Double
    let onSeek: (TimeInterval) -> Void

    private var currentIndex: Int? {
        guard synced else { return nil }
        let adjusted = progress + offset
        var result: Int?
        for (index, line) in lines.enumerated() {
            if line.time <= adjusted { result = index } else { break }
        }
        return result ?? (lines.isEmpty ? nil : 0)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: synced ? 15 : 12) {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let isCurrent = currentIndex == index
                        Text(line.text)
                            .font(.system(
                                size: isCurrent ? 27 : 20,
                                weight: isCurrent ? .semibold : .regular,
                                design: .rounded
                            ))
                            .foregroundStyle(isCurrent ? Color.white.opacity(0.98) : palette.dim.opacity(index < (currentIndex ?? 0) ? 0.52 : 0.74))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, isCurrent ? 7 : 1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if synced { onSeek(line.time) }
                            }
                            .id(index)
                    }
                }
                .padding(.top, 300)
                .padding(.bottom, 300)
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.08),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: currentIndex) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.38)) {
                    reader.scrollTo(newValue, anchor: UnitPoint(x: 0.5, y: 0.38))
                }
            }
            .onAppear {
                guard let currentIndex else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    reader.scrollTo(currentIndex, anchor: UnitPoint(x: 0.5, y: 0.38))
                }
            }
        }
    }
}
