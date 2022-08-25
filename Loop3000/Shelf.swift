import Foundation
import CoreGraphics
import CoreImage
import AVFoundation
import UniformTypeIdentifiers
import Collections

struct CueTime: Equatable {
    var value: Int

    static let timescale = 75

    static let zero = CueTime(value: 0)
    static let invalid = CueTime(valueUnchecked: -1)
    static let indefinite = CueTime(valueUnchecked: -2)
    static let negativeInfinity = CueTime(valueUnchecked: -3)
    static let positiveInfinity = CueTime(valueUnchecked: -4)

    var isValid: Bool {
        value >= 0
    }

    fileprivate init() {
        self = Self.invalid
    }

    init(value: Int) {
        precondition(value >= 0)
        self.value = value
    }

    private init(valueUnchecked: Int) {
        self.value = valueUnchecked
    }

    init?(minutes: Int, seconds: Int, frames: Int) {
        guard minutes >= 0 && seconds >= 0 && frames >= 0 else { return nil }
        guard frames < Self.timescale else { return nil }
        guard seconds < 60 else { return nil }
        let totalSeconds = minutes * 60 + seconds
        let totalFrames = totalSeconds * Self.timescale + frames
        self.init(value: totalFrames)
    }

    init?(from s: String) {
        guard let match = try? /(\d\d):(\d\d):(\d\d)/.wholeMatch(in: s) else { return nil }
        self.init(minutes: Int(match.1)!, seconds: Int(match.2)!, frames: Int(match.3)!)
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

extension CueTime: CustomStringConvertible {
    var description: String {
        String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }
}

extension CueTime {
    var shortDescription: String {
        String(format: "%02d:%02d", minutes, seconds + (frames > Self.timescale / 2 ? 1 : 0))
    }
}

extension CueTime {
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
            self.init(value: Int(time.value) * CueTime.timescale / Int(time.timescale))
        }
    }
}

extension CMTime {
    init(from timestamp: CueTime) {
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
            self.init(value: CMTimeValue(timestamp.value), timescale: CMTimeScale(CueTime.timescale))
        }
    }
}

extension CueTime {
    static func difference(_ lhs: CueTime, _ rhs: CueTime) -> CueTime? {
        guard lhs.isValid && rhs.isValid else { return nil }
        guard lhs >= rhs else { return nil }
        return CueTime(value: lhs.value - rhs.value)
    }

    static func distance(_ lhs: CueTime, _ rhs: CueTime) -> CueTime? {
        guard lhs.isValid && rhs.isValid else { return nil }
        return CueTime(value: abs(lhs.value - rhs.value))
    }
}

extension CueTime: Comparable {
    static func <(lhs: CueTime, rhs: CueTime) -> Bool {
        if lhs.isValid && rhs.isValid {
            return lhs.value < rhs.value
        } else {
            switch (lhs, rhs) {
            case (.invalid, _): fallthrough
            case (_, .invalid): fallthrough
            case (.indefinite, _): fallthrough
            case (_, .indefinite):
                fatalError("Non-comparable")
            case (.negativeInfinity, .positiveInfinity):
                return true
            case (let l, .positiveInfinity) where l.isValid:
                return true
            case (.negativeInfinity, let r) where r.isValid:
                return true
            default:
                return false
            }
        }
    }
}

extension CueTime: Codable {
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

struct MetadataCommonKey {
    let title = "TITLE"
    let version = "VERSION"
    let album = "ALBUM"
    let trackNumber = "TRACKNUMBER"
    let discNumber = "DISCNUMBER"
    let artist = "ARTIST"
    let albumArtist = "ALBUMARTIST"
    let performer = "PERFORMER"
    let composer = "COMPOSER"
    let author = "AUTHOR"
    let contributor = "CONTRIBUTOR"
    let creator = "CREATOR"
    let publisher = "PUBLISHER"
    let copyright = "COPYRIGHT"
    let license = "LICENSE"
    let organization = "ORGANIZATION"
    let description = "DESCRIPTION"
    let genre = "GENRE"
    let date = "DATE"
    let language = "LANGUAGE"
    let location = "LOCATION"
    let ISRC = "ISRC"
    let comment = "COMMENT"
    let encoder = "ENCODER"
}

fileprivate let metadataCommonKey = MetadataCommonKey()

struct Metadata {
    private var metadata: [String: String] = [:]

