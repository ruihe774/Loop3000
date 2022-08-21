import SwiftUI
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate var model: ViewModel?

    func applicationDidHide(_ notification: Notification) {
        model?.windowIsHidden = true
    }

    func applicationWillUnhide(_ notification: Notification) {
        model?.windowIsHidden = false
    }
}

@main
struct Loop3000App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var model = ViewModel()

    var body: some Scene {
        Window("Loop 3000", id: "main") {
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
                Button("Add File") {
                    model.libraryCommands.showFileAdder = true
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .fileImporter(
                    isPresented: $model.libraryCommands.showFileAdder,
                    allowedContentTypes: model.musicLibrary.canImportTypes
                ) { result in
                    (try? result.get()).map { model.musicLibrary.performScanMedia(at: $0) }
                }
                Button("Add Folder") {
                    model.libraryCommands.showFolderAdder = true
                }
                .fileImporter(
                    isPresented: $model.libraryCommands.showFolderAdder,
                    allowedContentTypes: [.folder]
                ) { result in
                    (try? result.get()).map { model.musicLibrary.performDiscoverMedia(at: $0, recursive: false) }
                }
                Button("Scan Recursively") {
                    model.libraryCommands.showDiscoverer = true
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .fileImporter(
                    isPresented: $model.libraryCommands.showDiscoverer,
                    allowedContentTypes: [.folder]
                ) { result in
                    (try? result.get()).map { model.musicLibrary.performDiscoverMedia(at: $0, recursive: true) }
                }
            }
        }
    }
}
