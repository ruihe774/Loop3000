import Foundation
import AppKit
import Combine
import MediaPlayer
import UniformTypeIdentifiers
import Atomics

fileprivate struct ObservableRequestChoker: RequestChoker {
    private var counter = ManagedAtomic<Int>(16)

    private func tryAcquire() -> Bool {
        let current = counter.load(ordering: .acquiring)
        if current == 0 {
            return false
        }
        return counter.compareExchange(
            expected: current,
            desired: current - 1,
            successOrdering: .acquiring,
            failureOrdering: .relaxed
        ).exchanged
    }

    private func release() {
        counter.wrappingIncrement(ordering: .releasing)
    }

    func add(_ url: URL) async {
        var tick = 0
        while !tryAcquire() {
            if tick < 10 {
                await Task.yield()
            } else {
                try! await Task.sleep(nanoseconds: 1000000)
            }
            tick += 1
        }
        adding.send(url)
    }

    func remove(_ url: URL) {
        release()
        removing.send(url)
    }

    var adding: PassthroughSubject<URL, Never>
    var removing: PassthroughSubject<URL, Never>

    init(adding: PassthroughSubject<URL, Never>, removing: PassthroughSubject<URL, Never>) {
        self.adding = adding
        self.removing = removing
    }
}

@MainActor
class MusicLibrary: ObservableObject {
    @Published private var shelf = Shelf()
    @Published private(set) var albums: [UUID: Album] = [:]
    @Published private(set) var tracks: [UUID: Track] = [:]
    @Published private(set) var albumPlaylists: [Playlist] = []
    @Published private(set) var manualPlaylists: [Playlist] = []
    @Published private(set) var playlists: [UUID: Playlist] = [:]
    @Published private(set) var playlistItemLocation: [UUID: (Playlist, PlaylistItem)] = [:]

    @Published private(set) var importedAlbums: [Album] = []
    @Published private(set) var importedTracks: [Track] = []
    @Published private(set) var returnedErrors: [Error] = []
    @Published private(set) var requesting: [URL] = []
    @Published private(set) var processing = false
    private let queue = SerialAsyncQueue()
    private let choker = ObservableRequestChoker(adding: PassthroughSubject(), removing: PassthroughSubject())

    private var ac: [Cancellable] = []
    private var syncAc: Cancellable?

    init() {
        $shelf
            .map { $0.albums }
            .map { $0.makeDictionary() }
            .assign(to: &$albums)

        $shelf
            .map { $0.tracks }
            .map { $0.makeDictionary() }
            .assign(to: &$tracks)

        $shelf
            .map { $0.manualPlaylists }
            .assign(to: &$manualPlaylists)

        $shelf
            .map { shelf in
                shelf.sorted(albums: shelf.albums).map { album in
                    Playlist(
                        id: album.id,
                        title: album.metadata[\.title] ?? "<No Title>",
                        items: shelf.sorted(tracks: shelf.getTracks(for: album)).map {
                            PlaylistItem(
                                id: $0.id,
                                trackId: $0.id
                            )
                        }
                    )
                }
            }
            .assign(to: &$albumPlaylists)

        Publishers.Zip($albumPlaylists, $manualPlaylists)
            .map { $0 + $1 }
            .map { $0.makeDictionary() }
            .assign(to: &$playlists)

        $playlists
            .map {
                Dictionary(uniqueKeysWithValues: $0.values
                    .flatMap { list in
                        list.items.map { item in
                            (item.id, (list, item))
                        }
                    }
                )
            }
            .assign(to: &$playlistItemLocation)

        ac.append(choker.adding
            .receiveOnMain()
            .sink { [unowned self] url in
                requesting.append(url)
            }
        )

        ac.append(choker.removing
            .receiveOnMain()
            .sink { [unowned self] url in
                if let index = requesting.lastIndex(of: url) {
                    requesting.remove(at: index)
                }
            }
        )
    }

