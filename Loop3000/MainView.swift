import SwiftUI

struct WindowBackgrounMaterial: NSViewRepresentable {
    func makeNSView(context _: Self.Context) -> NSView {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .windowBackground
        return visualEffect
    }
    func updateNSView(_: NSView, context _: Context) {}
}

struct MainView: View {
    @EnvironmentObject var model: ViewModel

    
    
    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ZStack {
                Rectangle()
                    .background(WindowBackgrounMaterial())
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
