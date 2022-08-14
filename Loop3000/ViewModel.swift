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
    @Published private(set) var importedAlbums: [Album]?
    @Published private(set) var importedTracks: [Track]?

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
        importedAlbums = nil
        importedTracks = nil
    }

    func getTracks(for album: Album) -> [Track] {
        backstore.getTracks(for: album)
    }

    var canImportTypes: [UTType] {
        self.backstore.canImportTypes
    }

    var canGrabTypes: [UTType] {
        self.backstore.canGrabTypes
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
    case DiscoverFinish
    case Stub
}

class ViewModel: ObservableObject {
    @Published var musicLibrary = ObservableMusicLibrary()
    @Published var libraryCommands = LibraryCommands()
    @Published var alertModel = AlertModel()

    @Published var currentView = ShowView.Stub

    private var ac: [AnyCancellable] = []

    init() {
        ac.append(musicLibrary
            .objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in self.objectWillChange.send() }
        )

        musicLibrary.$processing
            .compactMap { $0 ? .Discover : nil }
            .assign(to: &$currentView)

        Publishers.CombineLatest(musicLibrary.$importedAlbums, musicLibrary.$importedTracks)
            .map { item in item.0 != nil && item.1 != nil ? .DiscoverFinish : .Stub }
            .assign(to: &$currentView)
    }

    func alert(title: String, message: String) {
        alertModel.title = title
        alertModel.message = message
        alertModel.isPresented = true
    }
}