    func performDiscover(at url: URL) {
        queue.enqueue {
            let oldShelf = await MainActor.run {
                self.processing = true
                return self.shelf
            }
            let (shelf, albums, tracks, errors) = await {
                let result = await discover(at: url, recursive: true, previousLog: oldShelf.discoverLog, choker: self.choker)
                let albums = result.albums
                let tracks = result.tracks
                let log = result.log
                var errors = result.errors
                var newShelf = oldShelf
                newShelf.merge(with: Shelf(albums: albums, tracks: tracks, discoverLog: log))
                newShelf.consolidateMetadata()
                errors.append(contentsOf: await newShelf.loadAllArtworks(choker: self.choker))
                return (
                    newShelf,
                    albums.compactMap { newShelf.albums.get(by: $0.id) },
                    tracks.compactMap { newShelf.tracks.get(by: $0.id) },
                    errors
                )
            }()
            await MainActor.run {
                self.shelf = shelf
                self.importedAlbums = albums
                self.importedTracks = tracks
                self.returnedErrors = errors
                self.processing = false
            }
        }
    }

    func prepareDiscover() {
        DispatchQueue.global(qos: .utility).async {
            let _ = Scaler.shared()
        }
    }

    func sorted(albums: [Album]) -> [Album] {
        shelf.sorted(albums: albums)
    }

    func sorted(tracks: [Track]) -> [Track] {
        shelf.sorted(tracks: tracks)
    }

    func syncWithStorage() {
        guard syncAc == nil else { return }
        let fileManager = FileManager.default
        let myApplicationSupport = URL.applicationSupportDirectory.appending(component: "Loop3000")
        try! fileManager.createDirectory(at: myApplicationSupport, withIntermediateDirectories: true)
        let shelfURL = myApplicationSupport.appending(component: "shelf.plist")
        if let data = try? readData(from: shelfURL) {
            let decoder = PropertyListDecoder()
            shelf = try! decoder.decode(Shelf.self, from: data)
        }
        let syncQueue = DispatchQueue(label: "MusicLibrary.sync", qos: .utility)
        syncAc = $shelf
            .receive(on: syncQueue)
            .sink { shelf in
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let encoded = try! encoder.encode(shelf)
                try! encoded.write(to: shelfURL, options: [.atomic])
            }
    }

    func activate(url: URL) {
        guard let bookmark = shelf.getBookmark(normalizedURL: url.normalizedURL) else { return }
        guard let loadedURL = try? loadURLFromBookmark(bookmark) else { return }
        assert(url.normalizedURL == loadedURL.normalizedURL)
    }

    nonisolated func activateFromOtherThread(url: URL) {
        precondition(!Thread.isMainThread)
        var bookmark: Data?
        let normalizedURL = url.normalizedURL
        DispatchQueue.main.sync {
            bookmark = shelf.getBookmark(normalizedURL: normalizedURL)
        }
        guard let bookmark else { return }
        guard let loadedURL = try? loadURLFromBookmark(bookmark) else { return }
        assert(url.normalizedURL == loadedURL.normalizedURL)
    }
}

@MainActor
struct MusicPiece: EquatableIdentifiable, Hashable {
    let id: UUID
    unowned let musicLibrary: MusicLibrary

    private enum ItemType {
        case track
        case playlistItem
    }

    private let type: ItemType

    var playlistItemId: UUID? {
        type == .playlistItem ? id : nil
    }

    var playlist: Playlist? {
        playlistItemId
            .flatMap { musicLibrary.playlistItemLocation[$0] }
            .map { $0.0 }
    }

    var playlistId: UUID? {
        playlist.map { $0.id }
    }

    var playlistItem: PlaylistItem? {
        playlistItemId
            .flatMap { musicLibrary.playlistItemLocation[$0] }
            .map { $0.1 }
    }

    var trackId: UUID? {
        switch type {
        case .track: return id
        case .playlistItem: return playlistItem?.trackId
        }
    }

    var track: Track? {
        trackId.flatMap { musicLibrary.tracks[$0] }
    }

    var albumId: UUID? {
        track?.albumId
    }

    var album: Album? {
        albumId.flatMap { musicLibrary.albums[$0] }
    }

    init(playlistItemId: UUID, musicLibrary library: MusicLibrary) {
        id = playlistItemId
        type = .playlistItem
        musicLibrary = library
    }

