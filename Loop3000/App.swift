import SwiftUI
import UniformTypeIdentifiers

@main
struct Loop3000App: App {
    @StateObject var model = ViewModel()
    var musicLibrary: ObservableMusicLibrary {
        model.musicLibrary
    }

    var body: some Scene {
        Window("Loop 3000", id: "main") {
            MainView()
            .environmentObject(model)
            .alert(model.alertModel.title, isPresented: $model.alertModel.isPresented) {
                Button("OK") {
                }
                .keyboardShortcut(.defaultAction)
            } message: {
                Text(model.alertModel.message)
            }
        }
        .commands {
            CommandMenu("Library") {
                Button("Add File…") {
                    model.libraryCommands.showFileAdder = true
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .fileImporter(
                    isPresented: $model.libraryCommands.showFileAdder,
                    allowedContentTypes: musicLibrary.canImportTypes
                ) { result in
                    guard let url = try? result.get() else { return }
                    let type = UTType(filenameExtension: url.pathExtension)!
                    if type.conforms(to: .audio) {
                        musicLibrary.performImportMedia(from: url)
                    } else {
                        model.alert(title: "Add File", message: "Please use “Add Folder” to add the whole album.")
                    }
                }
                Button("Add Folder…") {
                    model.libraryCommands.showFolderAdder = true
                }
                .fileImporter(
                    isPresented: $model.libraryCommands.showFolderAdder,
                    allowedContentTypes: [.folder]
                ) { result in
                    (try? result.get()).map { musicLibrary.performDiscover(at: $0, recursive: false) }
                }
                Button("Discover…") {
                    model.libraryCommands.showDiscoverer = true
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .fileImporter(
                    isPresented: $model.libraryCommands.showDiscoverer,
                    allowedContentTypes: [.folder]
                ) { result in
                    (try? result.get()).map { musicLibrary.performDiscover(at: $0, recursive: true) }
                }
            }
        }
    }
}
