import Foundation
import AppKit

actor SpotifyService {
    private let separator = "\u{1e}"

    func readSnapshot() async -> SpotifySnapshot {
        let script = """
        set d to ASCII character 30
        tell application "Spotify"
            if it is not running then return "__VESPER_STOPPED__"
            try
                set t to current track
                set stateText to (player state as text)
                set tName to (name of t as text)
                set tArtist to (artist of t as text)
                set tAlbum to (album of t as text)
                set tDur to (duration of t as text)
                set tPos to (player position as text)
                set tVol to (sound volume as text)
                set tArt to ""
                try
                    set tArt to (artwork url of t as text)
                end try
                set tID to ""
                try
                    set tID to (id of t as text)
                end try
                set shuffleText to (shuffling as text)
                set repeatText to (repeating as text)
                return stateText & d & tName & d & tArtist & d & tAlbum & d & tDur & d & tPos & d & tVol & d & tArt & d & tID & d & shuffleText & d & repeatText
            on error errMsg
                return "__VESPER_ERROR__" & errMsg
            end try
        end tell
        """

        guard let output = await ScriptRunner.run(script),
              !output.hasPrefix("__VESPER_STOPPED__"),
              !output.hasPrefix("__VESPER_ERROR__") else {
            return .stopped
        }

        let fields = output.components(separatedBy: separator)
        guard fields.count >= 11 else { return .stopped }

        let state = fields[0].lowercased()
        return SpotifySnapshot(
            isRunning: true,
            isPlaying: state == "playing",
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            duration: (Double(fields[4]) ?? 0) / 1000,
            progress: Double(fields[5]) ?? 0,
            volume: Int(fields[6]) ?? 0,
            artworkURL: fields[7].isEmpty ? nil : fields[7],
            trackID: fields[8],
            isShuffling: fields[9].lowercased() == "true",
            isRepeating: fields[10].lowercased() == "true",
            capturedAt: Date()
        )
    }

    @discardableResult
    func command(_ body: String) async -> Bool {
        let script = "tell application \"Spotify\" to \(body)"
        return await ScriptRunner.run(script) != nil
    }

    func playPause() async { _ = await command("playpause") }
    func nextTrack() async { _ = await command("next track") }
    func previousTrack() async { _ = await command("previous track") }

    func seek(to seconds: TimeInterval) async {
        let value = String(format: "%.3f", max(0, seconds))
        _ = await command("set player position to \(value)")
    }

    func setVolume(_ volume: Int) async {
        let value = max(0, min(100, volume))
        _ = await command("set sound volume to \(value)")
    }

    func setShuffling(_ enabled: Bool) async {
        _ = await command("set shuffling to \(enabled ? "true" : "false")")
    }

    func setRepeating(_ enabled: Bool) async {
        _ = await command("set repeating to \(enabled ? "true" : "false")")
    }

    func openSpotify() async {
        await MainActor.run {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