    init(trackId: UUID, musicLibrary library: MusicLibrary) {
        id = trackId
        type = .track
        musicLibrary = library
    }

    init(_ playlistItem: PlaylistItem, musicLibrary: MusicLibrary) {
        self.init(playlistItemId: playlistItem.id, musicLibrary: musicLibrary)
    }

    init(_ track: Track, musicLibrary: MusicLibrary) {
        self.init(trackId: track.id, musicLibrary: musicLibrary)
    }

    var title: String? {
        track?.metadata[\.title]
    }

    var uiTitle: String {
        title ?? track?.source.lastPathComponent ?? "<No Title>"
    }

    var artists: [String] {
        let artistsString = track?.metadata[\.artist]
            ?? album?.metadata[\.artist]
            ?? ""
        switch artistsString {
        case "Various Artists", "V.A.", "VA":
            return []
        default:
            return universalSplit(artistsString)
        }
    }

    var trackNumber: Int? {
        track?.metadata[\.trackNumber].flatMap { Int($0) }
    }

    var discNumber: Int? {
        track?.metadata[\.discNumber].flatMap { Int($0) }
    }

    var indexString: String? {
        guard let trackNumber = trackNumber else { return nil }
        if let discNumber = discNumber {
            return String(format: "%d.%02d", discNumber, trackNumber)
        } else {
            return String(format: "%02d", trackNumber)
        }
    }

    var albumTitle: String? {
        album?.metadata[\.title]
    }

    var albumArtists: [String] {
        let artistsString = album?.metadata[\.artist] ?? ""
        switch artistsString {
        case "Various Artists", "V.A.", "VA":
            return []
        default:
            return universalSplit(artistsString)
        }
    }

    var combinedTitle: String {
        if !artists.isEmpty && artists != albumArtists {
            return uiTitle + " / " + artists.joined(separator: "; ")
        } else {
            return uiTitle
        }
    }

    var combinedAlbumTitle: String? {
        guard let albumTitle = albumTitle else { return nil }
        if albumArtists.isEmpty {
            return albumTitle
        } else {
            return albumTitle + " / " + albumArtists.joined(separator: "; ")
        }
    }

    var duration: CueTime? {
        track.flatMap { CueTime.difference($0.end, $0.start) }
    }

    var durationString: String? {
        return duration?.shortDescription
    }

    var previous: MusicPiece? {
        guard let list = playlist, let item = playlistItem else { return nil }
        let index = list.items.firstIndex(of: item)!
        guard index > 0 else { return nil }
        return MusicPiece(list.items[index - 1], musicLibrary: musicLibrary)
    }

