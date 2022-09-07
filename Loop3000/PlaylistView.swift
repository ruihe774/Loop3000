import SwiftUI

fileprivate struct MusicPieceView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var windowModel: WindowModel

    @State private var lastTap = DispatchTime.init(uptimeNanoseconds: 0)

    private var piece: MusicPiece

    private var selected: Bool {
        windowModel.selectedPiece == piece || windowModel.selectedPieces.contains(piece)
    }

    private var currentPlaying: Bool {
        return model.playingPiece == piece && model.playbackState == .playing
    }

    private var currentPaused: Bool {
        model.playingPiece == piece && model.playbackState == .paused
    }

    init(_ piece: MusicPiece) {
        self.piece = piece
    }

    var body: some View {
        Button {
            let now = DispatchTime.now()
            if now.uptimeNanoseconds - lastTap.uptimeNanoseconds < 300000000 {
                model.play(piece)
            } else {
                windowModel.selectedPiece = piece
            }
            lastTap = now
        } label: {
            HStack {
                (currentPlaying || currentPaused ?
                    Label(currentPaused ? "Paused" : "Playing", systemImage: currentPaused ? "pause.fill" : "play.fill")
                    .foregroundColor(.secondary) :
                    Label("Track", systemImage: "list.bullet")
                    .foregroundColor(.clear))
                    .labelStyle(.iconOnly)
                    .frame(width: 10)
                Text(piece.indexString ?? "")
                    .font(.body.monospacedDigit())
                    .frame(width: 30)
                Text(piece.combinedTitle)
                    .help(piece.combinedTitle)
                    .scaledToFit()
                Spacer()
                Text(piece.durationString ?? "")
                    .help(piece.duration?.description ?? "")
                    .font(.body.monospacedDigit())
            }
            .frame(height: 20)
            .padding(.leading, 10)
            .padding(.trailing, 30)
        }
        .buttonStyle(.borderless)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(selected ? Color.selectedBackgroundColor : .clear))
        .foregroundColor(.primary)
    }
}

struct PlaylistView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var windowModel: WindowModel

    @MainActor
    private struct AlbumSection: Identifiable {
        var pieces: [MusicPiece]

        let id: UUID

        var album: Album? {
            pieces.first!.album
        }

        var title: String {
            pieces.first!.combinedAlbumTitle ?? "<No Title>"
        }

        init(pieces: [MusicPiece]) {
            self.id = pieces.first!.id
            self.pieces = pieces
        }
    }

    private let playlistId: UUID?
    private var tracks: [Track]?

    private var playlist: Playlist? {
        playlistId.flatMap { model.musicLibrary.playlists[$0] }
    }

    private var pieces: [MusicPiece] {
        if let playlist {
            return playlist.items.map {
                MusicPiece($0, musicLibrary: model.musicLibrary)
            }
        } else {
            return tracks!.map {
                MusicPiece($0, musicLibrary: model.musicLibrary)
            }
        }
    }

    private var sections: [AlbumSection] {
        var sections = [AlbumSection]()
        for piece in pieces {
            if sections.last?.album == piece.album {
                sections[sections.count - 1].pieces.append(piece)
            } else {
                sections.append(AlbumSection(pieces: [piece]))
            }
        }
        return sections
    }

    @State private var selectedPiece: MusicPiece?

    init(tracks: [Track]) {
        self.tracks = tracks
        self.playlistId = nil
    }

    init(_ playlistId: UUID) {
        self.tracks = nil
        self.playlistId = playlistId
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack {
                    ForEach(pieces) { piece in
                        if let section = sections.first(where: { $0.pieces.first! == piece }) {
                            MusicPieceView(piece)
                                .padding(.top, 30)
                                .overlay(alignment: .topLeading) {
                                    Text(section.title)
                                        .font(.callout.bold())
                                        .foregroundColor(.secondary)
                                        .frame(height: 30)
                                }
                        } else {
                            MusicPieceView(piece)
                        }
                    }
                }
                .padding([.leading, .trailing, .bottom])
            }
            .background(.background)
            if let selectedPiece {
                Divider()
                MetadataView(selectedPiece)
            }
        }
        .onAnimatedValue(of: windowModel.selectedPiece) {
            selectedPiece = $0.flatMap { $0.playlistId == playlistId ? $0 : nil }
        }
        .onAnimatedValue(of: playlistId, onAppear: false) { playlistId in
            selectedPiece = windowModel.selectedPiece.flatMap { $0.playlistId == playlistId ? $0 : nil }
        }
    }
}

