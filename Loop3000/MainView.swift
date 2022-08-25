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

fileprivate struct InnerMainView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var windowModel: WindowModel

    @State var window: NSWindow?

    var body: some View {
        if model.applicationIsHidden {
            Spacer()
        } else {
            ZStack {
                if window == nil {
                    WindowFinder(window: $window)
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
                            switch (windowModel.currentView) {
                            case .Discover:
                                DiscoverView()
                            case .Playlist:
                                let list = windowModel.selectedList.flatMap({ model.musicLibrary.getPlaylist(by: $0) })
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
            .navigationTitle(windowModel.selectedList.flatMap {
                model.musicLibrary.getPlaylist(by: $0)?.title
            } ?? "Loop3000")
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var windowModel: WindowModel?

    var body: some View {
        ZStack {
            if let windowModel {
                InnerMainView()
                    .environmentObject(windowModel)
            } else {
                Spacer()
            }
        }
        .onAppear {
            windowModel = WindowModel(appModel: model)
        }
    }
}