    var next: MusicPiece? {
        guard let list = playlist, let item = playlistItem else { return nil }
        let index = list.items.firstIndex(of: item)!
        guard index < list.items.count - 1 else { return nil }
        return MusicPiece(list.items[index + 1], musicLibrary: musicLibrary)
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension CueTime {
    func toSeconds() -> Double {
        Double(value) / Double(Self.timescale)
    }

    init(seconds: Double) {
        self.init(value: Int(seconds * Double(Self.timescale)))
    }
}

struct AlertModel {
    var isPresented = false
    var title = ""
    var message = ""
}

enum ShowView {
    case discover
    case playlist
    case stub
}

enum PlaybackState {
    case playing
    case paused
    case stopped
}

@MainActor
class AppModel: ObservableObject {
    @Published var applicationIsHidden = false

    let musicLibrary = MusicLibrary()
    @Published var alertModel = AlertModel()

    @Published private(set) var playingPiece: MusicPiece?
    private var playingPieceBackup: MusicPiece?
    private var playingPieceNext: MusicPiece?
    @Published private(set) var playbackState = PlaybackState.stopped
    fileprivate var player = PlaybackScheduler()
    var currentTimestamp: CueTime {
        player.currentTimestamp
    }
    var bufferedSeconds: Double {
        player.bufferedSeconds
    }
    let refreshTimer = Timer.publish(every: 0.25, on: .main, in: .default)
        .autoconnect()
        .share()

    private var nowPlayingCenter: MPNowPlayingInfoCenter { MPNowPlayingInfoCenter.default() }
    private var remoteControlCenter: MPRemoteCommandCenter { MPRemoteCommandCenter.shared() }
    private var remoteControlInitialized = false
    private var coverData: Data?
    private var coverImage: CGImage?

    private var ac: [Cancellable] = []

    init() {
        ac.append(musicLibrary
            .objectWillChange
            .sink { [unowned self] _ in objectWillChange.send() }
        )

        player.requestNextHandler = { [unowned self] track in
            var nextTrack: Track?
            DispatchQueue.main.sync {
                nextTrack = {
                    guard let playingPiece = self.playingPiece ?? playingPieceBackup else {
                        return nil
                    }
                    guard let list = playingPiece.playlist, let item = playingPiece.playlistItem else {
                        return playingPiece.track
                    }
                    guard let track else {
                        return playingPiece.track
                    }
                    let index = list.items.firstIndex(of: item)!
                    guard let prevIndex = list.items[index...].firstIndex(where: { $0.trackId == track.id }) else {
                        return nil
                    }
                    guard prevIndex < list.items.count - 1 else {
                        return nil
                    }
                    let nextItem = list.items[prevIndex + 1]
                    playingPieceNext = MusicPiece(nextItem, musicLibrary: musicLibrary)
                    return musicLibrary.tracks[nextItem.trackId]
                }()
            }
            nextTrack.map { musicLibrary.activateFromOtherThread(url: $0.source) }
            return nextTrack
        }

        player.errorHandler = { [unowned self] error in
            DispatchQueue.main.async {
                self.alert(title: "Playback Error", message: error.localizedDescription)
            }
        }

        var tick = 0
        ac.append(refreshTimer
            .sink { [unowned self] _ in
                switch (playbackState, player.playing) {
                case (.playing, false):
                    playbackState = .stopped
                    if player.currentTrack == nil && playingPiece != nil {
                        playingPieceBackup = playingPiece
                        playingPiece = nil
                    }
                case (.stopped, true), (.paused, true):
                    playbackState = .playing
                    if playingPiece == nil && player.currentTrack == playingPieceBackup?.track {
                        playingPiece = playingPieceBackup
                        playingPieceBackup = nil
                    }
                    if playingPiece == nil && player.currentTrack == playingPieceNext?.track {
                        playingPiece = playingPieceNext
                        playingPieceNext = nil
                    }
                default: ()
                }
                guard playbackState == .playing else { return }
                tick += 1
                if tick % 20 == 0 {
                    updateNowPlayingElapsedPlaybackTime()
                }
                guard let currentTrack = player.currentTrack, let playingPiece else {
                    return
                }
                guard let list = playingPiece.playlist, let item = playingPiece.playlistItem else {
                    return
                }
                let index = list.items.firstIndex(of: item)!
                guard let currentItem = list.items[index...].first(where: { $0.trackId == currentTrack.id }) else {
                    return
                }
                if playingPiece.playlistItem != currentItem {
                    self.playingPiece = MusicPiece(currentItem, musicLibrary: musicLibrary)
                }
            }
        )

        ac.append($playbackState
            .sink { [unowned self] state in
                switch state {
                case .playing:
                    nowPlayingCenter.playbackState = .playing
                case .paused:
                    nowPlayingCenter.playbackState = .paused
                case .stopped:
                    nowPlayingCenter.playbackState = .stopped
                }
                initRemoteControl()
                updateNowPlayingElapsedPlaybackTime()
            }
        )

        ac.append($playingPiece.sink { [unowned self] playingPiece in
            if let playingPiece {
                if playingPiece.album?.cover != coverData {
                    coverData = playingPiece.album?.cover
                    coverImage = coverData.map { loadImage(from: $0) }
                }
                var nowPlayingInfo = [
                    MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
                    MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
                    MPNowPlayingInfoPropertyPlaybackRate: 1.0,
                    MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
                    MPNowPlayingInfoPropertyIsLiveStream: false,
                    MPMediaItemPropertyTitle: playingPiece.uiTitle,
                ]
                (playingPiece.duration?.toSeconds()).map { nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = $0 }
                (playingPiece.track?.source).map { nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = $0 }
                (playingPiece.artists.isEmpty ? nil : playingPiece.artists.joined(separator: ";")).map { nowPlayingInfo[MPMediaItemPropertyArtist] = $0 }
                playingPiece.albumTitle.map { nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = $0 }
                coverImage
                    .map{ coverImage in
                        MPMediaItemArtwork(
                            boundsSize: CGSize(width: Double(coverImage.width), height: Double(coverImage.height))
                        ) { size in
                            NSImage(cgImage: coverImage, size: size)
                        }
                    }
                    .map { nowPlayingInfo[MPMediaItemPropertyArtwork] = $0 }
                nowPlayingCenter.nowPlayingInfo = nowPlayingInfo
            } else {
                nowPlayingCenter.nowPlayingInfo = nil
            }
        })

    }

    func alert(title: String, message: String) {
        alertModel.title = title
        alertModel.message = message
        alertModel.isPresented = true
    }

    func play(_ piece: MusicPiece) {
        playingPiece = piece
        player.stop()
        player.play()
    }

    private func resume() {
        if playingPiece != nil {
            player.play()
        }
    }

    func pause() {
        playbackState = .paused
        player.pause()
    }

    func playPrevious() {
        playingPiece
            .flatMap { $0.previous }
            .map { play($0) }
    }

    func playNext() {
        playingPiece
            .flatMap { $0.next }
            .map { play($0) }
    }

    func seek(to time: CueTime) {
        self.player.seek(to: time)
        updateNowPlayingElapsedPlaybackTime()
    }

    func initRemoteControl() {
        guard !remoteControlInitialized else { return }
        remoteControlCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        remoteControlCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        remoteControlCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .success }
            if self.playbackState == .playing {
                self.pause()
            } else {
                self.resume()
            }
            return .success
        }
        remoteControlCenter.previousTrackCommand.addTarget { [weak self]  _ in
            self?.playPrevious()
            return .success
        }
        remoteControlCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        remoteControlCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            let seekEvent = event as! MPChangePlaybackPositionCommandEvent
            self?.seek(to: CueTime(seconds: seekEvent.positionTime))
            return .success
        }
        remoteControlInitialized = true
    }

    func updateNowPlayingElapsedPlaybackTime() {
        nowPlayingCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTimestamp.toSeconds()
    }
}

