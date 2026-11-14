import Foundation

struct LyricsResult: Equatable {
    let synced: Bool
    let lines: [LyricLine]
    let instrumental: Bool

    init(synced: Bool, lines: [LyricLine], instrumental: Bool = false) {
        self.synced = synced
        self.lines = lines
        self.instrumental = instrumental
    }
}

enum LyricsServiceError: LocalizedError {
    case notFound
    case network
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No synced lyrics found for this track."
        case .network:
            return "Could not load lyrics. Check your connection."
        case .server(let code):
            return "LRCLIB returned an error (\(code)). Try again shortly."
        }
    }
}

actor LyricsService {
    private struct Payload: Decodable {
        let id: Int?
        let trackName: String?
        let artistName: String?
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
    }

    func fetch(title: String, artist: String, album: String, duration: TimeInterval) async throws -> LyricsResult {
        let primaryArtist = artist.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? artist
        let getResult = try await fetchExact(title: title, artist: primaryArtist, album: album, duration: duration)
        if let getResult { return getResult }

        let searchResults = try await search(title: title, artist: primaryArtist)
        if let synced = searchResults.first(where: { !($0.syncedLyrics ?? "").isEmpty }) {
            return result(from: synced)
        }
        if let plain = searchResults.first(where: { !($0.plainLyrics ?? "").isEmpty }) {
            return result(from: plain)
        }
        throw LyricsServiceError.notFound
    }

    private func fetchExact(title: String, artist: String, album: String, duration: TimeInterval) async throws -> LyricsResult? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]
        let (data, status) = try await request(url: components.url!)
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw LyricsServiceError.server(status) }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return result(from: payload)
    }

    private func search(title: String, artist: String) async throws -> [Payload] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        let (data, status) = try await request(url: components.url!)
        guard (200..<300).contains(status) else { throw LyricsServiceError.server(status) }
        return try JSONDecoder().decode([Payload].self, from: data)
    }

    private func request(url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("VesperMac/1.0 (https://github.com/noahengelking/vesper-kiosk)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LyricsServiceError.network }
            return (data, http.statusCode)
        } catch let error as LyricsServiceError {
            throw error
        } catch {
            throw LyricsServiceError.network
        }
    }

    private func result(from payload: Payload) -> LyricsResult {
        if payload.instrumental == true {
            return LyricsResult(synced: false, lines: [], instrumental: true)
        }
        if let synced = payload.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = Self.parseLRC(synced)
            if !lines.isEmpty { return LyricsResult(synced: true, lines: lines) }
        }
        if let plain = payload.plainLyrics, !plain.isEmpty {
            let lines = plain.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .enumerated()
                .map { LyricLine(id: $0.offset, time: 0, text: $0.element) }
            return LyricsResult(synced: false, lines: lines)
        }
        return LyricsResult(synced: false, lines: [])
    }

    nonisolated static func parseLRC(_ source: String) -> [LyricLine] {
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var timed: [(Double, String)] = []

        for rawLine in source.components(separatedBy: .newlines) {
            let range = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
            let matches = regex.matches(in: rawLine, range: range)
            guard !matches.isEmpty else { continue }
            let text = regex.stringByReplacingMatches(in: rawLine, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let minRange = Range(match.range(at: 1), in: rawLine),
                      let secRange = Range(match.range(at: 2), in: rawLine) else { continue }
                let minutes = Double(rawLine[minRange]) ?? 0
                let seconds = Double(rawLine[secRange]) ?? 0
                var fraction = 0.0
                if let fracRange = Range(match.range(at: 3), in: rawLine) {
                    let digits = String(rawLine[fracRange])
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                timed.append((minutes * 60 + seconds + fraction, text))
            }
        }

        return timed.sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
