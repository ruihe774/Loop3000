import Foundation
import CoreGraphics
import CoreImage
import AVFoundation
import UniformTypeIdentifiers

struct Timestamp: Equatable {
    private static let cueTimestampRegex = /(\d\d):(\d\d):(\d\d)/

    var value: Int

    static let timescale = 75

    static let zero = Timestamp(value: 0)
    static let invalid = Timestamp(valueUnchecked: -1)
    static let indefinite = Timestamp(valueUnchecked: -2)
    static let negativeInfinity = Timestamp(valueUnchecked: -3)
    static let positiveInfinity = Timestamp(valueUnchecked: -4)

    var isValid: Bool {
        value >= 0
    }

    init() {
        self = Self.invalid
    }

    init(value: Int) {
        precondition(value >= 0)
        self.value = value
    }

    private init(valueUnchecked: Int) {
        self.value = valueUnchecked
    }

    init(minutes: Int, seconds: Int, frames: Int) {
        let totalSeconds = minutes * 60 + seconds
        let totalFrames = totalSeconds * Self.timescale + frames
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
            self.init(value: Int(time.value) * Timestamp.timescale / Int(time.timescale))
        }
    }

    var minutes: Int {
        value / Self.timescale / 60
    }

    var seconds: Int {
        value / Self.timescale % 60
    }

    var frames: Int {
        value % Self.timescale
    }
}

extension Timestamp: CustomStringConvertible {
    var description: String {
        String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }
}

extension Timestamp {
    var briefDescription: String {
        String(format: "%02d:%02d", minutes, seconds + (frames > Self.timescale / 2 ? 1 : 0))
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
            self.init(value: CMTimeValue(timestamp.value), timescale: CMTimeScale(Timestamp.timescale))
        }
    }
}

extension Timestamp: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(Int.self)
        self.init(valueUnchecked: s)
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

class Album: Unicorn, Codable {
    private(set) var id = makeMonotonicUUID()
    var metadata = Metadata()
    var cover: Data?
}

class Track: Unicorn, Codable {
    private(set) var id = UUID()
    var source: URL
    private var bookmark: Data?
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

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case start
        case end
        case albumId
        case metadata
    }

    private struct BookmarkDataDecodingError: Error {}

    private struct URLBookmarkPair: Codable {
        let url: URL
        let bookmark: Data?
    }

    private static func dumpURL(_ url: URL) throws -> Data {
        return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
    }

    private static func loadURL(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
        guard !isStale && url.startAccessingSecurityScopedResource() else {
            throw BookmarkDataDecodingError()
        }
        return url
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(URLBookmarkPair(url: source, bookmark: (try? Self.dumpURL(source)) ?? bookmark), forKey: .source)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(albumId, forKey: .albumId)
        try container.encode(metadata, forKey: .metadata)
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let pair = try container.decode(URLBookmarkPair.self, forKey: .source)
        source = pair.bookmark.flatMap({ try? Self.loadURL($0) }) ?? pair.url
        bookmark = pair.bookmark
        start = try container.decode(Timestamp.self, forKey: .start)
        end = try container.decode(Timestamp.self, forKey: .end)
        albumId = try container.decode(UUID.self, forKey: .albumId)
        metadata = try container.decode(Metadata.self, forKey: .metadata)
    }
}

class PlaylistItem: Unicorn, Codable {
    private(set) var id: UUID
    var trackId: UUID

    init(id: UUID = UUID(), trackId: UUID) {
        self.id = id
        self.trackId = trackId
    }
}

class Playlist: Unicorn, Codable {
    private(set) var id: UUID
    var title: String
    var items: [PlaylistItem]