@MainActor
class WindowModel: ObservableObject {
    @Published private(set) var currentView = ShowView.stub
    @Published private(set) var previousView: ShowView?

    @Published var selectedList: UUID?
    @Published var selectedPiece: MusicPiece?
    @Published var selectedPieces: Set<MusicPiece> = []

    unowned let appModel: AppModel

    private var ac: [Cancellable] = []

    init(appModel: AppModel) {
        self.appModel = appModel

        $currentView
            .withPrevious()
            .compactMap { (previousView, currentView) -> ShowView? in
                previousView.flatMap { $0 == currentView ? nil : $0 }
            }
            .assign(to: &$previousView)

        appModel.musicLibrary.$processing
            .compactMap { $0 ? .discover : nil }
            .assign(to: &$currentView)

        $selectedList
            .compactMap { $0.map { _ in .playlist } }
            .assign(to: &$currentView)

        appModel.$playingPiece
            .compactMap { [unowned self] playingPiece -> MusicPiece? in
                guard playingPiece?.playlistId == selectedList else { return nil }
                return playingPiece
            }
            .assign(to: &$selectedPiece)

        $selectedPiece
            .compactMap { $0.map { _ in [] } }
            .assign(to: &$selectedPieces)

        $selectedPieces
            .compactMap { $0.isEmpty ? nil : true }
            .map { _ in nil }
            .assign(to: &$selectedPiece)
    }

    func switchToPreviousView() {
        guard let previousView = previousView else { return }
        currentView = previousView
    }

    func resume() {
        if appModel.playingPiece != nil {
            appModel.player.play()
        } else {
            selectedList
                .flatMap { appModel.musicLibrary.playlists[$0] }
                .flatMap { $0.items.first }
                .map { appModel.play(MusicPiece($0, musicLibrary: appModel.musicLibrary)) }
        }
    }
}
