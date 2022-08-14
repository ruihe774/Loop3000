import Foundation
import Combine
import UniformTypeIdentifiers

fileprivate actor MusicLibraryActor {
    private let musicLibrary: MusicLibrary

    init(musicLibrary: MusicLibrary) {
        self.musicLibrary = musicLibrary
    }

    func importMedia(from url: URL) async throws -> (importedAlbums: [Album], importedTracks: [Track]) {
        try await musicLibrary.importMedia(from: url)
    }

    func discover(at url: URL, recursive: Bool = false, consolidate: Bool = true)
    async throws -> (importedAlbums: [Album], importedTracks: [Track], errors: [Error]) {
        try await musicLibrary.discover(at: url, recursive: recursive, consolidate: consolidate)
    }

    func consolidate() {
        musicLibrary.consolidate()
    }

    func importLibrary(from data: Data) throws -> (importedAlbums: [Album], importedTracks: [Track]) {
        try musicLibrary.importLibrary(from: data)
    }

    var albums: [Album] {
        musicLibrary.albums
    }

    var tracks: [Track] {
        musicLibrary.tracks
    }
}

extension Publisher {
    func `await`<T>(_ f: @escaping (Output) async -> T) -> some Publisher<T, Failure> {
        flatMap { value -> Future<T, Failure> in
            Future { promise in
                Task {
                    let result = await f(value)
                    promise(.success(result))
                }
            }
        }
    }
}

class ObservableMusicLibrary: ObservableObject {
    private let backstore = MusicLibrary()
    private let shelf: MusicLibraryActor

    @Published private(set) var albums: [Album] = []
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var processing = false
    @Published private(set) var requesting: [URL] = []
    @Published private(set) var thrownError: Error?
    @Published private(set) var returnedErrors: [Error] = []
    @Published private(set) var importedAlbums: [Album] = []
    @Published private(set) var importedTracks: [Track] = []

    @Published private var tasks = Set<UUID>()

    private let taskStarted = PassthroughSubject<UUID, Never>()
    private let taskFinished = PassthroughSubject<(taskId: UUID, thrownError: Error?, returnedErrors: [Error]), Never>()
    private let discovered = PassthroughSubject<(importedAlbums: [Album], importedTracks: [Track]), Never>()

    private var ac: [any Cancellable] = []

    init() {
        shelf = MusicLibraryActor(musicLibrary: backstore)
        backstore.requestTracer = RequestTracer()
        
        ac.append(taskStarted
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] taskId in
                self.tasks.insert(taskId)
            })

        ac.append(taskFinished
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] (taskId, thrownError, returnedErrors) in
                self.tasks.remove(taskId)
                self.thrownError = thrownError
                self.returnedErrors = returnedErrors
            })

        let reassign = taskFinished
            .await { [unowned self] _ in
                async let albums = self.shelf.albums
                async let tracks = self.shelf.tracks
                return await (albums: albums, tracks: tracks)
            }
            .receive(on: DispatchQueue.main)
            .share()
        reassign
            .map { $0.albums }
            .assign(to: &$albums)
        reassign
            .map { $0.tracks }
            .assign(to: &$tracks)

        $tasks
            .map { !$0.isEmpty }
            .assign(to: &$processing)

        discovered
            .receive(on: DispatchQueue.main)
            .map { ( importedAlbums, _) in importedAlbums }
            .assign(to: &$importedAlbums)

        discovered
            .receive(on: DispatchQueue.main)
            .map { (_, importedTracks) in importedTracks }
            .assign(to: &$importedTracks)

        ac.append(Timer.publish(every: 2, on: .main, in: .default)
            .autoconnect()
            .compactMap { [unowned self] date in self.processing ? date : nil }
            .sink { [unowned self] _ in
                self.requesting = self.backstore.requestTracer!.urls
            }
        )
    }

    private func perform(operation: @escaping () async throws -> [Error]) {
        let taskId = UUID()
        taskStarted.send(taskId)
        Task {
            var thrownError: Error?
            var returnedErrors: [Error] = []
            do {
                returnedErrors = try await operation()
            } catch let error {
                thrownError = error
            }
            taskFinished.send((taskId: taskId, thrownError: thrownError, returnedErrors: returnedErrors))
        }
    }

    func performImportMedia(from url: URL) {
        perform {
            let r = try await self.shelf.importMedia(from: url)
            self.discovered.send(r)
            return []
        }
    }

    func performDiscover(at url: URL, recursive: Bool = false, consolidate: Bool = true) {
        perform {
            let r = try await self.shelf.discover(at: url, recursive: recursive, consolidate: consolidate)
            self.discovered.send((importedAlbums: r.importedAlbums, importedTracks: r.importedTracks))
            return r.errors
        }
    }

    func clearResult() {
        importedAlbums = []
        importedTracks = []
    }

    func getTracks(for album: Album) -> [Track] {
        backstore.getTracks(for: album)
    }

    func getAlbum(for track: Track) -> Album {
        backstore.getAlbum(for: track)
    }

    func performConsolidate() {
        perform {
            await self.shelf.consolidate()
            return []
        }
    }

    func performInputLibrary(from url: URL) {
        perform {
            let data = try await URLSession.shared.data(from: url).0
            self.discovered.send(try await self.shelf.importLibrary(from: data))
            return []
        }
    }

    var canImportTypes: [UTType] {
        self.backstore.canImportTypes
    }

    var canGrabTypes: [UTType] {
        self.backstore.canGrabTypes
    }

    func sorted(tracks: [Track]) -> [Track] {
        self.backstore.sorted(tracks: tracks)
    }
}

struct LibraryCommands {
    var showFileAdder = false
    var showFolderAdder = false
    var showDiscoverer = false
    var consolidate = false
    var importLibrary = false
    var exportLibary = false
}

struct AlertModel {
    var isPresented = false
    var title = ""
    var message = ""
}

enum ShowView {
    case Discover
    case Stub
}

enum SidebarList {
    case Albums
    case Playlists
}

struct SidebarModel {
    var currentList = SidebarList.Albums
    var selected: UUID?
}

extension Publisher {
    func withPrevious() -> some Publisher<(previous: Output?, current: Output), Failure> {
        scan(Optional<(Output?, Output)>.none) { ($0?.1, $1) }
            .compactMap { $0 }
    }

    func withPrevious(_ initialPreviousValue: Output) -> some Publisher<(previous: Output, current: Output), Failure> {
        scan((initialPreviousValue, initialPreviousValue)) { ($0.1, $1) }
    }
}

class ViewModel: ObservableObject {
    @Published var musicLibrary = ObservableMusicLibrary()
    @Published var libraryCommands = LibraryCommands()
    @Published var alertModel = AlertModel()

    @Published var currentView = ShowView.Stub
    @Published var previousView: ShowView?

    @Published var sidebarModel = SidebarModel()

    private var ac: [AnyCancellable] = []

    init() {
        ac.append(musicLibrary
            .objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.objectWillChange.send() }
        )

        $currentView
            .withPrevious()
            .map { $0.0 }
            .assign(to: &$previousView)

        musicLibrary.$processing
            .compactMap { $0 ? .Discover : nil }
            .assign(to: &$currentView)
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
}
