import SwiftUI
import UniformTypeIdentifiers

fileprivate class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate var model: AppModel?

    func applicationDidHide(_ notification: Notification) {
        model.map { model in
            DispatchQueue.main.async {
                model.applicationIsHidden = true
            }
        }
    }

    func applicationWillUnhide(_ notification: Notification) {
        model.map { model in
            DispatchQueue.main.async {
                model.applicationIsHidden = false
            }
        }
    }
}

@main
fileprivate struct Loop3000App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    @StateObject private var model = AppModel()

    @State private var showDiscoverer = false

    var body: some Scene {
        WindowGroup {
            MainView()
            .environmentObject(model)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                model.musicLibrary.syncWithStorage()
                appDelegate.model = model
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button("Discover Music") {
                    showDiscoverer = true
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .fileImporter(
                    isPresented: $showDiscoverer,
                    allowedContentTypes: [.folder]
                ) { result in
                    (try? result.get()).map { model.musicLibrary.performDiscover(at: $0) }
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Acknowledgments") {
                    let fileManager = FileManager.default
                    let workspace = NSWorkspace.shared
                    let ackPath = Bundle.main.url(forResource: "Acknowledgments", withExtension: "rtf")!
                    let roPath = URL.temporaryDirectory.appending(component: "Loop3000 Acknowledgments.rtf")
                    try? fileManager.setAttributes([.immutable: false], ofItemAtPath: roPath.path)
                    try? fileManager.removeItem(at: roPath)
                    try! fileManager.copyItem(at: ackPath, to: roPath)
                    try! fileManager.setAttributes([.immutable: true], ofItemAtPath: roPath.path)
                    let config = NSWorkspace.OpenConfiguration()
                    config.addsToRecentItems = false
                    workspace.open(
                        [roPath],
                        withApplicationAt: workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")!,
                        configuration: config
                    )
                }
            }
        }
        Window("Alert", id: "alert") {
            AlertView($model.alertModel.isPresented, title: model.alertModel.title, message: model.alertModel.message)
        }
        .onChange(of: model.alertModel.isPresented) { isPresent in
            if isPresent {
                openWindow(id: "alert")
            }
        }
        .onChange(of: showDiscoverer) { showDiscoverer in
            model.musicLibrary.prepareDiscover()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}

fileprivate class AlertWindowDelegate: NSObject, NSWindowDelegate {
    @Binding private var isPresent: Bool

    func windowWillClose(_ notification: Notification) {
        isPresent = false
        NSApp!.stopModal()
    }

    init(_ isPresent: Binding<Bool>) {
        _isPresent = isPresent
    }
}

fileprivate struct AlertView: View {
    private let message: String
    private let title: String
    private let delegate: AlertWindowDelegate
    @Binding private var isPresent: Bool
    @State private var window: NSWindow?

    init(_ isPresent: Binding<Bool>, title: String, message: String) {
        self._isPresent = isPresent
        self.message = message
        self.title = title
        self.delegate = AlertWindowDelegate(isPresent)
    }

    var body: some View {
        ZStack {
            if window == nil {
                WindowFinder(window: $window)
            }
            VStack(alignment: .trailing) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.custom("SF Pro", size: 50))
                    VStack(alignment: .leading) {
                        Spacer()
                        Text(title)
                            .textSelection(.enabled)
                            .font(.headline)
                        Text(message)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    Spacer()
                }
                Button {
                    window!.close()
                } label: {
                    Text("Close")
                        .frame(width: 50)
                }
                .keyboardShortcut(.defaultAction)
            }
            .scenePadding()
            .frame(width: 400)
            .frame(maxHeight: 200)
            .onChange(of: window == nil) { _ in
                guard let window else { return }
                window.delegate = delegate
                if isPresent {
                    NSApp!.runModal(for: window)
                } else {
                    window.close()
                }
            }
            .onChange(of: isPresent) { isPresent in
                guard let window else { return }
                if isPresent {
                    NSApp!.runModal(for: window)
                } else {
                    window.close()
                }
            }
        }
    }
}
