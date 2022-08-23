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

class MusicLibrary: ObservableObject {
    @Published private var shelf = Shelf()
    @Published private(set) var albums: [Album] = []
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var manualPlaylists: [Playlist] = []
    @Published private(set) var albumPlaylists: [Playlist] = []
    @Published private(set) var playlists: [Playlist] = []

    @Published private(set) var importedAlbums: [Album] = []
    @Published private(set) var importedTracks: [Track] = []
    @Published private(set) var thrownError: Error?
    @Published private(set) var returnedError: [Error] = []
    @Published private(set) var requesting: [URL] = []
    @Published private(set) var processing = false
    @Published private var importedAlbumsOO: [Album] = []
    @Published private var importedTracksOO: [Track] = []
    @Published private var thrownErrorOO: Error?
    @Published private var returnedErrorOO: [Error] = []
    @Published private var processingOO = false
    @Published private var shelfOO = Shelf()
    private let asyncQueue = AsyncQueue()
    private let tracer = ObservableRequestTracer(adding: PassthroughSubject(), removing: PassthroughSubject())

    private var ac: [any Cancellable] = []

    init() {
        $shelf
            .map { $0.albums }
            .assign(to: &$albums)

        $shelf
            .map { $0.tracks }
            .assign(to: &$tracks)

        $shelf
            .map { $0.manualPlaylists }
            .assign(to: &$manualPlaylists)

        $shelf
            .map { shelf in
                shelf.albums.map { album in
                    Playlist(
                        id: album.id,
                        title: album.metadata[MetadataCommonKey.title] ?? "<No Title>",
                        items: shelf.getTracks(for: album).map { PlaylistItem(id: $0.id, trackId: $0.id) }
                    )
                }
            }
            .assign(to: &$albumPlaylists)

        Publishers.CombineLatest($albumPlaylists, $manualPlaylists)
            .map { (albumPlaylists, manualPlaylists) in
                albumPlaylists + manualPlaylists
            }
            .assign(to: &$playlists)

        ac.append(tracer.adding
            .receive(on: RunLoop.main)
            .sink { [unowned self] url in
                self.requesting.append(url)
            }
        )

        ac.append(tracer.removing
            .receive(on: RunLoop.main)
            .sink { [unowned self] url in
                if let index = self.requesting.lastIndex(of: url) {
                    self.requesting.remove(at: index)
                }
            }
        )

        $importedAlbumsOO.receive(on: RunLoop.main).assign(to: &$importedAlbums)
        $importedTracksOO.receive(on: RunLoop.main).assign(to: &$importedTracks)
        $thrownErrorOO.receive(on: RunLoop.main).assign(to: &$thrownError)
        $returnedErrorOO.receive(on: RunLoop.main).assign(to: &$returnedError)
        $processingOO.receive(on: RunLoop.main).assign(to: &$processing)
        $shelfOO.receive(on: RunLoop.main).assign(to: &$shelf)
    }

    private func perform(_ operation: @escaping () async throws -> [Error]) {
        Task {
            await asyncQueue.perform({
                self.processingOO = true
                self.returnedErrorOO = []
                self.thrownErrorOO = nil
                do {
                    self.returnedErrorOO = try await operation()
                } catch let error {
                    self.thrownErrorOO = error
                }
                self.processingOO = false
            })
        }
    }

    func clearResult() {
        importedAlbumsOO = []
        importedTracksOO = []
    }

    func performScanMedia(at url: URL) {
        perform {
            self.clearResult()
            let (albums, tracks) = try await scanMedia(at: url, tracer: self.tracer)
            var newShelf = self.shelf
            newShelf.merge(with: Shelf(albums: albums, tracks: tracks))
            newShelf.consolidateMetadata()
            let errors = await newShelf.loadAllArtworks(tracer: self.tracer)
            newShelf.sort()
            self.shelfOO = newShelf
            self.importedAlbumsOO = albums.filter { self.shelfOO.albums.contains($0) }
            self.importedTracksOO = tracks.filter { self.shelfOO.tracks.contains($0) }
            return errors
        }
    }

    func performDiscoverMedia(at url: URL, recursive: Bool = false) {
        perform {
            self.clearResult()
            var (albums, tracks, errors) = try await discoverMedia(at: url, recursive: recursive, tracer: self.tracer)
            var newShelf = self.shelf
            newShelf.merge(with: Shelf(albums: albums, tracks: tracks))
            newShelf.consolidateMetadata()
            errors.append(contentsOf: await newShelf.loadAllArtworks(tracer: self.tracer))
            newShelf.sort()
            self.shelfOO = newShelf
            self.importedAlbumsOO = albums.filter { self.shelfOO.albums.contains($0) }
            self.importedTracksOO = tracks.filter { self.shelfOO.tracks.contains($0) }
            return errors
        }
    }

