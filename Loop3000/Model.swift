import Foundation
import AppKit
import CoreGraphics
import Combine
import MediaPlayer
import UniformTypeIdentifiers

fileprivate struct ObservableRequestTracer: RequestTracer {
    func add(_ url: URL) {
        adding.send(url)
    }

    func remove(_ url: URL) {
        removing.send(url)
    }

    var adding: PassthroughSubject<URL, Never>
    var removing: PassthroughSubject<URL, Never>
}

@MainActor
class MusicLibrary: ObservableObject {
    @Published private var shelf = Shelf()
    @Published private var albums: [UUID: Album] = [:]
    @Published private var tracks: [UUID: Track] = [:]
    @Published private(set) var manualPlaylists: [Playlist] = []
    @Published private(set) var albumPlaylists: [Playlist] = []
    @Published private(set) var playlists: [UUID: Playlist] = [:]
    @Published private var playlistItemMap: [UUID: (Playlist, PlaylistItem)] = [:]

    @Published private(set) var importedAlbums: [Album] = []
    @Published private(set) var importedTracks: [Track] = []
    @Published private(set) var returnedErrors: [Error] = []
    @Published private(set) var requesting: [URL] = []
    @Published private(set) var processing = false
    private let queue = SerialAsyncQueue()
    private let tracer = ObservableRequestTracer(adding: PassthroughSubject(), removing: PassthroughSubject())

    private var ac: [any Cancellable] = []
    private var syncAc: Cancellable?

    init() {
        $shelf
            .map { $0.albums }
            .map {
                var d: [UUID: Album] = [:]
                for album in $0 {
                    d[album.id] = album
                }
                return d
            }
            .assign(to: &$albums)

        $shelf
            .map { $0.tracks }
            .map {
                var d: [UUID: Track] = [:]
                for track in $0 {
                    d[track.id] = track
                }
                return d
            }
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
            .map {
                var d: [UUID: Playlist] = [:]
                for playlist in $0 {
                    d[playlist.id] = playlist
                }
                return d
            }
            .assign(to: &$playlists)

        $playlists
            .map {
                var d: [UUID: (Playlist, PlaylistItem)] = [:]
                for playlist in $0.values {
                    for item in playlist.items {
                        d[item.id] = (playlist, item)
                    }
                }
                return d
            }
            .assign(to: &$playlistItemMap)

        ac.append(tracer.adding
            .receive(on: RunLoop.main)
            .sink { [unowned self] url in
                requesting.append(url)
            }
        )

        ac.append(tracer.removing
            .receive(on: RunLoop.main)
            .sink { [unowned self] url in
                if let index = requesting.lastIndex(of: url) {
                    requesting.remove(at: index)
                }
            }
        )
    }

