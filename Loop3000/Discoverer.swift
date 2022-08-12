import Foundation
import CoreMedia
import AVFoundation
import UniformTypeIdentifiers

struct Timestamp: Equatable {
    private static let cueTimestampRegex = /(\d\d):(\d\d):(\d\d)/

    var value: Int

    static let timeScale = 75

    static let invalid = Timestamp(value: -1)
    static let indefinite = Timestamp(value: -2)
    static let negativeInfinity = Timestamp(value: -3)
    static let positiveInfinity = Timestamp(value: -4)

    init() {
        self = Self.invalid
    }

    init(value: Int) {
        self.value = value
    }

    init(minutes: Int, seconds: Int, frames: Int) {
        let totalSeconds = minutes * 60 + seconds
        let totalFrames = totalSeconds * Self.timeScale + frames
        self.init(value: totalFrames)
    }

    init?(fromCueTimestampString s: String) {
        guard let match = try? Timestamp.cueTimestampRegex.wholeMatch(in: s) else { return nil }
        self.init(minutes: Int(match.1)!, seconds: Int(match.2)!, frames: Int(match.3)!)
    }

    init(from time: CMTime) {
        switch time {
        case .invalid:
            self = Self.invalid
        case .indefinite:
            self = Self.indefinite
        case .negativeInfinity:
            self = Self.negativeInfinity
        case .positiveInfinity:
            self = Self.positiveInfinity
        default:
            self.init(value: Int(time.value) * Timestamp.timeScale / Int(time.timescale))
        }
    }

    var minutes: Int {
        value / Self.timeScale / 60
    }

    var seconds: Int {
        value / Self.timeScale % 60
    }

    var frames: Int {
        value % Self.timeScale
    }

    var description: String {
        String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }
}

extension CMTime {
    init(from timestamp: Timestamp) {
        switch timestamp {
        case .invalid:
            self = Self.invalid
        case .indefinite:
            self = Self.indefinite
        case .negativeInfinity:
            self = Self.negativeInfinity
        case .positiveInfinity:
            self = Self.positiveInfinity
        default:
            self.init(value: CMTimeValue(timestamp.value), timescale: CMTimeScale(Timestamp.timeScale))
        }
    }
}

extension Timestamp: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        self.init(fromCueTimestampString: s)!
    }
}

typealias Metadata = [String: String]

struct MetadataCommonKey {
    static let title = "TITLE"
    static let version = "VERSION"
    static let album = "ALBUM"
    static let trackNumber = "TRACKNUMBER"
    static let discNumber = "DISCNUMBER"
    static let artist = "ARTIST"
    static let albumArtist = "ALBUMARTIST"
    static let performer = "PERFORMER"
    static let composer = "COMPOSER"
    static let author = "AUTHOR"
    static let contributor = "CONTRIBUTOR"
    static let creator = "CREATOR"
    static let publisher = "PUBLISHER"
    static let copyright = "COPYRIGHT"
    static let license = "LICENSE"
    static let organization = "ORGANIZATION"
    static let description = "DESCRIPTION"
    static let genre = "GENRE"
    static let date = "DATE"
    static let language = "LANGUAGE"
    static let location = "LOCATION"
    static let ISRC = "ISRC"
    static let comment = "COMMENT"
    static let encoder = "ENCODER"
}

class Album: Identifiable, Codable {
    var id = UUID()
    var metadata = Metadata()
}

class Track: Identifiable, Codable {
    var id = UUID()
    var source: URL
    var start: Timestamp
    var end: Timestamp
    var albumId: UUID
    var metadata = Metadata()

    init(source: URL, start: Timestamp, end: Timestamp, albumId: UUID) {
        self.source = source
        self.start = start
        self.end = end
        self.albumId = albumId
    }
}

struct PlayItem {
    let track: Track
    let album: Album

