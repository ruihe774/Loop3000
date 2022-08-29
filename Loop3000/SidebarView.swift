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

    private enum ListType {
        case albums
        case playlists
    }
    @State private var listType = ListType.albums

    var body: some View {
        VStack(alignment: .center) {
            Text("Loop3000")
                .font(.headline)
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
            .scrollContentBackground(.hidden)
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
