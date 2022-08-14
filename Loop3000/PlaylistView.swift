import SwiftUI

struct PlayItem: Identifiable {
    let id = UUID()
    let track: Track
    let album: Album

    private func universalSplit(_ s: String) -> [String] {
        s
            .split { ",;，；、\r\n".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var title: String {
        track.metadata[MetadataCommonKey.title] ?? track.source.lastPathComponent
    }

    var artists: [String] {
        universalSplit(
            track.metadata[MetadataCommonKey.artist] ??
            album.metadata[MetadataCommonKey.artist] ??
            ""
        )
    }

    var trackNumber: Int? {
        if let numberString = track.metadata[MetadataCommonKey.trackNumber] {
            return Int(numberString)
        } else {
            return nil
        }
    }

    var discNumber: Int? {
        if let numberString = track.metadata[MetadataCommonKey.discNumber] {
            return Int(numberString)
        } else {
            return nil
        }
    }

    var indexString: String? {
        guard let trackNumber = trackNumber else { return nil }
        if let discNumber = discNumber {
            return String(format: "%d.%02d", discNumber, trackNumber)
        } else {
            return String(format: "%02d", trackNumber)
        }
    }

    var albumTitle: String? {
        album.metadata[MetadataCommonKey.title]
    }

    var albumArtists: [String] {
        universalSplit(
            album.metadata[MetadataCommonKey.artist] ??
            ""
        )
    }

    var combinedTitle: String {
        if !artists.isEmpty && artists != albumArtists {
            return title + " / " + artists.joined(separator: "; ")
        } else {
            return title
        }
    }

    var combinedAlbumTitle: String? {
        guard let albumTitle = albumTitle else { return nil }
        if albumArtists.isEmpty {
            return albumTitle
        } else {
            return albumTitle + " / " + albumArtists.joined(separator: "; ")
        }
    }

    var duration: String? {
        let durationValue = track.end.value - track.start.value
        guard durationValue >= 0 else { return nil }
        let s = Timestamp(value: track.end.value - track.start.value).description
        return String(s[..<s.index(s.startIndex, offsetBy: 5)])
    }

    init(track: Track, album: Album) {
        assert(track.albumId == album.id)
        self.track = track
        self.album = album
    }
}

struct PlayItemView: View {
    @EnvironmentObject var model: ViewModel

    var playItem: PlayItem

    var selected: Bool {
        model.selectedItem == playItem.id
    }

    var playing: Bool {
        model.playingItem == playItem.id
    }

    init(_ playItem: PlayItem) {
        self.playItem = playItem
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? Color.primary.opacity(0.2) : Color.black.opacity(0.001))
                .cornerRadius(5)
            HStack {
                Image(systemName: "play.fill")
                    .foregroundColor(playing ? .secondary : .clear)
                Text(playItem.indexString ?? "")
                    .font(.body.monospacedDigit())
                    .frame(width: 30)
                Text(playItem.combinedTitle)
                    .scaledToFit()
                Spacer()
                Text(playItem.duration ?? "")
                    .font(.body.monospacedDigit())
            }
            .frame(height: 20)
            .padding(.leading, 10)
            .padding(.trailing, 30)
        }
        .onTapGesture(count: 2) {
            print("awd")
            model.playingItem = playItem.id
        }
        .onTapGesture(count: 1) {
            model.selectedItem = playItem.id
        }
    }
}

struct PlaylistView: View {
    @EnvironmentObject var model: ViewModel

    struct SectionItem: Identifiable {
        let id: UUID
        let album: Album
        var items: [PlayItem]

        init(album: Album, items: [PlayItem]) {
            self.album = album
            self.items = items
            self.id = album.id
        }
    }

    let listId: UUID?
    var tracks: [Track]?
    var items: [PlayItem] {
        if let listId = listId {
            return model.musicLibrary.getPlaylist(id: listId).items
        } else {
            return tracks!.map { PlayItem(track: $0, album: model.musicLibrary.getAlbum(for: $0)) }
        }
    }
    var sections: [SectionItem] {
        var sections = [SectionItem]()
        for item in items {
            if sections.last?.album.id == item.album.id {
                sections[sections.count - 1].items.append(item)
            } else {
                sections.append(SectionItem(album: item.album, items: [item]))
            }
        }
        return sections
    }

    init(tracks: [Track]) {
        self.tracks = tracks
        self.listId = nil
    }

    init(_ listId: UUID) {
        self.tracks = nil
        self.listId = listId
    }

    var body: some View {
        List(sections) { section in
            let items = section.items
            Section(items.first!.combinedAlbumTitle ?? "<No Title>") {
                ForEach(items) { item in
                    PlayItemView(item)
                }
            }
        }
    }
}
