import SwiftUI
import CoreGraphics

fileprivate struct PlaylistViewItem: Unicorn {
    let id: UUID
    let track: Track
    let album: Album
    let playlistItem: PlaylistItem?
    let playlist: Playlist?

    var title: String? {
        track.metadata[MetadataCommonKey.title]
    }

    var uiTitle: String {
        title ?? track.source.lastPathComponent
    }

    var artists: [String] {
        let artistsString = track.metadata[MetadataCommonKey.artist]
            ?? album.metadata[MetadataCommonKey.artist]
            ?? ""
        switch artistsString {
        case "Various Artists": fallthrough
        case "V.A.": fallthrough
        case "VA": return []
        default:
            return universalSplit(
                artistsString
            )
        }
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
        let artistsString = album.metadata[MetadataCommonKey.artist] ?? ""
        switch artistsString {
        case "Various Artists": fallthrough
        case "V.A.": fallthrough
        case "VA": return []
        default:
            return universalSplit(
                artistsString
            )
        }
    }

    var combinedTitle: String {
        if !artists.isEmpty && artists != albumArtists {
            return uiTitle + " / " + artists.joined(separator: "; ")
        } else {
            return uiTitle
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
        return Timestamp(value: track.end.value - track.start.value).briefDescription
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
        viewItem.playlistItem != nil && model.selectedItem == viewItem.playlistItem?.id
    }

    private var currentPlaying: Bool {
        viewItem.playlistItem != nil && model.playing && model.playingItem == viewItem.playlistItem?.id
    }

    private var currentPausd: Bool {
        viewItem.playlistItem != nil && model.paused && model.playingItem == viewItem.playlistItem?.id
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
                model.play(playlistItem.id)
            } else {
                model.selectedItem = playlistItem.id
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
    private var selectedViewItem: PlaylistViewItem? {
        guard let (list, item) = model.selectedItem.flatMap({ model.musicLibrary.locatePlaylistItem(by: $0) }) else {
            return nil
        }
        guard list == playlist else {
            return nil
        }
        let track = model.musicLibrary.getTrack(by: item.trackId)
        let album = model.musicLibrary.getAlbum(for: track)
        return PlaylistViewItem(track: track, album: album, playlistItem: item, playlist: list)
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
        HStack(spacing: 0) {
            List(sections) { section in
                let items = section.items
                Section(items.first!.combinedAlbumTitle ?? "<No Title>") {
                    ForEach(items) { item in
                        PlaylistItemView(item)
                    }
                }
            }
            if let selectedViewItem {
                Divider()
                MetadataView(selectedViewItem)
            }
        }
    }
}

struct MetadataItemView: View {
    private let label: String
    private let text: String
    private let scrollable: Bool
    private let selectable: Bool

    private var textView: some View {
        ZStack {
            if selectable {
                Text(text)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(text)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    fileprivate init(label: String, text: String, scrollable: Bool = false, selectable: Bool = true) {
        self.label = label
        self.text = text
        self.scrollable = scrollable
        self.selectable = selectable
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer(minLength: 15)
            if scrollable {
                ScrollView(.horizontal) {
                    textView
                }
                .scrollIndicators(.never)
            } else {
                textView
            }
        }
        .font(.caption.weight(.medium))
    }
}

struct MetadataView: View {
    @EnvironmentObject private var model: ViewModel

    private let viewItem: PlaylistViewItem
    private var coverJPEG: Data? {
        viewItem.album.coverJPEG
    }
    @State private var coverImage: CGImage?

    fileprivate init(_ viewItem: PlaylistViewItem) {
        self.viewItem = viewItem
    }

    var body: some View {
        ZStack {
            if let coverImage {
                GeometryReader { geo in
                    Image(coverImage, scale: 1, label: Text("Background"))
                        .resizable()
                        .frame(height: geo.size.height)
                }
            } else {
                Rectangle().fill(Color(nsColor: .controlBackgroundColor))
            }
            VStack {
                if let coverImage {
                    Image(coverImage, scale: 1, label: Text("Cover Artwork"))
                        .resizable()
                        .scaledToFit()
                        .shadow(radius: 1)
                }
                VStack(spacing: 5) {
                    if let title = viewItem.title {
                        MetadataItemView(label: "Title", text: title)
                    }
                    if let album = viewItem.albumTitle {
                        MetadataItemView(label: "Album", text: album)
                    }
                    let artists = viewItem.artists
                    if !artists.isEmpty {
                        let artistLabel = artists.count > 1 ? "Artists" : "Artist"
                        MetadataItemView(label: artistLabel, text: artists.joined(separator: "\n"))
                    }
                    let albumArtists = viewItem.albumArtists
                    if !albumArtists.isEmpty && artists != albumArtists {
                        let artistLabel = albumArtists.count > 1 ? "Artists" : "Artist"
                        MetadataItemView(label: "Album " + artistLabel, text: albumArtists.joined(separator: "\n"))
                    }
                    if let discNumber = viewItem.discNumber {
                        MetadataItemView(label: "Disc Number", text: "\(discNumber)")
                    }
                    if let trackNumber = viewItem.trackNumber {
                        MetadataItemView(label: "Track Number", text: "\(trackNumber)")
                    }
                    if let duration = viewItem.duration {
                        MetadataItemView(label: "Duration", text: duration)
                    }
                    // XXX: Add more field
                    let isFile = viewItem.track.source.isFileURL
                    MetadataItemView(
                        label: isFile ? "File" : "URL",
                        text: isFile ? viewItem.track.source.path : viewItem.track.source.description,
                        scrollable: true,
                        selectable: !isFile
                    )
                    .onTapGesture {
                        if isFile {
                            NSWorkspace.shared.activateFileViewerSelecting([viewItem.track.source])
                        }
                    }
                }
                .padding()
                Spacer()
            }
            .padding()
            .background(.thickMaterial)
        }
        .frame(width: 250)
        .onChange(of: coverJPEG, perform: updateImage)
        .onAppear {
            updateImage(coverJPEG)
        }
    }

    private func updateImage(_ coverJPEG: Data?) {
        coverImage = coverJPEG.map { data in
            CGImage(
                jpegDataProviderSource: CGDataProvider(data: data as CFData)!,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )!
        }
    }
}

