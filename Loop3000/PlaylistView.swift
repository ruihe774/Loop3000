import SwiftUI

fileprivate struct PlaylistViewItem: Unicorn {
    let id: UUID
    let track: Track
    let album: Album
    let playlistItem: PlaylistItem?
    let playlist: Playlist?

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
        track.metadata[MetadataCommonKey.trackNumber].flatMap { Int($0) }
    }

    var discNumber: Int? {
        track.metadata[MetadataCommonKey.discNumber].flatMap { Int($0) }
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

    init(track: Track, album: Album, playlistItem: PlaylistItem?, playlist: Playlist?) {
        self.id = playlistItem?.id ?? track.id
        self.track = track
        self.album = album
        self.playlistItem = playlistItem
        self.playlist = playlist
    }
}

fileprivate struct PlaylistItemView: View {
    @EnvironmentObject private var model: ViewModel

    @State private var lastTap = DispatchTime.init(uptimeNanoseconds: 0)

    private var viewItem: PlaylistViewItem

    private var selected: Bool {
        viewItem.playlistItem != nil && model.selectedItem == viewItem.playlistItem
    }

    private var currentPlaying: Bool {
        viewItem.playlistItem != nil && model.playing && model.playingItem == viewItem.playlistItem
    }

    private var currentPausd: Bool {
        viewItem.playlistItem != nil && model.paused && model.playingItem == viewItem.playlistItem
    }

    init(_ viewItem: PlaylistViewItem) {
        self.viewItem = viewItem
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Color(nsColor: .quaternaryLabelColor) : Color.black.opacity(0.001))
            HStack {
                (currentPlaying || currentPausd ?
                    Label(currentPausd ? "Paused" : "Playing", systemImage: currentPausd ? "pause.fill" : "play.fill")
                    .foregroundColor(.secondary) :
                    Label("Item", systemImage: "list.bullet")
                    .foregroundColor(.clear))
                    .labelStyle(.iconOnly)
                    .frame(width: 10)
                Text(viewItem.indexString ?? "")
                    .font(.body.monospacedDigit())
                    .frame(width: 30)
                Text(viewItem.combinedTitle)
                    .help(viewItem.combinedTitle)
                    .scaledToFit()
                Spacer()
                Text(viewItem.duration ?? "")
                    .font(.body.monospacedDigit())
            }
            .frame(height: 20)
            .padding(.leading, 10)
            .padding(.trailing, 30)
        }
        .onTapGesture {
            guard let playlistItem = viewItem.playlistItem else { return }
            let now = DispatchTime.now()
            if now.uptimeNanoseconds - lastTap.uptimeNanoseconds < 300000000 {
                model.play(playlistItem)
            } else {
                model.selectedItem = playlistItem
            }
            lastTap = now
        }
    }
}

struct PlaylistView: View {
    @EnvironmentObject private var model: ViewModel

    private struct SectionItem: Identifiable {
        let id: UUID
        let album: Album
        var items: [PlaylistViewItem]

        init(album: Album, items: [PlaylistViewItem]) {
            self.id = items.first!.id
            self.album = album
            self.items = items
        }
    }

    private let playlist: Playlist?
    private var tracks: [Track]?
    private var viewItems: [PlaylistViewItem] {
        if let playlist {
            return playlist.items.map {
                let track = model.musicLibrary.getTrack(by: $0.trackId)
                let album = model.musicLibrary.getAlbum(for: track)
                return PlaylistViewItem(track: track, album: album, playlistItem: $0, playlist: playlist)
            }
        } else {
            return tracks!.map {
                return PlaylistViewItem(
                    track: $0,
                    album: model.musicLibrary.getAlbum(for: $0),
                    playlistItem: nil,
                    playlist: nil
                )
            }
        }
    }
    private var sections: [SectionItem] {
        var sections = [SectionItem]()
        for item in viewItems {
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
        self.playlist = nil
    }

    init(_ playlist: Playlist) {
        self.tracks = nil
        self.playlist = playlist
    }

    var body: some View {
        List(sections) { section in
            let items = section.items
            Section(items.first!.combinedAlbumTitle ?? "<No Title>") {
                ForEach(items) { item in
                    PlaylistItemView(item)
                }
            }
        }
    }
}
