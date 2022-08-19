import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: ViewModel

    var body: some View {
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
                        PlaylistView(model.selectedList!)
                    case .Stub:
                        Spacer()
                        Text("Enjoy your music")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}
