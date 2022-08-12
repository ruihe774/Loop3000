import Foundation
import CoreMedia
import AVFoundation

struct Timestamp: Codable {
    static let timeScale = 75
    private static let cueTimestampRegex = /(\d\d):(\d\d):(\d\d)/
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
        guard let match = try? Timestamp.cueTimestampRegex.wholeMatch(in: s) else { return nil }
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

struct Metadata: Codable {
    struct CommonKey {
        static let title = "TITLE"
        static let version = "VERSION"
        static let album = "ALBUM"
        static let trackNumber = "TRACKNUMBER"
        static let artist = "ARTIST"
        static let performer = "PERFORMER"
        static let composer = "COMPOSER"
        static let copyright = "COPYRIGHT"
        static let license = "LICENSE"
        static let organization = "ORGANIZATION"
        static let description = "DESCRIPTION"
        static let genre = "GENRE"
        static let date = "DATE"
        static let location = "LOCATION"
        static let ISRC = "ISRC"
        static let comment = "COMMENT"
        static let encoder = "ENCODER"
    }

    enum Value: Codable {
        case single(String)
        case multiple([String])
    }

    var mapping: [String: Value] = [:]

    subscript(key: String) -> Value? {
        get {
            mapping[key]
        }
        set {
            mapping[key] = newValue
        }
    }
}

class Track: Codable {
    var source: URL
    var start: Timestamp
    var end: Timestamp
    unowned var album: Album
    var title: String?
    var artists: [String]?
    var trackNumber: Int?
    var discNumber: Int?
    var extraMetadata = Metadata()

    init(source: URL, start: Timestamp, end: Timestamp, album: Album) {
        self.source = source
        self.start = start
        self.end = end
        self.album = album
    }
}

class Album: Codable {
    var tracks: [Track] = []
    var title: String?
    var artists: [String]?
    var extraMetadata = Metadata()
}

struct DecodeError: Error {}

private func universalSplit(_ s: String) -> [String] {
    s
        .split {",;，；、\r\n".contains($0)}
        .map {$0.trimmingCharacters(in: .whitespaces)}
        .filter {!$0.isEmpty}
}

private func universalMetadataSplit(_ s: String) -> Metadata.Value? {
    let ss = universalSplit(s)
    switch ss.count {
    case 0:
        return nil
    case 1:
        return .single(ss[0])
    default:
        return .multiple(ss)
    }
}

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

extension URL {
    mutating func replacePathExtension(_ pathExtension: String) {
        deletePathExtension()
        appendPathExtension(pathExtension)
    }

    func replacingPathExtension(_ pathExtension: String) -> Self {
        deletingPathExtension().appendingPathExtension(pathExtension)
    }
}

protocol FileParser {
    func parse(url: URL) async throws -> (albums: [Album], tracks: [Track])
}

struct CueSheetParser: FileParser {
    private static let linePartRegex = /(".+?"|.+?)\s+/

    struct InvalidFormat: Error {
        let url: URL
    }
    struct FileNotFound: Error {
        let url: URL
    }