    subscript(key: String) -> String? {
        get {
            metadata[key]
        }
        set(newValue) {
            metadata[key] = newValue
        }
    }

    subscript(key: KeyPath<MetadataCommonKey, String>) -> String? {
        get {
            metadata[metadataCommonKey[keyPath: key]]
        }
        set(newValue) {
            metadata[metadataCommonKey[keyPath: key]] = newValue
        }
    }
}

extension Metadata: Sequence {
    typealias Element = (key: String, value: String)
    typealias Iterator = Dictionary<String, String>.Iterator
    func makeIterator() -> Iterator {
        metadata.makeIterator()
    }
}

extension Metadata {
    mutating func merge(_ other: Metadata, uniquingKeysWith combine: (String, String) throws -> String) rethrows {
        try metadata.merge(other.metadata, uniquingKeysWith: combine)
    }
}

extension Metadata: Codable {
    func encode(to encoder: Encoder) throws {
        try metadata.encode(to: encoder)
    }

    init(from decoder: Decoder) throws {
        metadata = try [String: String](from: decoder)
    }
}

struct Album: EquatableIdentifiable, Codable {
    private(set) var id = makeMonotonicUUID()
    var metadata = Metadata()
    var cover: Data?
}

struct Track: EquatableIdentifiable, Codable {
    private(set) var id = UUID()
    var source: URL
    var start: CueTime
    var end: CueTime
    var albumId: UUID
    var metadata = Metadata()
}

struct PlaylistItem: EquatableIdentifiable, Codable {
    private(set) var id = UUID()
    var trackId: UUID
}

struct Playlist: EquatableIdentifiable, Codable {
    private(set) var id = UUID()
    var title: String
    var items: [PlaylistItem]
}

struct DiscoverLogItem: Codable {
    enum Action: Hashable, Codable {
        case discovering
        case importing
        case grabbing
    }
    let action: Action
    let url: URL
    let bookmark: Data
    let date: Date
}

struct DiscoverLog: Codable {
    var items: [DiscoverLogItem]
    static let empty = DiscoverLog(items: [])
}

struct Shelf: Codable {
    var albums: [Album] = []
    var tracks: [Track] = []
    var manualPlaylists: [Playlist] = []
    var discoverLog = DiscoverLog.empty

    func getTracks(for album: Album) -> [Track] {
        tracks.filter { $0.albumId == album.id }
    }

    func getAlbum(for track: Track) -> Album {
        albums.get(by: track.albumId)!
    }

    fileprivate mutating func modifyTracks(for album: Album, transform: (Track) -> Track) {
        for (i, track) in tracks.enumerated() {
            if track.albumId == album.id {
                tracks[i] = transform(track)
            }
        }
    }

    func sorted(tracks: [Track]) -> [Track] {
        return tracks.sorted {
            if $0.albumId != $1.albumId {
                let albumL = getAlbum(for: $0)
                let albumR = getAlbum(for: $1)
                let albumTitleL = albumL.metadata[\.title]
                let albumTitleR = albumR.metadata[\.title]
                if albumTitleL != albumTitleR {
                    if albumTitleL == nil { return false }
                    if albumTitleR == nil { return true }
                    return albumTitleL! < albumTitleR!
                }
                return $0.albumId < $1.albumId
            }
            let discNumberL = $0.metadata[\.discNumber].flatMap { Int($0) }
            let discNumberR = $1.metadata[\.discNumber].flatMap { Int($0) }
            if discNumberL != discNumberR {
                if discNumberL == nil { return false }
                if discNumberR == nil { return true }
                return discNumberL! < discNumberR!
            }
            let trackNumberL = $0.metadata[\.trackNumber].flatMap { Int($0) }
            let trackNumberR = $1.metadata[\.trackNumber].flatMap { Int($0) }
            if trackNumberL != trackNumberR {
                if trackNumberL == nil { return false }
                if trackNumberR == nil { return true }
                return trackNumberL! < trackNumberR!
            }
            if $0.source.absoluteString != $1.source.absoluteString {
                return $0.source.absoluteString < $1.source.absoluteString
            }
            return $0.start < $1.start
        }
    }