    var canImportTypes: [UTType] {
        mediaImporters.flatMap { $0.supportedTypes }
    }

    var canGrabTypes: [UTType] {
        metadataGrabbers.flatMap { $0.supportedTypes }
    }

    func getTracks(for album: Album) -> [Track] {
        shelf.getTracks(for: album)
    }

    func getTracks(for playlist: Playlist) -> [Track] {
        shelf.getTracks(for: playlist)
    }

    func getAlbum(for track: Track) -> Album {
        shelf.getAlbum(for: track)
    }

    func getAlbum(by id: UUID) -> Album {
        albums.get(by: id)!
    }

    func getTrack(by id: UUID) -> Track {
        tracks.get(by: id)!
    }

    func getPlaylist(by id: UUID) -> Playlist? {
        playlists.get(by: id)
    }

    func locatePlaylistItem(by id: UUID) -> (Playlist, PlaylistItem)? {
        for list in playlists {
            if let item = list.items.first(where: { $0.id == id }) {
                return (list, item)
            }
        }
        return nil
    }

    func sorted(albums: [Album]) -> [Album] {
        shelf.sorted(albums: albums)
    }

    func sorted(tracks: [Track]) -> [Track] {
        shelf.sorted(tracks: tracks)
    }

    func syncWithStorage() {
        let fileManager = FileManager.default
        let applicationSupport = URL.applicationSupportDirectory.appending(component: "Loop3000")
        try! fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        let shelfURL = applicationSupport.appending(component: "shelf.plist")
        if let data = try? readData(from: shelfURL) {
            let decoder = PropertyListDecoder()
            shelf = try! decoder.decode(Shelf.self, from: data)
        }
        let syncQueue = DispatchQueue(label: "MusicLibrary.sync", qos: .utility)
        ac.append($shelf
            .sink { shelf in
                syncQueue.async {
                    let encoder = PropertyListEncoder()
                    encoder.outputFormat = .binary
                    let encoded = try! encoder.encode(shelf)
                    try! encoded.write(to: shelfURL)
                }
            }
        )
    }
}


struct LibraryCommands {
    var showFileAdder = false
    var showFolderAdder = false
    var showDiscoverer = false
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

class ViewModel: ObservableObject {
    @Published var windowIsHidden = false

    @Published private(set) var musicLibrary = MusicLibrary()
    @Published var libraryCommands = LibraryCommands()
    @Published var alertModel = AlertModel()

    @Published private(set) var currentView = ShowView.Stub
    @Published private(set) var previousView: ShowView?

    @Published var selectedList: UUID?
    @Published var selectedItem: UUID?
    @Published private(set) var playingItem: UUID?
    @Published private(set) var playing = false
    @Published private(set) var paused = false
    @Published private(set) var currentTimestamp = Timestamp.zero

    private var player = PlaybackScheduler()

    private var nowPlayingCenter: MPNowPlayingInfoCenter { MPNowPlayingInfoCenter.default() }
    private var remoteControlCenter: MPRemoteCommandCenter { MPRemoteCommandCenter.shared() }
    private var remoteControlInitialized = false
    private var coverJPEG: Data?
    private var coverImage: CGImage?

    private var ac: [any Cancellable] = []

    init() {
        ac.append(musicLibrary
            .objectWillChange
            .receive(on: RunLoop.main)
            .sink { [unowned self] _ in self.objectWillChange.send() }
        )

        $currentView
            .withPrevious()
            .map { $0.0 }
            .assign(to: &$previousView)

        musicLibrary.$processing
            .compactMap { $0 ? .Discover : nil }
            .assign(to: &$currentView)

        $selectedList
            .compactMap { $0.map { _ in .Playlist } }
            .assign(to: &$currentView)

        $playingItem
            .compactMap { [unowned self] playingItem in
                guard let playingItem else { return nil }
                guard let (list, _) = self.musicLibrary.locatePlaylistItem(by: playingItem) else { return nil }
                guard list.id == self.selectedList else { return nil }
                return playingItem
            }
            .assign(to: &$selectedItem)

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
            return self.musicLibrary.getTrack(by: list.items[prevIndex + 1].trackId)
        }

        player.errorHandler = { [unowned self] error in
            DispatchQueue.main.async {
                self.alert(title: "Playback Error", message: error.localizedDescription)
            }
        }