    private func universalSplit(_ s: String) -> [String] {
        s
            .split { ",;，；、\r\n".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var title: String {
        track.metadata[MetadataCommonKey.title] ?? track.source.lastPathComponent
    }

    var artists: [String] {
        universalSplit(
            track.metadata[MetadataCommonKey.artist] ??
            album.metadata[MetadataCommonKey.artist] ??
            ""
        )
    }

    var trackNumber: Int? {
        if let numberString = track.metadata[MetadataCommonKey.trackNumber] {
            return Int(numberString)
        } else {
            return nil
        }
    }

    var discNumber: Int? {
        if let numberString = track.metadata[MetadataCommonKey.discNumber] {
            return Int(numberString)
        } else {
            return nil
        }
    }

    var albumTitle: String? {
        album.metadata[MetadataCommonKey.title]
    }

    var albumArtists: [String] {
        universalSplit(
            album.metadata[MetadataCommonKey.artist] ??
            ""
        )
    }

    init(track: Track, album: Album) {
        assert(track.albumId == album.id)
        self.track = track
        self.album = album
    }
}

fileprivate extension Array where Element: Identifiable {
    func getElementById(id: Element.ID) -> Element? {
        self.first {
            $0.id == id
        }
    }
}

class MusicLibrary: Codable {
    static var mediaImporters: [any MediaImporter] = [CueSheetImporter()]
    static var metadataGrabbers: [any MetadataGrabber] = [FLACGrabber(), AVGrabber()]

    var albums = [Album]()
    var tracks = [Track]()

    struct NoApplicableImporter: Error {
        let url: URL
    }

    func importMedia(from url: URL) async throws {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            throw NoApplicableImporter(url: url)
        }
        guard let importer = Self.mediaImporters.first(where: { importer in
            importer.supportedTypes.contains { type.conforms(to: $0) }
        }) else {
            throw NoApplicableImporter(url: url)
        }

        let (albums, tracks) = try await importer.importMedia(url: url)

        let sources = Set(tracks.map { $0.source })
        let metadatas = try await withThrowingTaskGroup(of: (source: URL, metadata: Metadata).self) { taskGroup in
            for source in sources {
                guard let type = UTType(filenameExtension: source.pathExtension) else {
                    continue
                }
                guard let grabber = Self.metadataGrabbers.first(where: { grabber in
                    grabber.supportedTypes.contains { type.conforms(to: $0) }
                }) else {
                    continue
                }
                taskGroup.addTask {
                    (source: source, metadata: try await grabber.grabMetadata(url: source))
                }
            }
            var metadatas = [URL: Metadata]()
            for try await item in taskGroup {
                metadatas[item.source] = item.metadata
            }
            return metadatas
        }
        for track in tracks {
            guard let metadata = metadatas[track.source] else {
                continue
            }
            metadata.forEach { (k, v) in track.metadata[k] = v }
        }

        for track in tracks {
            if let album = track.metadata[MetadataCommonKey.album] {
                albums.getElementById(id: track.albumId)!.metadata[MetadataCommonKey.title] = album
                track.metadata[MetadataCommonKey.album] = nil
            }
            if let albumArtist = track.metadata[MetadataCommonKey.albumArtist] {
                albums.getElementById(id: track.albumId)!.metadata[MetadataCommonKey.artist] = albumArtist
                track.metadata[MetadataCommonKey.albumArtist] = nil
            }
        }

        self.albums.append(contentsOf: albums)
        self.tracks.append(contentsOf: tracks)
    }

    var canImportTypes: [UTType] {
        Self.mediaImporters.flatMap { $0.supportedTypes }
    }

    var canGrabTypes: [UTType] {
        Self.metadataGrabbers.flatMap { $0.supportedTypes }
    }
}

protocol MediaImporter {
    var supportedTypes: [UTType] { get }

    func importMedia(url: URL) async throws -> (albums: [Album], tracks: [Track])
}

protocol MetadataGrabber {
    var supportedTypes: [UTType] { get }

    func grabMetadata(url: URL) async throws -> Metadata
}

fileprivate extension URL {
    mutating func replacePathExtension(_ pathExtension: String) {
        deletePathExtension()
        appendPathExtension(pathExtension)
    }

    func replacingPathExtension(_ pathExtension: String) -> Self {
        deletingPathExtension().appendingPathExtension(pathExtension)
    }
}

fileprivate struct CueSheetImporter: MediaImporter {
    let supportedTypes = [UTType("io.misakikasumi.Loop3000.CueSheet")!]

    private static let linePartRegex = /(".+?"|.+?)\s+/

    struct InvalidFormat: Error {
        let url: URL
    }

    struct FileNotFound: Error {
        let url: URL
    }

    struct DecodeError: Error {
        let url: URL
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
            throw DecodeError(url: url)
        }
        return content
    }