    init(id: UUID = UUID(), title: String, items: [PlaylistItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

struct Shelf: Codable {
    var albums: [Album] = []
    var tracks: [Track] = []
    var manualPlaylists: [Playlist] = []

    func getTracks(for album: Album) -> [Track] {
        tracks.filter { $0.albumId == album.id }
    }

    func getTracks(for playlist: Playlist) -> [Track] {
        playlist.items.map { tracks.get(by: $0.trackId)! }
    }

    func getAlbum(for track: Track) -> Album {
        albums.get(by: track.albumId)!
    }

    func sorted(tracks: [Track]) -> [Track] {
        return tracks.sorted {
            if $0.albumId != $1.albumId {
                let albumL = getAlbum(for: $0)
                let albumR = getAlbum(for: $1)
                let albumTitleL = albumL.metadata[MetadataCommonKey.title]
                let albumTitleR = albumR.metadata[MetadataCommonKey.title]
                if albumTitleL != albumTitleR {
                    if albumTitleL == nil { return false }
                    if albumTitleR == nil { return true }
                    return albumTitleL! < albumTitleR!
                }
                return $0.albumId < $1.albumId
            }
            let discNumberL = $0.metadata[MetadataCommonKey.discNumber].flatMap { Int($0) }
            let discNumberR = $1.metadata[MetadataCommonKey.discNumber].flatMap { Int($0) }
            if discNumberL != discNumberR {
                if discNumberL == nil { return false }
                if discNumberR == nil { return true }
                return discNumberL! < discNumberR!
            }
            let trackNumberL = $0.metadata[MetadataCommonKey.trackNumber].flatMap { Int($0) }
            let trackNumberR = $1.metadata[MetadataCommonKey.trackNumber].flatMap { Int($0) }
            if trackNumberL != trackNumberR {
                if trackNumberL == nil { return false }
                if trackNumberR == nil { return true }
                return trackNumberL! < trackNumberR!
            }
            if $0.source.absoluteString != $1.source.absoluteString {
                return $0.source.absoluteString < $1.source.absoluteString
            }
            return $0.start.value < $1.start.value
        }
    }

    func sorted(albums: [Album]) -> [Album] {
        albums.sorted { (albumL, albumR) in
            let albumTitleL = albumL.metadata[MetadataCommonKey.title]
            let albumTitleR = albumR.metadata[MetadataCommonKey.title]
            if albumTitleL != albumTitleR {
                if albumTitleL == nil { return false }
                if albumTitleR == nil { return true }
                return albumTitleL! < albumTitleR!
            }
            return albumL.id < albumR.id
        }
    }

    func consolidateMetadata() {
        for album in albums {
            let tracks = getTracks(for: album)
            if tracks.count < 2 { continue }
            for (key, _) in tracks.first!.metadata {
                switch key {
                case
                    MetadataCommonKey.trackNumber,
                    MetadataCommonKey.discNumber,
                    MetadataCommonKey.ISRC,
                    "TOTALDISCS",
                    "TOTALTRACKS",
                    "DISCTOTAL",
                    "TRACKTOTAL":
                    ()
                default:
                    if let value = commonMetadata(tracks, for: key) {
                        if album.metadata[key] == nil {
                            album.metadata[key] = value
                        }
                        if album.metadata[key] == value {
                            for track in tracks {
                                track.metadata[key] = nil
                            }
                        }
                    }
                }
            }
        }
    }

    mutating func sort() {
        albums = sorted(albums: albums)
        tracks = sorted(tracks: tracks)
    }

    mutating func merge(with other: Shelf) {
        self = mergeShelf(self, other)
    }
}

protocol RequestTracer {
    func add(_ url: URL)
    func remove(_ url: URL)
}

protocol MediaImporter: AnyObject {
    var supportedTypes: [UTType] { get }
    func importMedia(url: URL, tracer: RequestTracer?) async throws -> (albums: [Album], tracks: [Track])
}

protocol MetadataGrabber: AnyObject {
    var supportedTypes: [UTType] { get }
    func grabMetadata(url: URL, tracer: RequestTracer?) async throws -> Metadata
}

var mediaImporters: [any MediaImporter] = [CueSheetImporter(), AVImporter()]
var metadataGrabbers: [any MetadataGrabber] = [FLACGrabber(), AVGrabber()]

struct NoApplicableImporter: Error {
    let url: URL
}

func scanMedia(at url: URL, tracer: RequestTracer?) async throws -> (albums: [Album], tracks: [Track]) {
    guard let type = UTType(filenameExtension: url.pathExtension) else {
        throw NoApplicableImporter(url: url)
    }
    guard let importer = mediaImporters.first(where: { importer in
        importer.supportedTypes.contains { type.conforms(to: $0) }
    }) else {
        throw NoApplicableImporter(url: url)
    }

    let (albums, tracks) = try await importer.importMedia(url: url, tracer: tracer)

    let sources = Set(tracks.map { $0.source })
    let metadatas = try await withThrowingTaskGroup(of: (source: URL, metadata: Metadata).self) { taskGroup in
        for source in sources {
            guard let type = UTType(filenameExtension: source.pathExtension) else { continue }
            guard let grabber = metadataGrabbers.first(where: { grabber in
                grabber.supportedTypes.contains { type.conforms(to: $0) }
            }) else { continue }
            taskGroup.addTask {
                (source: source, metadata: try await grabber.grabMetadata(url: source, tracer: tracer))
            }
        }
        var metadatas = [URL: Metadata]()
        for try await item in taskGroup {
            metadatas[item.source] = item.metadata
        }
        return metadatas
    }
    for track in tracks {
        if let metadata = metadatas[track.source] {
            track.metadata.merge(metadata) { (_, new) in new }
        }
    }

    for track in tracks {
        if let album = track.metadata[MetadataCommonKey.album] {
            albums.get(by: track.albumId)!.metadata[MetadataCommonKey.title] = album
            track.metadata[MetadataCommonKey.album] = nil
        }
        if let albumArtist = track.metadata[MetadataCommonKey.albumArtist] {
            albums.get(by: track.albumId)!.metadata[MetadataCommonKey.artist] = albumArtist
            track.metadata[MetadataCommonKey.albumArtist] = nil
        }
    }

    return (albums: albums, tracks: tracks)
}

func discoverMedia(at url: URL, recursive: Bool = false, tracer: RequestTracer?)
async throws -> (albums: [Album], tracks: [Track], errors: [Error]) {
    var r = (albums: [Album](), tracks: [Track](), errors: [Error]())
    let fileManager = FileManager.default
    var children = Set(try fileManager.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
    ).map { $0.absoluteURL })
    for importer in mediaImporters {
        let applicableFiles = children.filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return importer.supportedTypes.contains { type.conforms(to: $0) }
        }
        await withTaskGroup(of: (albums: [Album], tracks: [Track], errors: [Error]).self) { taskGroup in
            for url in applicableFiles {
                taskGroup.addTask {
                    var rv = (albums: [Album](), tracks: [Track](), errors: [Error]())
                    do {
                        let (albums, tracks) = try await scanMedia(at: url, tracer: tracer)
                        rv.albums = albums
                        rv.tracks = tracks
                    } catch let error {
                        rv.errors = [error]
                    }
                    return rv
                }
            }
            for await item in taskGroup {
                r.albums.append(contentsOf: item.albums)
                r.tracks.append(contentsOf: item.tracks)
                r.errors.append(contentsOf: item.errors)
            }
        }
        children.subtract(applicableFiles)
        children.subtract(r.tracks.map { $0.source.absoluteURL })
    }
    if recursive {
        try await withThrowingTaskGroup(of: (albums: [Album], tracks: [Track], errors: [Error]).self) { taskGroup in
            for child in children {
                let isDirectory = try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
                if isDirectory {
                    taskGroup.addTask {
                        try await discoverMedia(at: child, recursive: true, tracer: tracer)
                    }
                }
            }
            for try await item in taskGroup {
                r.albums.append(contentsOf: item.albums)
                r.tracks.append(contentsOf: item.tracks)
                r.errors.append(contentsOf: item.errors)
            }
        }
    }
    return r
}

fileprivate func mergeShelf(_ a: Shelf, _ b: Shelf) -> Shelf {
    var mergedShelf = Shelf()

    var trackIdMap: [UUID: UUID] = [:]
    var unconsolidatedTracks = (a.tracks + b.tracks).dropDuplicates()
    unconsolidatedTracks.reverse()
    var consolidatedTracks: [Track] = []
    while var track = unconsolidatedTracks.popLast() {
        trackIdMap[track.id] = track.id
        unconsolidatedTracks = unconsolidatedTracks.compactMap {
            guard let mergedTrack = mergeTracks(track, $0) else { return $0 }
            trackIdMap[track.id] = mergedTrack.id
            trackIdMap[$0.id] = mergedTrack.id
            track = mergedTrack
            return nil
        }
        consolidatedTracks.append(track)
    }
    mergedShelf.tracks = consolidatedTracks

    var usedAlbumIds = Set<UUID>()
    for track in consolidatedTracks {
        usedAlbumIds.insert(track.albumId)
    }
    var unconsolidatedAlbums = (a.albums + b.albums).dropDuplicates().filter { usedAlbumIds.contains($0.id) }
    unconsolidatedAlbums.reverse()
    var consolidatedAlbums: [Album] = []
    while var album = unconsolidatedAlbums.popLast() {
        unconsolidatedAlbums = unconsolidatedAlbums.compactMap {
            guard let mergedAlbum = mergeAlbums(
                album,
                mergedShelf.getTracks(for: album),
                $0,
                mergedShelf.getTracks(for: $0)
            ) else { return $0 }
            album = mergedAlbum
            return nil
        }
        consolidatedAlbums.append(album)
    }
    mergedShelf.albums = consolidatedAlbums

    let consolidatedPlaylists = (a.manualPlaylists + b.manualPlaylists).dropDuplicates()
    for playlist in consolidatedPlaylists {
        for item in playlist.items {
            item.trackId = trackIdMap[item.trackId]!
        }
    }
    mergedShelf.manualPlaylists = consolidatedPlaylists

    return mergedShelf
}

fileprivate func mergeTracks(_ a: Track, _ b: Track) -> Track? {
    guard a.source.absoluteURL == b.source.absoluteURL else { return nil }
    guard abs(a.start.value - b.start.value) < 500 || !a.start.isValid || !b.start.isValid else { return nil }
    guard abs(a.end.value - b.end.value) < 500 || !a.end.isValid || !b.end.isValid else { return nil }
    let durationA = a.start.isValid && a.end.isValid ? a.end.value - a.start.value : .max
    let durationB = b.start.isValid && b.end.isValid ? b.end.value - b.start.value : .max
    let selected = durationA == durationB ? (a.albumId < b.albumId ? a : b) : (durationA < durationB ? a : b)
    let abandoned = selected.id == a.id ? b : a
    selected.metadata.merge(abandoned.metadata) { (cur, _) in cur }
    return selected
}

fileprivate func mergeAlbums(_ a: Album, _ tracksA: [Track], _ b: Album, _ tracksB: [Track]) -> Album? {
    guard let titleA = a.metadata[MetadataCommonKey.title] else { return nil }
    guard let titleB = b.metadata[MetadataCommonKey.title] else { return nil }
    guard titleA == titleB else { return nil }
    var artistA = a.metadata[MetadataCommonKey.artist]
    var artistB = b.metadata[MetadataCommonKey.artist]
    if artistA != nil && artistB == nil {
        artistB = commonMetadata(tracksB, for: MetadataCommonKey.artist)
    }
    if artistA == nil && artistB != nil {
        artistA = commonMetadata(tracksA, for: MetadataCommonKey.artist)
    }
    guard artistA == artistB else { return nil }
    for trackA in tracksA {
        if tracksB.contains(where: { trackB in
            if let trackNumberA = trackA.metadata[MetadataCommonKey.trackNumber].flatMap({ Int($0) }),
               let trackNumberB = trackB.metadata[MetadataCommonKey.trackNumber].flatMap({ Int($0) }) {
                if trackNumberA == trackNumberB {
                    if let discNumberA = trackA.metadata[MetadataCommonKey.discNumber].flatMap({ Int($0) }),
                       let discNumberB = trackB.metadata[MetadataCommonKey.discNumber].flatMap({ Int($0) }) {
                        return discNumberA == discNumberB
                    } else {
                        return true
                    }
                } else {
                    return false
                }
            }
            if trackA.metadata[MetadataCommonKey.title] == trackB.metadata[MetadataCommonKey.title] {
                return true
            }
            return false
        }) {
            return nil
        }
        if tracksB.contains(where: { trackB in
            guard trackA.metadata[MetadataCommonKey.encoder] == trackB.metadata[MetadataCommonKey.encoder] else {
                return true
            }
            guard trackA.metadata[MetadataCommonKey.organization] == trackB.metadata[MetadataCommonKey.organization] else {
                return true
            }
            guard trackA.metadata[MetadataCommonKey.date] == trackB.metadata[MetadataCommonKey.date] else {
                return true
            }
            guard trackA.metadata["YEAR"] == trackB.metadata["YEAR"] else {
                return true
            }
            return false
        }) {
            return nil
        }
    }
    let selected = a.id < b.id ? a : b
    let abandoned = selected.id == a.id ? b : a
    selected.metadata.merge(abandoned.metadata) { (cur, _) in cur }
    for track in tracksA + tracksB {
        track.albumId = selected.id
    }
    return selected
}

fileprivate func commonMetadata(_ tracks: [Track], for key: String) -> String? {
    var values = Set<String>()
    for track in tracks {
        if let value = track.metadata[key] {
            values.insert(value)
        }
    }
    if values.count == 1 {
        return values.first!
    } else {
        return nil
    }
}

fileprivate class CueSheetImporter: MediaImporter {
    let supportedTypes = [UTType("io.misakikasumi.Loop3000.CueSheet")!]

    private static let linePartRegex = /(".+?"|.+?)\s+/

    private func fuzzyMatch(url: URL) throws -> URL? {
        let fileManager = FileManager.default
        let peers = try fileManager.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: [])
        var candidates: [URL] = []
        for grabber in metadataGrabbers {
            candidates.append(contentsOf: peers.filter { url in
                guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
                return grabber.supportedTypes.contains { type.conforms(to: $0) }
            })
        }
        return candidates
            .compactMap { candidate -> (URL, Int)? in
                let expectedStem = url.deletingPathExtension().lastPathComponent
                let candidateStem = candidate.deletingPathExtension().lastPathComponent
                let expectedWords = expectedStem.split { !$0.isLetter }
                let candidateWords = candidateStem.split { !$0.isLetter }
                guard !expectedWords.isEmpty && !candidateWords.isEmpty else { return nil }
                if expectedWords.filter({ candidateWords.contains($0) }) == candidateWords {
                    return (candidate, expectedWords.count - candidateWords.count)
                }
                if candidateWords.filter({ expectedWords.contains($0) }) == expectedWords {
                    return (candidate, candidateWords.count - expectedWords.count)
                }
                return nil
            }
            .sorted { $0.1 < $1.1 }
            .first
            .map { $0.0 }
    }