    func sorted(albums: [Album]) -> [Album] {
        albums.sorted { (albumL, albumR) in
            let albumTitleL = albumL.metadata[\.title]
            let albumTitleR = albumR.metadata[\.title]
            if albumTitleL != albumTitleR {
                if albumTitleL == nil { return false }
                if albumTitleR == nil { return true }
                return albumTitleL! < albumTitleR!
            }
            return albumL.id < albumR.id
        }
    }

    mutating func consolidateMetadata() {
        for i in 0 ..< albums.count {
            var album = albums[i]
            let tracks = getTracks(for: album)
            if tracks.count < 2 { continue }
            var mergedKeys: [String] = []
            for (key, _) in tracks.first!.metadata {
                switch key {
                case
                    metadataCommonKey.trackNumber,
                    metadataCommonKey.discNumber,
                    metadataCommonKey.ISRC,
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
                            mergedKeys.append(key)
                        }
                    }
                }
            }
            albums[i] = album
            if !mergedKeys.isEmpty {
                modifyTracks(for: album) {
                    var track = $0
                    for key in mergedKeys {
                        track.metadata[key] = nil
                    }
                    return track
                }
            }
        }
    }

    mutating func merge(with other: Shelf) {
        self = mergeShelf(self, other)
    }

    func activate() {
        for logItem in discoverLog.items {
            guard let url = try? loadURLFromBookmark(logItem.bookmark) else { continue }
            assert(url.absoluteURL == logItem.url.absoluteURL)
        }
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

var mediaImporters: [any MediaImporter] = [CueSheetImporter(), AVAssetImporter()]
var metadataGrabbers: [any MetadataGrabber] = [FLACGrabber(), AVAssetGrabber()]

struct NoApplicableImporter: Error {
    let url: URL
}

struct DiscoverResult {
    var albums: [Album]
    var tracks: [Track]
    var log: DiscoverLog
    var errors: [Error]
    static let empty = DiscoverResult(albums: [], tracks: [], log: .empty, errors: [])

    mutating func merge(with other: Self) {
        albums.append(contentsOf: other.albums)
        tracks.append(contentsOf: other.tracks)
        log.merge(with: other.log)
        errors.append(contentsOf: other.errors)
    }
}

fileprivate extension DiscoverLog {
    func needsRediscover(action: DiscoverLogItem.Action, url: URL) -> Bool {
        guard let logItem = items.first(where: { $0.url.absoluteURL == url.absoluteURL }) else {
            return true
        }
        guard let mtime = try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate else {
            return true
        }
        return mtime > logItem.date
    }

    mutating func log(action: DiscoverLogItem.Action, url: URL) {
        items.append(DiscoverLogItem(action: action, url: url, bookmark: try! dumpURLToBookmark(url), date: Date.now))
    }

    mutating func merge(with other: Self) {
        struct Key: Hashable {
            var action: DiscoverLogItem.Action
            var url: URL
        }
        var pool = OrderedDictionary<Key, DiscoverLogItem>()
        for item in items + other.items {
            let key = Key(action: item.action, url: item.url.absoluteURL)
            if let oitem = pool[key] {
                if item.date < oitem.date {
                    continue
                }
            }
            pool[key] = item
        }
        items = pool.values.elements
    }
}

func discover(
    at url: URL,
    recursive: Bool = false,
    previousLog: DiscoverLog = .empty,
    tracer: RequestTracer?
) async -> DiscoverResult {
    var r = DiscoverResult.empty
    if url.isDirectory == true {
        r.log.log(action: .discovering, url: url)
        let fileManager = FileManager.default
        var children = Set(((try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: .skipsHiddenFiles
        )) ?? []).map { $0.absoluteURL })
        for importer in mediaImporters {
            let applicableFiles = children.filter { $0.conformsAny(to: importer.supportedTypes) }
            await withTaskGroup(of: DiscoverResult.self) { taskGroup in
                for url in applicableFiles {
                    taskGroup.addTask {
                        await discover(at: url, recursive: false, previousLog: previousLog, tracer: tracer)
                    }
                }
                for await rv in taskGroup {
                    r.merge(with: rv)
                }
            }
            children.subtract(applicableFiles)
            children.subtract(r.tracks.map { $0.source.absoluteURL })
        }
        if recursive {
            await withTaskGroup(of: DiscoverResult.self) { taskGroup in
                for child in children {
                    if child.isDirectory == true {
                        taskGroup.addTask {
                            await discover(at: child, recursive: true, previousLog: previousLog, tracer: tracer)
                        }
                    }
                }
                for await rv in taskGroup {
                    r.merge(with: rv)
                }
            }
        }
    } else {
        guard let importer = mediaImporters.first(where: {
            url.conformsAny(to: $0.supportedTypes)
        }) else {
            r.errors.append(NoApplicableImporter(url: url))
            return r
        }
        if !previousLog.needsRediscover(action: .importing, url: url) {
            return r
        } else {
            r.log.log(action: .importing, url: url)
        }
        var albums: [Album] = []
        var tracks: [Track] = []
        do {
            (albums, tracks) = try await importer.importMedia(url: url, tracer: tracer)
        } catch let error {
            r.errors.append(error)
            return r
        }
        let sources = Set(tracks.map { $0.source.absoluteURL })
        var metadatas = [URL: Metadata]()
        await withTaskGroup(of: (source: URL, metadata: Metadata?, error: Error?).self) { taskGroup in
            for source in sources {
                guard let grabber = metadataGrabbers.first(where: {
                    source.conformsAny(to: $0.supportedTypes)
                }) else { continue }
                if !previousLog.needsRediscover(action: .grabbing, url: source) {
                    continue
                } else {
                    r.log.log(action: .grabbing, url: source)
                }
                taskGroup.addTask {
                    do {
                        return (source: source, metadata: try await grabber.grabMetadata(url: source, tracer: tracer), error: nil)
                    } catch let error {
                        return (source: source, metadata: nil, error: error)
                    }
                }
            }
            for await item in taskGroup {
                if let metadata = item.metadata {
                    metadatas[item.source] = metadata
                }
                if let error = item.error {
                    r.errors.append(error)
                }
            }
        }
        tracks = tracks.map {
            var track = $0
            if let metadata = metadatas[track.source] {
                track.metadata.merge(metadata) { (_, new) in new }
            }
            let albumTitle = track.metadata[\.album]
            let albumArtist = track.metadata[\.albumArtist]
            if albumTitle != nil || albumArtist != nil {
                for i in 0 ..< albums.count {
                    var album = albums[i]
                    if album.id == track.albumId {
                        if let albumTitle {
                            album.metadata[\.title] = albumTitle
                        }
                        if let albumArtist {
                            album.metadata[\.artist] = albumArtist
                        }
                        albums[i] = album
                        break
                    }
                }
            }
            track.metadata[\.album] = nil
            track.metadata[\.albumArtist] = nil
            return track
        }
        r.albums = albums
        r.tracks = tracks
    }
    return r
}

