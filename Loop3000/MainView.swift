import SwiftUI

fileprivate struct Stub: View {
    var body: some View {
        Spacer()
        Text("Enjoy your music")
            .foregroundColor(.secondary)
        Spacer()
    }
}

struct WindowFinder: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context _: Self.Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }
    func updateNSView(_: NSView, context _: Context) {}
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel

    @State var window: NSWindow?

    var body: some View {
        if model.applicationIsHidden {
            Spacer()
        } else {
            ZStack {
                if window == nil {
                    Spacer()
                        .background(WindowFinder(window: $window))
                }
                HStack(spacing: 0) {
                    Sidebar()
                    ZStack {
                        Rectangle()
                            .fill(Color(nsColor: .windowBackgroundColor))
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
            .onChange(of: window == nil) { _ in
                window?.tabbingMode = .disallowed
            }
        }
    }
}