    func importMedia(url: URL, tracer: RequestTracer?) async throws -> (albums: [Album], tracks: [Track]) {
        let content = try readString(from: url)
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
                    guard let matchedFile = try fuzzyMatch(url: file) else {
                        throw FileNotFound(url: file)
                    }
                    file = matchedFile
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
                    tracer?.add(url)
                    defer { tracer?.remove(url) }
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

fileprivate class AVImporter: MediaImporter {
    let supportedTypes = [UTType.audio]

    func importMedia(url: URL, tracer: RequestTracer?) async throws -> (albums: [Album], tracks: [Track]) {
        tracer?.add(url)
        defer { tracer?.remove(url) }
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let album = Album()
        let track = Track(source: url, start: .zero, end: Timestamp(from: duration), albumId: album.id)
        return (albums: [album], tracks: [track])
    }
}

fileprivate struct DataReader {
    private var data: Data
    private var position: Int

    mutating func read(count: Int) -> Data? {
        guard position + count <= data.count else { return nil }
        let buffer = data[position ..< position + count]
        position += count
        return buffer
    }

    init(_ data: Data) {
        precondition(data.startIndex == 0 && data.endIndex == data.count)
        self.data = data
        self.position = 0
    }
}

fileprivate class FLACGrabber: MetadataGrabber {
    let supportedTypes = [UTType("org.xiph.flac")!]

    private func parse32bitIntLE(_ data: Data) -> Int {
        let d = Data(data)
        precondition(d.count == 4)
        return Int(d[0]) | Int(d[1] << 8) | Int(d[2] << 16) | Int(d[3] << 24)
    }

    func grabMetadata(url: URL, tracer: RequestTracer?) async throws -> Metadata {
        tracer?.add(url)
        defer { tracer?.remove(url) }
        let invalid = InvalidFormat(url: url)
        var reader = DataReader(try readData(from: url))
        if reader.read(count: 4) != Data([0x66, 0x4C, 0x61, 0x43]) { throw invalid }
        var last = false
        var metadata = Metadata()
        repeat {
            guard let header = reader.read(count: 4).map({ Data($0) }) else { throw invalid }
            last = (header[0] >> 7) != 0
            let type = header[0] & 0x7f
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            switch type {
            case 4: // VORBIS_COMMENT
                guard let vendorStringLength = reader.read(count: 4).map({ parse32bitIntLE($0) }) else { throw invalid }
                guard let vendorString = reader.read(count: vendorStringLength) else { throw invalid }
                metadata[MetadataCommonKey.encoder] = String(data: vendorString, encoding: .utf8)
                guard let vectorLength = reader.read(count: 4).map({ parse32bitIntLE($0) }) else { throw invalid }
                var totalReadCount = 8 + vendorStringLength
                for _ in 0 ..< vectorLength {
                    guard let commentLength = reader.read(count: 4).map({ parse32bitIntLE($0) }) else { throw invalid }
                    guard let data = reader.read(count: commentLength) else { throw invalid }
                    totalReadCount += 4 + commentLength
                    guard let comment = String(data: data, encoding: .utf8) else { continue }
                    let parts = comment.split(separator: "=", maxSplits: 2)
                    if parts.count == 2 && parts[1] != " " {
                        let (key, value) = (parts[0].uppercased(), String(parts[1]))
                        metadata[key] = value
                    }
                }
                if totalReadCount != length { throw invalid }
                // We got what we need
                last = true
            default:
                guard reader.read(count: length) != nil else { throw invalid }
            }
        } while !last
        return metadata
    }
}

fileprivate class AVGrabber: MetadataGrabber {
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

    func grabMetadata(url: URL, tracer: RequestTracer?) async throws -> Metadata {
        tracer?.add(url)
        defer { tracer?.remove(url) }
        let asset = AVURLAsset(url: url)
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

protocol ArtworkLoader {
    var supportedTypes: [UTType] { get }

    func loadCover(from url: URL, tracer: RequestTracer?) async throws -> CGImage?
}

var artworkLoaders: [any ArtworkLoader] = [CGArtworkLoader()]

fileprivate let scaler = Scaler()

func loadImage(from data: Data) -> CGImage {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    return image
}

extension Shelf {
    private func loadOriginalArtwork(for album: Album, tracer: RequestTracer? = nil) async throws -> CGImage? {
        let tracks = getTracks(for: album)
        let firstTrack = sorted(tracks: tracks).first!
        if firstTrack.source.isFileURL {
            let fileManager = FileManager.default
            let directory = firstTrack.source.deletingLastPathComponent()
            let children = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [])
                .filter { $0.deletingPathExtension().lastPathComponent.lowercased() == "cover" }
            for loader in artworkLoaders {
                guard let image = children.first(where: { url in
                    guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
                    return loader.supportedTypes.contains { type.conforms(to: $0) }
                }) else { continue }
                guard let cgImage = try await loader.loadCover(from: image, tracer: tracer) else { continue }
                return cgImage
            }
        }
        let type = UTType(filenameExtension: firstTrack.source.pathExtension)!
        for loader in artworkLoaders {
            guard loader.supportedTypes.contains(where: { type.conforms(to: $0) }) else { continue }
            guard let cgImage = try await loader.loadCover(from: firstTrack.source, tracer: tracer) else { continue }
            return cgImage
        }
        return nil
    }

    func loadAllArtworks(tracer: RequestTracer? = nil) async -> [Error] {
        let (images, errors) = await withTaskGroup(of: (Album, CGImage?, Error?).self) { taskGroup in
            for album in albums {
                if album.cover == nil {
                    taskGroup.addTask {
                        do {
                            return (album, try await loadOriginalArtwork(for: album, tracer: tracer), nil)
                        } catch let error {
                            return (album, nil, error)
                        }
                    }
                }
            }
            var errors: [Error] = []
            var images: [(Album, CGImage)] = []
            for await item in taskGroup {
                item.1.map { images.append((item.0, $0)) }
                item.2.map { errors.append($0) }
            }
            return (images, errors)
        }
        let originalImages = images.map { $0.1 }
        let scaledImages = await scaler.scale(images: originalImages.map { CIImage(cgImage: $0) }, to: originalImages.map { image in
            let newWidth = 600
            let newHeight = image.height * 600 / image.width
            return Scaler.Resolution(width: newWidth, height: newHeight)
        })
        let cictx = scaler.cictx
        await withTaskGroup(of: Void.self) { taskGroup in
            for (album, image) in zip(images.map { $0.0 }, scaledImages) {
                taskGroup.addTask {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().async {
                            album.cover = cictx.heifRepresentation(
                                of: image,
                                format: .BGRA8,     // I did not figure out what this argument means.
                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                options: [.init(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.75]
                            )!
                            continuation.resume()
                        }
                    }
                }
            }
            await taskGroup.reduce((), { (_, _) in () })
        }
        return errors
    }
}

class CGArtworkLoader: ArtworkLoader {
    let supportedTypes = [UTType.jpeg, UTType.png]

    private let cictx = CIContext()

    func loadCover(from url: URL, tracer: RequestTracer? = nil) async throws -> CGImage? {
        tracer?.add(url)
        defer { tracer?.remove(url) }
        let type = UTType(filenameExtension: url.pathExtension)!
        guard let dataProvider = CGDataProvider(url: url as CFURL) else {
            throw FileNotFound(url: url)
        }
        guard let image = type.conforms(to: .jpeg)
            ? CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
            : CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else {
            throw InvalidFormat(url: url)
        }
        return image
    }
}