fileprivate func mergeShelf(_ a: Shelf, _ b: Shelf) -> Shelf {
    var mergedShelf = Shelf()

    var trackIdMap: [UUID: UUID] = [:]
    var unconsolidatedTracks = a.tracks + b.tracks
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
    var unconsolidatedAlbums = (a.albums + b.albums).filter { usedAlbumIds.contains($0.id) }
    unconsolidatedAlbums.reverse()
    var consolidatedAlbums: [Album] = []
    while var album = unconsolidatedAlbums.popLast() {
        unconsolidatedAlbums = unconsolidatedAlbums.compactMap { otherAlbum in
            guard let mergedAlbum = mergeAlbums(
                album,
                mergedShelf.getTracks(for: album),
                otherAlbum,
                mergedShelf.getTracks(for: otherAlbum)
            ) else { return otherAlbum }
            mergedShelf.tracks = mergedShelf.tracks
                .map {
                    var track = $0
                    if track.albumId == album.id || track.albumId == otherAlbum.id {
                        track.albumId = mergedAlbum.id
                    }
                    return track
                }
            album = mergedAlbum
            return nil
        }
        consolidatedAlbums.append(album)
    }
    mergedShelf.albums = consolidatedAlbums

    let unconsolidatedPlaylists = a.manualPlaylists + b.manualPlaylists
    let consolidatedPlaylists = unconsolidatedPlaylists.map {
        var playlist = $0
        playlist.items = playlist.items.map {
            var item = $0
            item.trackId = trackIdMap[item.trackId]!
            return item
        }
        return playlist
    }
    mergedShelf.manualPlaylists = consolidatedPlaylists

    mergedShelf.discoverLog = a.discoverLog
    mergedShelf.discoverLog.merge(with: b.discoverLog)

    return mergedShelf
}

