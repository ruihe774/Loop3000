import SwiftUI

fileprivate struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context _: Self.Context) -> NSView {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        return visualEffect
    }
    func updateNSView(_: NSView, context _: Context) {}
}

struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var windowModel: WindowModel

    @State private var filterString = ""

    private enum ListType {
        case albums
        case playlists
    }
    @State private var listType = ListType.albums

    var body: some View {
        VStack {
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
                .padding(.bottom, 10)
                .disabled(true)
            HStack(spacing: 15) {
                Button {
                    listType = .albums
                } label: {
                    Label("Albums", systemImage: listType == .albums ? "opticaldisc.fill" : "opticaldisc")
                        .labelStyle(.iconOnly)
                }
                .foregroundColor(listType == .albums ? .accentColor : .secondary)
                .buttonStyle(.plain)
                Button {
                    listType = .playlists
                } label: {
                    Label("Playlists", systemImage: "music.note.list")
                        .labelStyle(.iconOnly)
                }
                .foregroundColor(listType == .playlists ? .accentColor : .secondary)
                .buttonStyle(.plain)
                .disabled(true)
            }
            .font(.title2)
            ScrollView {
                LazyVStack(spacing: -4) {
                    ForEach(
                        listType == .albums ? model.musicLibrary.albumPlaylists : model.musicLibrary.manualPlaylists
                    ) { playlist in
                        let selected = windowModel.selectedList == playlist.id
                        Button {
                            windowModel.selectedList = playlist.id
                        } label: {
                            ScrollView(.horizontal) {
                                Text(playlist.title)
                                    .help(playlist.title)
                            }
                            .scrollIndicators(.never)
                            .padding(6)
                        }
                        .buttonStyle(.plain)
                        .padding(2)
                        .background(selected ? Color(nsColor: .quaternaryLabelColor) : .clear)
                        .cornerRadius(8)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .scenePadding([.leading, .trailing])
        .padding([.top, .bottom], 30)
        .frame(width: 250)
        .background(SidebarMaterial())
        .onAppear {
            guard let selectedList = windowModel.selectedList else { return }
            listType = model.musicLibrary.albumPlaylists.contains(where: { $0.id == selectedList }) ? .albums : .playlists
        }
    }
}
