import Foundation
import Combine
import UniformTypeIdentifiers

extension Album {
    var uiTitle: String {
        metadata[MetadataCommonKey.title] ?? "<No Title>"
    }
}

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
                    Playlist(title: album.uiTitle, items: shelf.getTracks(for: album).map { PlaylistItem(trackId: $0.id) })
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
            let newShelf = Shelf(albums: albums, tracks: tracks)
            self.shelfOO = sortedShelf(mergeShelf(self.shelf, newShelf))
            self.importedAlbumsOO = albums.filter { self.shelfOO.albums.contains($0) }
            self.importedTracksOO = tracks.filter { self.shelfOO.tracks.contains($0) }
            return []
        }
    }

    func performDiscoverMedia(at url: URL, recursive: Bool = false) {
        perform {
            self.clearResult()
            let (albums, tracks, errors) = try await discoverMedia(at: url, recursive: recursive, tracer: self.tracer)
            let newShelf = Shelf(albums: albums, tracks: tracks)
            self.shelfOO = sortedShelf(mergeShelf(self.shelf, newShelf))
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

    func getPlaylist(by id: UUID) -> Playlist {
        playlists.get(by: id)!
    }

    func getPlaylist(for item: PlaylistItem) -> Playlist {
        playlists.first { $0.items.contains(item) }!
    }

    func sorted(albums: [Album]) -> [Album] {
        shelf.sorted(albums: albums)
    }

    func sorted(tracks: [Track]) -> [Track] {
        shelf.sorted(tracks: tracks)
    }

    func syncWithStorage() {
        let fileManager = FileManager.default
        let applicationSupport = try! fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ).appending(component: "Loop3000")
        try! fileManager.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        let shelfURL = applicationSupport.appending(component: "shelf.plist")
        if let data = try? readData(from: shelfURL) {
            let decoder = PropertyListDecoder()
            shelf = try! decoder.decode(Shelf.self, from: data)
            print(shelf)
        }
        let syncQueue = DispatchQueue(label: "MusicLibrary.sync")
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
    @Published private(set) var musicLibrary = MusicLibrary()
    @Published var libraryCommands = LibraryCommands()
    @Published var alertModel = AlertModel()

    @Published private(set) var currentView = ShowView.Stub
    @Published private(set) var previousView: ShowView?

    @Published var selectedList: Playlist?
    @Published private(set) var playingList: Playlist?
    @Published var selectedItem: PlaylistItem?
    @Published private(set) var playingItem: PlaylistItem?
    @Published private(set) var playing = false

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
            .compactMap { $0 != nil ? .Playlist : nil }
            .assign(to: &$currentView)

        $playingItem
            .assign(to: &$selectedItem)
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

    func play(_ item: PlaylistItem) {

    }

    func pause() {

    }

    func resume() {

    }

    func playPrevious() {}

    func playNext() {}
}
