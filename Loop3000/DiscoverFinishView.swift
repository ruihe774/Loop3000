import SwiftUI

struct DiscoverFinishView: View {
    @EnvironmentObject var model: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Imported music")
                .font(.headline)
                .padding()
            Divider()
            List(model.musicLibrary.albums) { album in
                Section(album.metadata[MetadataCommonKey.title] ?? "<No title>") {
                    ForEach(model.musicLibrary.getTracks(for: album).filter { track in (model.musicLibrary.importedTracks ?? []).contains { $0.id == track.id } }) { track in
                        let text = track.metadata[MetadataCommonKey.title] ?? "<No title>"
                        Text(text)
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button {
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