    func parse(url: URL) async throws -> (albums: [Album], tracks: [Track]) {
        let content = try await loadContent(from: url)
        var currentFile: URL?
        var currentTrack: Track?
        var tracks: [Track] = []
        let album = Album()
        var discNumber: Int?
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
            let command = parts[0].uppercased()
            let params = parts[1...].map{$0.trimmingCharacters(in: CharacterSet(charactersIn: "\""))}
            func setMetadata(_ rawValue: String = params[0], for key: String, split: Bool = false) {
                let value = split ? universalMetadataSplit(rawValue) : .single(rawValue)
                if let track = currentTrack {
                    track.extraMetadata[key] = value
                } else {
                    album.extraMetadata[key] = value
                }
            }
            switch (command, params.count) {
            case ("FILE", 2):
                let filePath = String(params[0])
                var file = URL(filePath: filePath, relativeTo: url.deletingLastPathComponent())
                if file.isFileURL && !FileManager.default.fileExists(atPath: file.path) {
                    // When compressing using FLAC, EAC retain .wav suffix in cue
                    let flacFile = file.replacingPathExtension("flac")
                    guard FileManager.default.fileExists(atPath: flacFile.path) else {
                        throw FileNotFound(url: file)
                    }
                    file = flacFile
                }
                currentFile = file
            case ("TRACK", 2):
                if let previousTrack = currentTrack {
                    tracks.append(previousTrack)
                }
                guard let file = currentFile else {
                    throw InvalidFormat(url: url)
                }
                currentTrack = Track(
                    source: file,
                    start: Timestamp.init(rawValue: -1),
                    end: Timestamp.init(rawValue: -1),
                    album: album
                )
            case ("INDEX", 2):
                guard let file = currentFile,
                      let track = currentTrack,
                      let number = Int(params[0]),
                      let timestamp = Timestamp(fromCueTimestampString: params[1])
                else {
                    throw InvalidFormat(url: url)
                }
                switch number {
                case 0:
                    if let previousTrack = tracks.last, previousTrack.source == track.source {
                        previousTrack.end = timestamp
                    }
                case 1:
                    track.source = file
                    track.start = timestamp
                    if let previousTrack = tracks.last,
                       previousTrack.source == track.source && previousTrack.end.rawValue == -1 {
                        previousTrack.end = timestamp
                    }
                default:
                    ()
                }
            case ("SONGWRITER", 1):
                setMetadata(for: Metadata.CommonKey.composer, split: true)
            case ("ISRC", 1):
                setMetadata(for: Metadata.CommonKey.ISRC)
            case ("PERFORMER", 1):
                let artists = universalSplit(params[0])
                if let track = currentTrack {
                    track.artists = artists
                } else {
                    album.artists = artists
                }
            case ("TITLE", 1):
                let title = params[0]
                if let track = currentTrack {
                    track.title = title
                } else {
                    album.title = title
                }
            case ("REM", 2):
                switch params[0] {
                case "DATE":
                    setMetadata(params[1], for: Metadata.CommonKey.date)
                case "COMPOSER":
                    setMetadata(params[1], for: Metadata.CommonKey.composer, split: true)
                case "GENRE":
                    setMetadata(params[1], for: Metadata.CommonKey.genre)
                case "DISCNUMBER":
                    discNumber = Int(params[1])
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
        album.tracks = tracks
        for (i, track) in tracks.enumerated() {
            track.trackNumber = i + 1
            track.discNumber = discNumber
        }
        return (albums: [album], tracks: tracks)
    }
}

protocol Grabber {
    func grab(tracks: [Track]) async throws
}

struct FLACGrabber {
    struct InvalidFormat: Error {
        let url: URL
    }

    private func parse32bitIntLE(_ data: Data) -> Int {
        precondition(data.count == 4)
        return Int(data[0]) | Int(data[1] << 8) | Int(data[2] << 16) | Int(data[3] << 24)
    }

    func grab(tracks: [Track]) async throws {
        let sources = Set(tracks.map {$0.source}).filter {$0.pathExtension == "flac"}
        let metadatas = try await withThrowingTaskGroup(of: (source: URL, metadata: Metadata).self) { taskGroup in
            for source in sources {
                taskGroup.addTask {
                    var reader = AsyncReader(source.resourceBytes)
                    if try await reader.read(count: 4) != Data([0x66, 0x4C, 0x61, 0x43]) {
                        throw InvalidFormat(url: source)
                    }
                    var last = false
                    var metadata = Metadata()
                    repeat {
                        let header = try await reader.readEnough(count: 4)
                        last = (header[0] >> 7) != 0
                        let type = header[0] & 0x7f
                        let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
                        switch type {
                        case 4: // VORBIS_COMMENT
                            let vendorStringLength = parse32bitIntLE(try await reader.readEnough(count: 4))
                            let vendorString = try await reader.readEnough(count: vendorStringLength)
                            metadata[Metadata.CommonKey.encoder] = String(data: vendorString, encoding: .utf8).map {.single($0)}
                            let vectorLength = parse32bitIntLE(try await reader.readEnough(count: 4))
                            var totalReadCount = 8 + vendorStringLength
                            for _ in 0 ..< vectorLength {
                                let commentLength = parse32bitIntLE(try await reader.readEnough(count: 4))
                                let data = try await reader.readEnough(count: commentLength)
                                totalReadCount += 4 + commentLength
                                guard let comment = String(data: data, encoding: .utf8) else {
                                    continue
                                }
                                let parts = comment.split(separator: "=", maxSplits: 2).map {String($0)}
                                let (key, value) = (parts[0], parts[1])
                                metadata[key] = .single(value)
                            }
                            if totalReadCount != length {
                                throw InvalidFormat(url: source)
                            }
                        default:
                            let _ = try await reader.readEnough(count: length)
                        }
                    } while !last
                    return (source: source, metadata: metadata)
                }
            }
            var metadatas = [URL: Metadata]()
            for try await item in taskGroup {
                metadatas[item.source] = item.metadata
            }
            return metadatas
        }
        for track in tracks {
            guard let newMetadata = metadatas[track.source] else {continue}
            newMetadata.mapping.forEach { (k, v) in track.extraMetadata[k] = v }
        }
    }
}
