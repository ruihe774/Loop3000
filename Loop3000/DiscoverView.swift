import SwiftUI
import Combine

extension URL: Identifiable {
    public var id: String {
        absoluteString
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var windowModel: WindowModel

    @State private var refreshTick = 0
    private var dotCount: Int {
        refreshTick / 2 % 4
    }

    private var sortedImportedTracks: [Track] {
        model.musicLibrary.sorted(tracks: model.musicLibrary.importedTracks)
    }

    var body: some View {
        if model.musicLibrary.processing {
            VStack(alignment: .leading, spacing: 0) {
                Label("Discovering your music" + String(repeating: ".", count: dotCount), systemImage: "magnifyingglass.circle")
                    .font(.headline)
                    .symbolRenderingMode(.hierarchical)
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
                    List(model.musicLibrary.requesting.dropDuplicates()) { url in
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.5)
                            Text(url.pathDescription)
                                .help(url.pathDescription)
                                .scaledToFit()
                        }
                        .frame(height: 16)
                    }
                    .listStyle(.plain)
                }
            }
            .onReceive(model.refreshTimer, perform: { _ in
                refreshTick += 1
            })
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !model.musicLibrary.importedTracks.isEmpty {
                    Label("Imported music", systemImage: "square.and.arrow.down.on.square")
                        .font(.headline)
                        .padding()
                    Divider()
                    PlaylistView(tracks: sortedImportedTracks)
                } else if model.musicLibrary.returnedErrors.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Your music library is up to date.")
                        Spacer()
                    }
                    Spacer()
                }
                Divider()
                if !model.musicLibrary.returnedErrors.isEmpty {
                    Label("Encountered errors", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .symbolRenderingMode(.multicolor)
                        .padding()
                    Divider()
                    List(model.musicLibrary.returnedErrors.map { (id: UUID(), error: $0) }, id: \.id) { (_, error) in
                        let description = (error as CustomStringConvertible).description
                        Text(description)
                    }
                    .frame(idealHeight: 100)
                    Divider()
                }
                HStack {
                    Spacer()
                    Button {
                        windowModel.switchToPreviousView()
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
}
