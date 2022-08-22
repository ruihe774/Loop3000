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
    @EnvironmentObject private var model: ViewModel

    @State private var filterString = ""

    private enum ListType {
        case Albums
        case Playlists
    }
    @State private var listType = ListType.Albums

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
                    listType = .Albums
                } label: {
                    Label("Albums", systemImage: listType == .Albums ? "opticaldisc.fill" : "opticaldisc")
                        .labelStyle(.iconOnly)
                }
                .foregroundColor(listType == .Albums ? .accentColor : .secondary)
                .buttonStyle(.borderless)
                Button {
                    listType = .Playlists
                } label: {
                    Label("Playlists", systemImage: "music.note.list")
                        .labelStyle(.iconOnly)
                }
                .foregroundColor(listType == .Playlists ? .accentColor : .secondary)
                .buttonStyle(.borderless)
                .disabled(true)
            }
            .font(.title2)
            ScrollView {
                LazyVStack(spacing: -4) {
                    ForEach(
                        listType == .Albums ? model.musicLibrary.albumPlaylists : model.musicLibrary.manualPlaylists
                    ) { playlist in
                        let selected = model.selectedList == playlist.id
                        Button {
                            model.selectedList = playlist.id
                        } label: {
                            HStack {
                                Text(playlist.title)
                                    .help(playlist.title)
                                    .foregroundColor(.primary)
                                    .scaledToFit()
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderless)
                        .padding(8)
                        .background(selected ? Color(nsColor: .quaternaryLabelColor) : .clear)
                        .cornerRadius(8)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .scenePadding([.leading, .trailing])
        .padding([.top, .bottom], 30)
        .frame(width: 300)
        .background(SidebarMaterial())
        .onAppear {
            guard let selectedList = model.selectedList else { return }
            listType = model.musicLibrary.albumPlaylists.contains(where: { $0.id == selectedList }) ? .Albums : .Playlists
        }
    }
}
