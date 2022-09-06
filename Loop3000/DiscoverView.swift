import SwiftUI

extension URL: Identifiable {
    public var id: String {
        normalizedString
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

    @State private var processing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if processing {
                Text("Discovering your music" + String(repeating: ".", count: dotCount))
                    .font(.headline)
                    .padding()
                    .onReceive(model.guiRefreshTimer, perform: { _ in
                        refreshTick += 1
                    })
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
            } else {
                if !model.musicLibrary.importedTracks.isEmpty {
                    Label("Imported music", systemImage: "square.and.arrow.down.on.square")
                        .font(.headline)
                        .padding()
                    Divider()
                    PlaylistView(tracks: sortedImportedTracks)
                } else if model.musicLibrary.returnedErrors.isEmpty {
                    Spacer(minLength: 50)
                    HStack {
                        Spacer()
                        Text("Your music library is up to date.")
                        Spacer()
                    }
                    Spacer(minLength: 50)
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
        .onAnimatedValue(of: model.musicLibrary.processing) {
            processing = $0
        }
    }
}
