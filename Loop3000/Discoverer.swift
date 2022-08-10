import Foundation
import CoreMedia
import AVFoundation

struct Timestamp: Codable {
    static let timeScale = 75
    private static let CueTimestampRegex = /(\d\d):(\d\d):(\d\d)/
    var rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(minutes: Int, seconds: Int, frames: Int) {
        let totalSeconds = minutes * 60 + seconds
        let totalFrames = totalSeconds * Timestamp.timeScale + frames
        self.init(rawValue: totalFrames)
    }

    init?(fromCueTimestampString s: String) {
        guard let match = try? Timestamp.CueTimestampRegex.wholeMatch(in: s) else { return nil }
        self.init(minutes: Int(match.1)!, seconds: Int(match.2)!, frames: Int(match.3)!)
    }

    init(from time: CMTime) {
        let cmScale = Int(time.timescale)
        let num = Int(time.value) * Timestamp.timeScale + cmScale / 2
        self.init(rawValue: num / cmScale)
    }
}

extension CMTime {
    init(from timestamp: Timestamp) {
        self.init(value: CMTimeValue(timestamp.rawValue), timescale: CMTimeScale(Timestamp.timeScale))
    }
}

class Track: Codable {
    var source: URL
    var start: Timestamp
    var end: Timestamp
    weak var album: Album?
    var title: String?
    var artists: [String]?
    var trackNumber: Int?
    var diskNumber: Int?
    var extraMetadata: [String: String] = [:]

    init(source: URL, start: Timestamp, end: Timestamp) {
        self.source = source
        self.start = start
        self.end = end
    }
}

class Album: Codable {
    var tracks: [Track] = []
    var title: String?
    var artists: [String]?
    var trackCountInDiscs: [Int]?
    var extraMetadata: [String: String] = [:]
}

struct DecodeError: Error {}

private func loadContent(from url: URL) async throws -> String {
    let (data, response) = try await URLSession.shared.data(from: url)
    let encodingValue = response.textEncodingName
            .map { $0 as CFString }
            .map { CFStringConvertIANACharSetNameToEncoding($0) }
            .map { CFStringConvertEncodingToNSStringEncoding($0) }
        ?? NSString.stringEncoding(for: data, convertedString: nil, usedLossyConversion: nil)
    // Fallback to utf8
    let encoding: String.Encoding = encodingValue == 0 ? .utf8 : .init(rawValue: encodingValue)
    guard let content = String(data: data, encoding: encoding) else {
        throw DecodeError()
    }
    return content
}

protocol FileParser {
    func parse(url: URL) async throws -> (albums: [Album], tracks: [Track])
}

struct CueSheetParser: FileParser {
    private static let linePartRegex = /(".+?"|.+?)\s+/

    struct InvalidFormat: Error {}
    struct FileNotFound: Error {
        let url: URL
    }

    func parse(url: URL) async throws -> (albums: [Album], tracks: [Track]) {
        let content = try await loadContent(from: url)
        var currentFile: URL?
        var currentTrack: Track?
        var tracks: [Track] = []
        var albums: [Album] = []
        for line in content.split(whereSeparator: \.isNewline) {
            var parts: [Substring] = []
            var remaining = (line.trimmingCharacters(in: .whitespaces) + " ")[...]
            while let match = try! CueSheetParser.linePartRegex.firstMatch(in: remaining) {
                remaining = remaining[match.range.upperBound...]
                parts.append(match.1)
            }
            if parts.isEmpty {
                continue
            }
            print(parts)
            let command = parts[0].uppercased()
            let params = parts[1...].map{$0.trimmingCharacters(in: CharacterSet(charactersIn: "\""))}
            switch (command, params) {
            case ("FILE", let params) where params.count == 2:
                print(params)
                let filePath = String(params[0])
                var file = URL(filePath: filePath, relativeTo: url.deletingLastPathComponent())
                if file.isFileURL && !FileManager.default.fileExists(atPath: file.path) {
                    // When compressing using FLAC, EAC retain .wav suffix in cue
                    file.deletePathExtension()
                    file.appendPathExtension("flac")
                    if !FileManager.default.fileExists(atPath: file.path) {
                        throw FileNotFound(url: file)
                    }
                }
                currentFile = file
            case ("TRACK", let params) where params.count == 2:
                if let previousTrack = currentTrack {
                    tracks.append(previousTrack)
                }
                guard let file = currentFile else {
                    throw InvalidFormat()
                }
                currentTrack = Track(source: file, start: Timestamp.init(rawValue: -1), end: Timestamp.init(rawValue: -1))
            case ("INDEX", let params) where params.count == 2:
                guard let file = currentFile,
                      let track = currentTrack,
                      let number = Int(params[0]),
                      let timestamp = Timestamp(fromCueTimestampString: params[1])
                else {
                    throw InvalidFormat()
                }
                switch number {
                case 0:
                    if tracks.last?.source == track.source {
                        tracks.last!.end = timestamp
                    }
                case 1:
                    track.source = file
                    track.start = timestamp
                    if tracks.last?.source == track.source && tracks.last!.end.rawValue == -1 {
                        tracks.last!.end = timestamp
                    }
                default:
                    ()
                }
            default:
                ()
            }
        }
        if let previousTrack = currentTrack {
            tracks.append(previousTrack)
        }
        tracks = tracks.filter {$0.start.rawValue != -1}
        let tracksWithUnknownEnd = tracks.filter {$0.end.rawValue == -1}
        let sourcesNeedDuration = Set(tracksWithUnknownEnd.map {$0.source})
        let durations = try await withThrowingTaskGroup(of: (url: URL, duration: Timestamp).self) { taskGroup in
            for source in sourcesNeedDuration {
                taskGroup.addTask {
                    let asset = AVAsset(url: source)
                    let duration = try await asset.load(.duration)
                    return (url: source, duration: Timestamp.init(from: duration))
                }
            }
            var durations: [URL: Timestamp] = [:]
            for try await item in taskGroup {
                durations[item.url] = item.duration
            }
            return durations
        }
        for track in tracksWithUnknownEnd {
            track.end = durations[track.source]!
        }
        return (albums: albums, tracks: tracks)
    }
}
