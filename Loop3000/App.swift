import SwiftUI
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
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
struct Loop3000App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var model = AppModel()

    @State private var showDiscoverer = false

    var body: some Scene {
        WindowGroup {
            MainView()
            .environmentObject(model)
            .alert(model.alertModel.title, isPresented: $model.alertModel.isPresented) {
                Button("OK") {}
                .keyboardShortcut(.defaultAction)
            } message: {
                Text(model.alertModel.message)
            }
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                model.musicLibrary.syncWithStorage()
                appDelegate.model = model
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Discover Music") {
                    showDiscoverer = true
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .fileImporter(
                    isPresented: $showDiscoverer,
                    allowedContentTypes: model.musicLibrary.canImportTypes + [.folder]
                ) { result in
                    (try? result.get()).map { model.musicLibrary.performDiscover(at: $0) }
                }
            }
        }
    }
}
