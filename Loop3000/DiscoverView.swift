import SwiftUI
import Combine

extension URL: Identifiable {
    public var id: String {
        absoluteString
    }
}

struct DiscoverView: View {
    @EnvironmentObject var model: ViewModel

    @State private var dotCount = 0
    private var dotTimer = Timer.publish(every: 0.5, on: .main, in: .default)

    var sortedImportedTracks: [Track] {
        model.musicLibrary.sorted(tracks: model.musicLibrary.importedTracks)
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
                        ProgressView().scaleEffect(2)
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
                if !model.musicLibrary.importedTracks.isEmpty {
                    Text("Imported music")
                        .font(.headline)
                        .padding()
                    Divider()
                    PlaylistView(tracks: sortedImportedTracks)
                    Divider()
                } else {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Your music library is up to date.")
                        Spacer()
                    }
                    Spacer()
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
