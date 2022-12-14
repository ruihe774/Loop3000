import SwiftUI

fileprivate struct Stub: View {
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        Spacer()
        ZStack {
            if colorScheme == .light {
                Image(decorative: "IconFlat")
                    .blendMode(.plusDarker)
                    .opacity(0.1)
            } else {
                Image(decorative: "IconFlat")
                    .colorInvert()
                    .blendMode(.plusLighter)
                    .opacity(0.1)
            }
        }
        .offset(CGSize(width: 0, height: -30))
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

    @State private var currentView = ShowView.stub

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ZStack {
                Rectangle()
                    .fill(Color.windowBackgroundColor)
                    .shadow(radius: 1)
                VStack(spacing: 0) {
                    PlayerView()
                    Divider()
                    switch (currentView) {
                    case .discover:
                        DiscoverView()
                    case .playlist where windowModel.selectedList.flatMap({ model.musicLibrary.playlists[$0] }) != nil:
                        PlaylistView(windowModel.selectedList!)
                    default:
                        Stub()
                    }
                }
            }
        }
        .navigationTitle(windowModel.selectedList.flatMap {
            model.musicLibrary.playlists[$0]?.title
        } ?? "Loop3000")
        .onAnimatedValue(of: windowModel.currentView) {
            currentView = $0
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @State private var windowModel: WindowModel?

    @State private var window: NSWindow?

    var body: some View {
        ZStack {
            if window == nil {
                WindowFinder(window: $window)
            }
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
        .onChange(of: window == nil) { _ in
            window?.tabbingMode = .disallowed
        }
    }
}