fileprivate func mergeTracks(_ a: Track, _ b: Track) -> Track? {
    guard a.source.absoluteURL == b.source.absoluteURL else { return nil }
    guard abs(a.start.value - b.start.value) < 500 || !a.start.isValid || !b.start.isValid else { return nil }
    guard abs(a.end.value - b.end.value) < 500 || !a.end.isValid || !b.end.isValid else { return nil }
    let durationA = a.start.isValid && a.end.isValid ? a.end.value - a.start.value : .max
    let durationB = b.start.isValid && b.end.isValid ? b.end.value - b.start.value : .max
    var selected = durationA == durationB ? (a.albumId < b.albumId ? a : b) : (durationA < durationB ? a : b)
    let abandoned = selected.id == a.id ? b : a
    selected.metadata.merge(abandoned.metadata) { (cur, _) in cur }
    return selected
}

fileprivate func mergeAlbums(_ a: Album, _ tracksA: [Track], _ b: Album, _ tracksB: [Track]) -> Album? {
    guard let titleA = a.metadata[\.title] else { return nil }
    guard let titleB = b.metadata[\.title] else { return nil }
    guard titleA == titleB else { return nil }
    var artistA = a.metadata[\.artist]
    var artistB = b.metadata[\.artist]
    if artistA != nil && artistB == nil {
        artistB = commonMetadata(tracksB, for: metadataCommonKey.artist)
    }
    if artistA == nil && artistB != nil {
        artistA = commonMetadata(tracksA, for: metadataCommonKey.artist)
    }
    guard artistA == artistB else { return nil }
    for trackA in tracksA {
        if tracksB.contains(where: { trackB in
            if let trackNumberA = trackA.metadata[\.trackNumber].flatMap({ Int($0) }),
               let trackNumberB = trackB.metadata[\.trackNumber].flatMap({ Int($0) }) {
                if trackNumberA == trackNumberB {
                    if let discNumberA = trackA.metadata[\.discNumber].flatMap({ Int($0) }),
                       let discNumberB = trackB.metadata[\.discNumber].flatMap({ Int($0) }) {
                        return discNumberA == discNumberB
                    } else {
                        return true
                    }
                } else {
                    return false
                }
            }
            if trackA.metadata[\.title] == trackB.metadata[\.title] {
                return true
            }
            return false
        }) {
            return nil
        }
        if tracksB.contains(where: { trackB in
            guard trackA.metadata[\.encoder] == trackB.metadata[\.encoder] else {
                return true
            }
            guard trackA.metadata[\.organization] == trackB.metadata[\.organization] else {
                return true
            }
            guard trackA.metadata[\.date] == trackB.metadata[\.date] else {
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
    var selected = a.id < b.id ? a : b
    let abandoned = selected.id == a.id ? b : a
    selected.metadata.merge(abandoned.metadata) { (cur, _) in cur }
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
        var album = Album()
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
                if currentTrack != nil {
                    currentTrack!.metadata[key] = value
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
                      let timestamp = CueTime(from: params[1])
                else {
                    throw InvalidFormat(url: url)
                }
                switch number {
                case 0:
                    if let previousTrack = tracks.last, previousTrack.source == track.source {
                        tracks[tracks.count - 1].end = timestamp
                    }
                case 1:
                    currentTrack!.source = file
                    currentTrack!.start = timestamp
                    if let previousTrack = tracks.last,
                       previousTrack.source == track.source && previousTrack.end == .invalid {
                        tracks[tracks.count - 1].end = timestamp
                    }
                default:
                    ()
                }
            case ("SONGWRITER", 1):
                setMetadata(for: metadataCommonKey.composer)
            case ("ISRC", 1):
                setMetadata(for: metadataCommonKey.ISRC)
            case ("PERFORMER", 1):
                setMetadata(for: metadataCommonKey.artist)
            case ("TITLE", 1):
                setMetadata(for: metadataCommonKey.title)
            case ("REM", 2):
                switch params[0] {
                case "DATE":
                    setMetadata(params[1], for: metadataCommonKey.date)
                case "COMPOSER":
                    setMetadata(params[1], for: metadataCommonKey.composer)
                case "GENRE":
                    setMetadata(params[1], for: metadataCommonKey.genre)
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
        let sourcesNeedDuration = Set(tracks
            .filter { !$0.end.isValid }
            .map { $0.source.absoluteURL }
        )
        let durations = try await withThrowingTaskGroup(of: (url: URL, duration: CueTime).self) { taskGroup in
            for source in sourcesNeedDuration {
                taskGroup.addTask {
                    tracer?.add(url)
                    defer { tracer?.remove(url) }
                    let asset = AVAsset(url: source)
                    let duration = try await asset.load(.duration)
                    return (url: source, duration: CueTime(from: duration))
                }
            }
            var durations: [URL: CueTime] = [:]
            for try await item in taskGroup {
                durations[item.url] = item.duration
            }
            return durations
        }
        tracks = tracks
            .map {
                var track = $0
                if !track.end.isValid {
                    track.end = durations[track.source.absoluteURL]!
                }
                return track
            }
        for i in 0 ..< tracks.count {
            tracks[i].metadata[\.trackNumber] = String(i + 1)
            tracks[i].metadata[\.discNumber] = discNumber.map { String($0) }
        }
        return (albums: [album], tracks: tracks)
    }
}

fileprivate class AVAssetImporter: MediaImporter {
    let supportedTypes = [UTType.audio]

    func importMedia(url: URL, tracer: RequestTracer?) async throws -> (albums: [Album], tracks: [Track]) {
        tracer?.add(url)
        defer { tracer?.remove(url) }
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        let album = Album()
        let track = Track(source: url, start: .zero, end: CueTime(from: duration), albumId: album.id)
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
                metadata[\.encoder] = String(data: vendorString, encoding: .utf8)
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

fileprivate class AVAssetGrabber: MetadataGrabber {
    let supportedTypes = [UTType.audio]

    private static let keyMapping: [AVMetadataKey: String] = [
        .commonKeyAlbumName: metadataCommonKey.album,
        .commonKeyArtist: metadataCommonKey.artist,
        .commonKeyAuthor: metadataCommonKey.author,
        .commonKeyContributor: metadataCommonKey.contributor,
        .commonKeyCopyrights: metadataCommonKey.copyright,
        .commonKeyCreator: metadataCommonKey.creator,
        .commonKeyTitle: metadataCommonKey.title,
        .commonKeyDescription: metadataCommonKey.description,
        .commonKeyLanguage: metadataCommonKey.language,
        .commonKeyLocation: metadataCommonKey.location,
        .commonKeyPublisher: metadataCommonKey.publisher,
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

    mutating func loadAllArtworks(tracer: RequestTracer? = nil) async -> [Error] {
        let (images, errors) = await withTaskGroup(of: (Album, CGImage?, Error?).self) { taskGroup in
            for album in albums {
                if album.cover == nil {
                    let this = self
                    taskGroup.addTask {
                        do {
                            return (album, try await this.loadOriginalArtwork(for: album, tracer: tracer), nil)
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
        await withTaskGroup(of: (Album, Data).self) { taskGroup in
            for (album, image) in zip(images.map { $0.0 }, scaledImages) {
                taskGroup.addTask {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().async {
                            continuation.resume(returning: (album, cictx.heifRepresentation(
                                of: image,
                                format: .BGRA8,     // I did not figure out what this argument means.
                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                options: [.init(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.75]
                            )!))
                        }
                    }
                }
            }
            for await (album, cover) in taskGroup {
                albums[albums.firstIndex(of: album)!].cover = cover
            }
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