    func performDiscover(at url: URL) {
        Task.detached {
            await self.queue.enqueue {
                await MainActor.run {
                    self.processing = true
                }
                let (shelf, albums, tracks, errors) = await {
                    let oldShelf = await self.shelf
                    let result = await discover(at: url, recursive: true, previousLog: oldShelf.discoverLog, tracer: self.tracer)
                    let albums = result.albums
                    let tracks = result.tracks
                    let log = result.log
                    var errors = result.errors
                    var newShelf = oldShelf
                    newShelf.merge(with: Shelf(albums: albums, tracks: tracks, discoverLog: log))
                    newShelf.consolidateMetadata()
                    errors.append(contentsOf: await newShelf.loadAllArtworks(tracer: self.tracer))
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
    }

    func locatePlaylistItem(by itemId: UUID) -> (Playlist, PlaylistItem)? {
        playlistItemMap[itemId]
    }

    func getTrack(by id: UUID) -> Track? {
        tracks[id]
    }

    func getAlbum(by id: UUID) -> Album? {
        albums[id]
    }

    func getPlaylist(by id: UUID) -> Playlist? {
        playlists[id]
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
            shelf.activate()
        }
        let syncQueue = DispatchQueue(label: "MusicLibrary.sync", qos: .utility)
        syncAc = $shelf
            .sink { shelf in
                syncQueue.async {
                    let encoder = PropertyListEncoder()
                    encoder.outputFormat = .binary
                    let encoded = try! encoder.encode(shelf)
                    try! encoded.write(to: shelfURL, options: [.atomic])
                }
            }
    }
}

struct AlertModel {
    var isPresented = false
    var title = ""
    var message = ""
}

enum ShowView {
    case Discover
    case Playlist
    case Stub
}

@MainActor
class AppModel: ObservableObject {
    @Published var applicationIsHidden = false

    @Published private(set) var musicLibrary = MusicLibrary()
    @Published var alertModel = AlertModel()

    @Published private(set) var playingItem: UUID?
    @Published private(set) var playing = false
    @Published private(set) var paused = false

    fileprivate var player = PlaybackScheduler()
    var currentTimestamp: CueTime {
        player.currentTimestamp
    }
    private var nowPlayingCenter: MPNowPlayingInfoCenter { MPNowPlayingInfoCenter.default() }
    private var remoteControlCenter: MPRemoteCommandCenter { MPRemoteCommandCenter.shared() }
    private var remoteControlInitialized = false
    private var coverData: Data?
    private var coverImage: CGImage?
    let refreshTimer = Timer.publish(every: 0.25, on: .main, in: .default)
        .autoconnect()
        .share()

    private var ac: [any Cancellable] = []

    init() {
        ac.append(musicLibrary
            .objectWillChange
            .sink { [unowned self] _ in objectWillChange.send() }
        )

        $playing
            .compactMap { $0 ? false : nil }
            .assign(to: &$paused)

        player.requestNextHandler = { [unowned self] track in
            guard let (list, item) = playingItem.flatMap({ musicLibrary.locatePlaylistItem(by: $0) }) else {
                return nil
            }
            guard let track else {
                return musicLibrary.getTrack(by: item.trackId)
            }
            let index = list.items.firstIndex(of: item)!
            guard let prevIndex = list.items[index...].firstIndex(where: { $0.trackId == track.id }) else {
                return nil
            }
            guard prevIndex < list.items.count - 1 else {
                return nil
            }
            return musicLibrary.getTrack(by: list.items[prevIndex + 1].trackId)
        }

        player.errorHandler = { [unowned self] error in
            DispatchQueue.main.async {
                self.alert(title: "Playback Error", message: error.localizedDescription)
            }
        }

        var tick = 0
        ac.append(refreshTimer
            .sink { [unowned self] _ in
                if playing != player.playing {
                    playing = player.playing
                    if !playing && player.currentTrack == nil && playingItem != nil {
                        playingItem = nil
                    }
                }
                guard playing else { return }
                tick += 1
                if tick % 20 == 0 {
                    updateNowPlayingElapsedPlaybackTime()
                }
                guard let currentTrack = player.currentTrack else {
                    return
                }
                guard let (list, item) = playingItem.flatMap({ musicLibrary.locatePlaylistItem(by: $0) }) else {
                    return
                }
                let index = list.items.firstIndex(of: item)!
                guard let currentItem = list.items[index...].first(where: { $0.trackId == currentTrack.id })?.id else {
                    return
                }
                if playingItem != currentItem {
                    playingItem = currentItem
                }
            }
        )

        ac.append(Publishers.CombineLatest($playing, $paused)
            .sink { [unowned self] (playing, paused) in
                switch (playing, paused) {
                case (true, false):
                    nowPlayingCenter.playbackState = .playing
                    updateNowPlayingElapsedPlaybackTime()
                case (false, true):
                    nowPlayingCenter.playbackState = .paused
                    updateNowPlayingElapsedPlaybackTime()
                case (false, false):
                    nowPlayingCenter.playbackState = .stopped
                default:
                    ()
                }
                initRemoteControl()
            }
        )

        ac.append($playingItem.sink { [unowned self] playingItem in
            if let playingItem {
                guard let (_, item) = musicLibrary.locatePlaylistItem(by: playingItem) else { return }
                let track = musicLibrary.getTrack(by: item.trackId)!
                let album = musicLibrary.getAlbum(by: track.albumId)!
                if album.cover != coverData {
                    coverData = album.cover
                    coverImage = coverData.map { loadImage(from: $0) }
                }
                nowPlayingCenter.nowPlayingInfo = [
                    MPMediaItemPropertyPlaybackDuration: Double(track.end.value - track.start.value) / Double(CueTime.timescale),
                    MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
                    MPNowPlayingInfoPropertyAssetURL: track.source,
                    MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
                    MPNowPlayingInfoPropertyPlaybackRate: 1.0,
                    MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
                    MPNowPlayingInfoPropertyIsLiveStream: false,
                    MPMediaItemPropertyTitle: track.metadata[\.title] ?? track.source.lastPathComponent,
                    MPMediaItemPropertyArtist:
                        (track.metadata[\.artist] ?? album.metadata[\.artist])
                            .map({ universalSplit($0).joined(separator: "; ") }) as Any,
                    MPMediaItemPropertyAlbumTitle: album.metadata[\.title] as Any,
                    MPMediaItemPropertyArtwork: coverImage.map({ coverImage in
                        MPMediaItemArtwork(
                            boundsSize: CGSize(width: Double(coverImage.width), height: Double(coverImage.height))
                        ) { size in
                            NSImage(cgImage: coverImage, size: size)
                        }
                    }) as Any
                ]
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

    func play(_ itemId: UUID) {
        playingItem = itemId
        player.stop()
        player.play()
    }

    private func resume() {
        if playingItem != nil {
            player.play()
        }
    }

    func pause() {
        paused = true
        player.pause()
    }

    func playPrevious() {
        guard let (list, item) = playingItem.flatMap({ musicLibrary.locatePlaylistItem(by: $0) }) else { return }
        let index = list.items.firstIndex(of: item)!
        guard index > 0 else { return }
        play(list.items[index - 1].id)
    }

    func playNext() {
        guard let (list, item) = playingItem.flatMap({ musicLibrary.locatePlaylistItem(by: $0) }) else { return }
        let index = list.items.firstIndex(of: item)!
        guard index < list.items.count - 1 else { return }
        play(list.items[index + 1].id)
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
            self?.seek(to: CueTime(value: Int(seekEvent.positionTime * Double(CueTime.timescale))))
            return .success
        }
        remoteControlInitialized = true
    }

    func updateNowPlayingElapsedPlaybackTime() {
        nowPlayingCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
            Double(player.currentTimestamp.value) / Double(CueTime.timescale)
    }
}

@MainActor
class WindowModel: ObservableObject {
    @Published private(set) var currentView = ShowView.Stub
    @Published private(set) var previousView: ShowView?

    @Published var selectedList: UUID?
    @Published var selectedItem: UUID?

    unowned let appModel: AppModel

    private var ac: [any Cancellable] = []

    init(appModel: AppModel) {
        self.appModel = appModel

        $currentView
            .withPrevious()
            .compactMap { (previousView, currentView) -> ShowView? in
                previousView.flatMap { $0 == currentView ? nil : $0 }
            }
            .assign(to: &$previousView)

        appModel.musicLibrary.$processing
            .compactMap { $0 ? .Discover : nil }
            .assign(to: &$currentView)

        $selectedList
            .compactMap { $0.map { _ in .Playlist } }
            .assign(to: &$currentView)

        appModel.$playingItem
            .compactMap { [unowned self] playingItem in
                guard let playingItem else { return nil }
                guard let (list, _) = appModel.musicLibrary.locatePlaylistItem(by: playingItem) else { return nil }
                guard list.id == selectedList else { return nil }
                return playingItem
            }
            .assign(to: &$selectedItem)
    }

    func switchToPreviousView() {
        guard let previousView = previousView else { return }
        currentView = previousView
    }

    func resume() {
        if appModel.playingItem != nil {
            appModel.player.play()
        } else {
            selectedList
                .flatMap { appModel.musicLibrary.getPlaylist(by: $0) }
                .flatMap { $0.items.first }
                .map { appModel.play($0.id) }
        }
    }
}