fileprivate struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

fileprivate struct SizeModifier: ViewModifier {
    private var sizeView: some View {
        GeometryReader { geo in
            Color.clear.preference(key: SizePreferenceKey.self, value: geo.size)
        }
    }

    func body(content: Content) -> some View {
        content.overlay(sizeView)
    }
}

fileprivate extension View {
    func getSize(perform: @escaping (CGSize) -> ()) -> some View {
        self
            .modifier(SizeModifier())
            .onPreferenceChange(SizePreferenceKey.self) {
                perform($0)
            }
    }
}

fileprivate struct AdaptiveScrollView<Content>: View where Content: View {
    private let content: Content
    private let axes: Axis.Set
    @State private var contentSize: CGSize = .zero
    @State private var geoSize: CGSize = .zero
    private var frameWidth: CGFloat? {
        if axes.contains(.horizontal) {
            return contentSize.width <= geoSize.width ? contentSize.width : nil
        } else {
            return contentSize.width
        }
    }
    private var frameHeight: CGFloat? {
        if axes.contains(.vertical) {
            return contentSize.height < geoSize.height ? contentSize.height : nil
        } else {
            return contentSize.height
        }
    }

    init(_ axes: Axis.Set = .vertical, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(axes) {
                content
                    .getSize { contentSize = $0 }
            }
            .onChange(of: geo.size) { geoSize in
                self.geoSize = geoSize
            }
        }
        .frame(width: frameWidth, height: frameHeight)
    }
}

fileprivate struct MetadataItemView: View {
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

    init(label: String, text: String, scrollable: Bool = false, selectable: Bool = true) {
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
                AdaptiveScrollView(.horizontal) {
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

fileprivate struct MetadataView: View {
    @EnvironmentObject private var model: AppModel

    private let piece: MusicPiece
    private var coverData: Data? {
        piece.album?.cover
    }
    @State private var coverImage: CGImage?

    init(_ piece: MusicPiece) {
        self.piece = piece
    }

    var body: some View {
        ZStack {
            if let coverImage {
                GeometryReader { geo in
                    ZStack(alignment: .center) {
                        Image(decorative: coverImage, scale: 1)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            } else {
                Rectangle().fill(Color(nsColor: .controlBackgroundColor))
            }
            VStack {
                if let coverImage {
                    Image(coverImage, scale: 1, label: Text("Cover Artwork"))
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(3)
                        .shadow(radius: 1)
                }
                ScrollView {
                    VStack(spacing: 5) {
                        if let title = piece.title {
                            MetadataItemView(label: "Title", text: title)
                        }
                        if let album = piece.albumTitle {
                            MetadataItemView(label: "Album", text: album)
                        }
                        let artists = piece.artists
                        if !artists.isEmpty {
                            let artistLabel = artists.count > 1 ? "Artists" : "Artist"
                            MetadataItemView(label: artistLabel, text: artists.joined(separator: "\n"))
                        }
                        let albumArtists = piece.albumArtists
                        if !albumArtists.isEmpty && artists != albumArtists {
                            let artistLabel = albumArtists.count > 1 ? "Artists" : "Artist"
                            MetadataItemView(label: "Album " + artistLabel, text: albumArtists.joined(separator: "\n"))
                        }
                        if let discNumber = piece.discNumber {
                            MetadataItemView(label: "Disc Number", text: "\(discNumber)")
                        }
                        if let trackNumber = piece.trackNumber {
                            MetadataItemView(label: "Track Number", text: "\(trackNumber)")
                        }
                        if let duration = piece.durationString {
                            MetadataItemView(label: "Duration", text: duration)
                        }
                        // XXX: Add more field
                        if let track = piece.track {
                            let isFile = track.source.isFileURL
                            MetadataItemView(
                                label: isFile ? "File" : "URL",
                                text: isFile ? track.source.lastPathComponent : track.source.description,
                                scrollable: true,
                                selectable: !isFile
                            )
                            .clickable(enabled: isFile)
                            .onTapGesture {
                                Task {
                                    (try? await model.musicLibrary.startAccess(url: track.source)).map {
                                        NSWorkspace.shared.activateFileViewerSelecting([$0])
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .padding()
            .background(.thickMaterial)
        }
        .frame(width: 250)
        .onChange(of: coverData, perform: updateImage)
        .onAppear {
            updateImage(coverData)
        }
    }

    private func updateImage(_ coverData: Data?) {
        coverImage = coverData.map { loadImage(from: $0) }
    }
}

