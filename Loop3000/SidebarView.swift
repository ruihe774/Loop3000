import SwiftUI

fileprivate struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context _: Self.Context) -> NSView {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        return visualEffect
    }
    func updateNSView(_: NSView, context _: Context) {}
}

fileprivate struct SidebarList: View {
    @EnvironmentObject private var windowModel: WindowModel

    let playlists: [Playlist]

    var body: some View {
        LazyVStack(spacing: -4) {
            ForEach(playlists) { playlist in
                let selected = windowModel.selectedList == playlist.id
                Button {
                    windowModel.selectedList = playlist.id
                } label: {
                    ScrollView(.horizontal) {
                        Text(playlist.title)
                            .help(playlist.title)
                            .foregroundColor(.primary)
                    }
                    .scrollIndicators(.never)
                    .padding(6)
                }
                .buttonStyle(.borderless)
                .padding(2)
                .background(selected ? Color.selectedBackgroundColor : .clear)
                .cornerRadius(8)
            }
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var windowModel: WindowModel

    private enum ListType {
        case albums
        case playlists
    }
    @State private var listType = ListType.albums

    @State private var filterString = ""

    var body: some View {
        VStack(spacing: 15) {
            TextField(text: $filterString) {}
                .padding(.leading, 23.5)
                .overlay {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        filterString.isEmpty ? Text("Search") : nil
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                }
                .padding([.leading, .trailing], 10)
                .frame(height: 30)
                .textFieldStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
                .scenePadding([.leading, .trailing])
                .disabled(true)
            ScrollView {
                VStack(alignment: .leading) {
                    if !model.musicLibrary.manualPlaylists.isEmpty {
                        Text("Playlists")
                            .font(.callout.bold())
                            .foregroundColor(.secondary)
                            .padding(.bottom, -4)
                        SidebarList(playlists: model.musicLibrary.manualPlaylists)
                    }
                    if !model.musicLibrary.albumPlaylists.isEmpty {
                        Text("Albums")
                            .font(.callout.bold())
                            .foregroundColor(.secondary)
                            .padding(.bottom, -4)
                        SidebarList(playlists: model.musicLibrary.albumPlaylists)
                    }
                }
                .scenePadding([.leading, .trailing])
            }
            .scrollContentBackground(.hidden)
        }
        .padding([.top, .bottom], 30)
        .frame(width: 250)
        .background(SidebarMaterial())
        .onAppear {
            guard let selectedList = windowModel.selectedList else { return }
            listType = model.musicLibrary.albumPlaylists.contains(where: { $0.id == selectedList }) ? .albums : .playlists
        }
    }
}
