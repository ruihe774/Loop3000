import SwiftUI

struct Stub: View {
    var body: some View {
        Spacer()
        Text("Enjoy your music")
            .foregroundColor(.secondary)
        Spacer()
    }
}

struct MainView: View {
    @EnvironmentObject private var model: ViewModel

    var body: some View {
        if model.windowIsHidden {
            Spacer()
        } else {
            HStack(spacing: 0) {
                Sidebar()
                ZStack {
                    Rectangle()
                        .background(Color(nsColor: .windowBackgroundColor))
                        .foregroundColor(.clear)
                        .shadow(radius: 1)
                    VStack(spacing: 0) {
                        PlayerView()
                        Divider()
                        switch (model.currentView) {
                        case .Discover:
                            DiscoverView()
                        case .Playlist:
                            let list = model.selectedList.flatMap({ model.musicLibrary.getPlaylist(by: $0) })
                            if list != nil {
                                PlaylistView(list!)
                            } else {
                                Stub()
                            }
                        default:
                            Stub()
                        }
                    }
                }
            }
        }
    }
}