        var tick = 0
        ac.append(Timer.publish(every: 0.25, on: .main, in: .default)
            .autoconnect()
            .sink { [unowned self] _ in
                let playing = player.playing
                if self.playing != playing {
                    self.playing = playing
                    if !playing && player.currentTrack == nil {
                        playingItem = nil
                    }
                }
                guard playing else { return }
                currentTimestamp = player.currentTimestamp
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
                if playing {
                    nowPlayingCenter.playbackState = .playing
                    updateNowPlayingElapsedPlaybackTime()
                } else if paused {
                    nowPlayingCenter.playbackState = .paused
                    updateNowPlayingElapsedPlaybackTime()
                } else {
                    nowPlayingCenter.playbackState = .stopped
                }
                initRemoteControl()
            }
        )

        ac.append($playingItem.sink { [unowned self] playingItem in
            if let playingItem {
                guard let (_, item) = musicLibrary.locatePlaylistItem(by: playingItem) else { return }
                let track = musicLibrary.getTrack(by: item.trackId)
                let album = musicLibrary.getAlbum(for: track)
                if album.coverJPEG != coverJPEG {
                    coverJPEG = album.coverJPEG
                    coverImage = coverJPEG.map { coverJPEG in
                        return CGImage(
                            jpegDataProviderSource: CGDataProvider(data: coverJPEG as CFData)!,
                            decode: nil,
                            shouldInterpolate: true,
                            intent: .defaultIntent
                        )!
                    }
                }
                nowPlayingCenter.nowPlayingInfo = [
                    MPMediaItemPropertyPlaybackDuration: Double(track.end.value - track.start.value) / Double(Timestamp.timescale),
                    MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
                    MPNowPlayingInfoPropertyAssetURL: track.source,
                    MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
                    MPNowPlayingInfoPropertyPlaybackRate: 1.0,
                    MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
                    MPNowPlayingInfoPropertyIsLiveStream: false,
                    MPMediaItemPropertyTitle: track.metadata[MetadataCommonKey.title] ?? track.source.lastPathComponent,
                    MPMediaItemPropertyArtist:
                        (track.metadata[MetadataCommonKey.artist] ?? album.metadata[MetadataCommonKey.artist])
                            .map({ universalSplit($0).joined(separator: "; ") }) as Any,
                    MPMediaItemPropertyAlbumTitle: album.metadata[MetadataCommonKey.title] as Any,
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

    func switchToPreviousView() {
        guard let previousView = previousView else { return }
        currentView = previousView
    }

    func play(_ itemId: UUID) {
        self.playingItem = itemId
        self.player.stop()
        self.player.play()
    }

    func pause() {
        self.paused = true
        self.player.pause()
    }

    func resume() {
        if playingItem != nil {
            self.player.play()
        } else {
            selectedList
                .flatMap { musicLibrary.getPlaylist(by: $0) }
                .flatMap { $0.items.first }
                .map { self.play($0.id) }
        }
    }

    func playPrevious() {
        guard let (list, item) = playingItem.flatMap({ musicLibrary.locatePlaylistItem(by: $0) }) else {
            return
        }
        let index = list.items.firstIndex(of: item)!
        guard index > 0 else { return }
        play(list.items[index - 1].id)
    }

    func playNext() {
        guard let (list, item) = playingItem.flatMap({ musicLibrary.locatePlaylistItem(by: $0) }) else {
            return
        }
        let index = list.items.firstIndex(of: item)!
        guard index < list.items.count - 1 else { return }
        play(list.items[index + 1].id)
    }

    func seek(to time: Timestamp) {
        self.player.seek(to: time)
        currentTimestamp = self.player.currentTimestamp
        updateNowPlayingElapsedPlaybackTime()
    }

    func initRemoteControl() {
        guard !remoteControlInitialized else { return }
        remoteControlCenter.playCommand.addTarget { _ in
            self.resume()
            return .success
        }
        remoteControlCenter.pauseCommand.addTarget { _ in
            self.pause()
            return .success
        }
        remoteControlCenter.previousTrackCommand.addTarget { _ in
            self.playPrevious()
            return .success
        }
        remoteControlCenter.nextTrackCommand.addTarget { _ in
            self.playNext()
            return .success
        }
        remoteControlCenter.changePlaybackPositionCommand.addTarget { event in
            let seekEvent = event as! MPChangePlaybackPositionCommandEvent
            self.seek(to: Timestamp(value: Int(seekEvent.positionTime * Double(Timestamp.timescale))))
            return .success
        }
        remoteControlInitialized = true
    }

    func updateNowPlayingElapsedPlaybackTime() {
        nowPlayingCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
            Double(currentTimestamp.value) / Double(Timestamp.timescale)
    }
}