    func importMedia(url: URL) async throws -> (albums: [Album], tracks: [Track]) {
        let content = try await loadContent(from: url)
        var currentFile: URL?
        var currentTrack: Track?
        var tracks: [Track] = []
        let album = Album()
        var discNumber: Int?
        for line in content.split(whereSeparator: \.isNewline) {
            var parts: [Substring] = []
            var remaining = (line.trimmingCharacters(in: .whitespaces) + " ")[...]
            while let match = try! Self.linePartRegex.firstMatch(in: remaining) {
                remaining = remaining[match.range.upperBound...]
                parts.append(match.1)
            }
            if parts.isEmpty {
                continue
            }
            let command = parts[0].uppercased()
            let params = parts[1...].map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            func setMetadata(_ value: String = params[0], for key: String) {
                if value.isEmpty {
                    return
                }
                if let track = currentTrack {
                    track.metadata[key] = value
                } else {
                    album.metadata[key] = value
                }
            }
            switch (command, params.count) {
            case ("FILE", 2):
                var file = URL(filePath: params[0], relativeTo: url.deletingLastPathComponent())
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
                    start: .invalid,
                    end: .invalid,
                    albumId: album.id
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
                       previousTrack.source == track.source && previousTrack.end == .invalid {
                        previousTrack.end = timestamp
                    }
                default:
                    ()
                }
            case ("SONGWRITER", 1):
                setMetadata(for: MetadataCommonKey.composer)
            case ("ISRC", 1):
                setMetadata(for: MetadataCommonKey.ISRC)
            case ("PERFORMER", 1):
                setMetadata(for: MetadataCommonKey.artist)
            case ("TITLE", 1):
                setMetadata(for: MetadataCommonKey.title)
            case ("REM", 2):
                switch params[0] {
                case "DATE":
                    setMetadata(params[1], for: MetadataCommonKey.date)
                case "COMPOSER":
                    setMetadata(params[1], for: MetadataCommonKey.composer)
                case "GENRE":
                    setMetadata(params[1], for: MetadataCommonKey.genre)
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
        tracks = tracks.filter { $0.start != .invalid }
        let tracksWithUnknownEnd = tracks.filter { $0.end == .invalid }
        let sourcesNeedDuration = Set(tracksWithUnknownEnd.map { $0.source })
        let durations = try await withThrowingTaskGroup(of: (url: URL, duration: Timestamp).self) { taskGroup in
            for source in sourcesNeedDuration {
                taskGroup.addTask {
                    let asset = AVAsset(url: source)
                    let duration = try await asset.load(.duration)
                    return (url: source, duration: Timestamp(from: duration))
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
        for (i, track) in tracks.enumerated() {
            track.metadata[MetadataCommonKey.trackNumber] = String(i + 1)
            track.metadata[MetadataCommonKey.discNumber] = discNumber.map { String($0) }
        }
        return (albums: [album], tracks: tracks)
    }
}

fileprivate struct FLACGrabber: MetadataGrabber {
    let supportedTypes = [UTType("org.xiph.flac")!]

    struct InvalidFormat: Error {
        let url: URL
    }

    private func parse32bitIntLE(_ data: Data) -> Int {
        precondition(data.count == 4)
        return Int(data[0]) | Int(data[1] << 8) | Int(data[2] << 16) | Int(data[3] << 24)
    }

    func grabMetadata(url: URL) async throws -> Metadata {
        var reader = AsyncReader(url.resourceBytes)
        if try await reader.read(count: 4) != Data([0x66, 0x4C, 0x61, 0x43]) {
            throw InvalidFormat(url: url)
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
                metadata[MetadataCommonKey.encoder] = String(data: vendorString, encoding: .utf8)
                let vectorLength = parse32bitIntLE(try await reader.readEnough(count: 4))
                var totalReadCount = 8 + vendorStringLength
                for _ in 0 ..< vectorLength {
                    let commentLength = parse32bitIntLE(try await reader.readEnough(count: 4))
                    let data = try await reader.readEnough(count: commentLength)
                    totalReadCount += 4 + commentLength
                    guard let comment = String(data: data, encoding: .utf8) else { continue }
                    let parts = comment.split(separator: "=", maxSplits: 2).map { String($0) }
                    let (key, value) = (parts[0], parts[1])
                    metadata[key] = value
                }
                if totalReadCount != length {
                    throw InvalidFormat(url: url)
                }
            default:
                let _ = try await reader.readEnough(count: length)
            }
        } while !last
        return metadata
    }
}

fileprivate struct AVGrabber: MetadataGrabber {
    let supportedTypes = [UTType.audio]

    private static let keyMapping: [AVMetadataKey: String] = [
        .commonKeyAlbumName: MetadataCommonKey.album,
        .commonKeyArtist: MetadataCommonKey.artist,
        .commonKeyAuthor: MetadataCommonKey.author,
        .commonKeyContributor: MetadataCommonKey.contributor,
        .commonKeyCopyrights: MetadataCommonKey.copyright,
        .commonKeyCreator: MetadataCommonKey.creator,
        .commonKeyTitle: MetadataCommonKey.title,
        .commonKeyDescription: MetadataCommonKey.description,
        .commonKeyLanguage: MetadataCommonKey.language,
        .commonKeyLocation: MetadataCommonKey.location,
        .commonKeyPublisher: MetadataCommonKey.publisher,
    ]

    func grabMetadata(url: URL) async throws -> Metadata {
        let asset = AVAsset(url: url)
        let avMetadata = try await asset.load(.metadata)
        var metadata = Metadata()
        for item in avMetadata {
            guard let commonKey = item.commonKey else { continue }
            guard let mappedKey = Self.keyMapping[commonKey] else { continue }
            guard let value = try await item.load(.stringValue) else { continue }
            metadata[mappedKey] = value
        }
        return metadata
    }
}
