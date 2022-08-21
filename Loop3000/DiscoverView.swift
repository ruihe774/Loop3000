import SwiftUI
import Combine

extension URL: Identifiable {
    public var id: String {
        absoluteString
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var model: ViewModel

    @State private var dotCount = 0
    private var dotTimer = Timer.publish(every: 0.5, on: .main, in: .default)

    private var sortedImportedTracks: [Track] {
        model.musicLibrary.sorted(tracks: model.musicLibrary.importedTracks)
    }

    private var errors: [Error] {
        if let thrownError = model.musicLibrary.thrownError {
            return [thrownError] + model.musicLibrary.returnedError
        } else {
            return model.musicLibrary.returnedError
        }
    }

    var body: some View {
        if model.musicLibrary.processing {
            VStack(alignment: .leading, spacing: 0) {
                Text("Discovering your music" + String(repeating: ".", count: dotCount))
                    .font(.headline)
                    .padding()
                Divider()
                if model.musicLibrary.requesting.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    Spacer()
                } else {
                    List(dedup(model.musicLibrary.requesting)) { url in
                        let text = url.isFileURL ? url.path : url.absoluteString
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.5)
                            Text(text)
                                .help(text)
                                .scaledToFit()
                        }
                        .frame(height: 16)
                    }
                    .listStyle(.plain)
                }
            }
            .onReceive(dotTimer, perform: { _ in
                self.dotCount = (self.dotCount + 1) % 4
            })
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if model.musicLibrary.thrownError == nil {
                    if !model.musicLibrary.importedTracks.isEmpty {
                        Label("Imported music", systemImage: "square.and.arrow.down.on.square")
                            .font(.headline)
                            .padding()
                        Divider()
                        PlaylistView(tracks: sortedImportedTracks)
                    } else {
                        Spacer(minLength: 50)
                        HStack {
                            Spacer()
                            Text("Your music library is up to date.")
                            Spacer()
                        }
                        Spacer(minLength: 50)
                    }
                }
                Divider()
                if !errors.isEmpty {
                    Label("Encountered errors", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                        .foregroundColor(model.musicLibrary.thrownError == nil ? .yellow : .red)
                        .padding()
                    Divider()
                    List(errors.map { (id: UUID(), error: $0) }, id: \.id) { (_, error) in
                        let description = (error as CustomStringConvertible).description
                        Text(description)
                    }
                    .frame(idealHeight: 100)
                }
                HStack {
                    Spacer()
                    Button {
                        model.switchToPreviousView()
                        model.musicLibrary.clearResult()
                    } label: {
                        Text("OK")
                            .frame(width: 50)
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
    }

    private func dedup(_ urls: [URL]) -> [URL] {
        var uniques: [URL] = []
        var met: Set<URL> = []
        for url in urls {
            if !met.contains(url) {
                uniques.append(url)
                met.insert(url)
            }
        }
        return uniques
    }

    private var ac: [any Cancellable] = []

    init() {
        ac.append(dotTimer.connect())
    }
}
