import SwiftUI

struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context _: Self.Context) -> NSView {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        return visualEffect
    }
    func updateNSView(_: NSView, context _: Context) {}
}

extension Album {
    var title: String? {
        get {
            metadata[MetadataCommonKey.title]
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var model: ViewModel
    @State var filterString = ""

    var body: some View {
        VStack {
            TextField(text: $filterString) {}
                .overlay {
                    HStack {
                        filterString.isEmpty ? Image(systemName: "magnifyingglass") : nil
                        filterString.isEmpty ? Text("Search") : nil
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                }
                .frame(height: 30)
                .textFieldStyle(.plain)
                .padding([.leading, .trailing], 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.1)))
                .padding(.bottom, 10)
            HStack(spacing: 15) {
                Button {
                    model.sidebarModel.currentList = .Albums
                } label: {
                    Image(systemName: model.sidebarModel.currentList == .Albums ? "opticaldisc.fill" : "opticaldisc")
                }
                .help("Albums")
                .foregroundColor(model.sidebarModel.currentList == .Albums ? .accentColor : .secondary)
                .buttonStyle(.borderless)
                Button {
                    model.sidebarModel.currentList = .Playlists
                } label: {
                    Image(systemName: "music.note.list")
                }
                .help("Playlists")
                .foregroundColor(model.sidebarModel.currentList == .Playlists ? .accentColor : .secondary)
                .buttonStyle(.borderless)
            }
            .font(.title2)
            if model.sidebarModel.currentList == .Albums {
                ScrollView {
                    LazyVStack(spacing: -4) {
                        ForEach(model.musicLibrary.albums.filter { $0.title != nil }) {album in
                            let selected = model.sidebarModel.selected == album.id
                            Button {
                                model.sidebarModel.selected = album.id
                            } label: {
                                HStack {
                                    Text(album.title!)
                                        .foregroundColor(.primary)
                                        .scaledToFit()
                                    Spacer()
                                }
                            }
                            .buttonStyle(.borderless)
                            .padding(8)
                            .background(selected ? Color.primary.opacity(0.2) : .clear)
                            .cornerRadius(8)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            } else {
                Spacer()
            }
        }
        .scenePadding([.leading, .trailing])
        .padding([.top, .bottom], 30)
        .frame(width: 300)
        .background(SidebarMaterial())
    }
}
