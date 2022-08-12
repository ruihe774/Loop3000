//
//  ContentView.swift
//  Loop3000
//
//  Created by 見崎かすみ on 2022/8/10.
//
//

import SwiftUI
import UniformTypeIdentifiers

struct JSONDocument: FileDocument {
    static let readableContentTypes = [UTType.json]

    var content: Data

    init(_ content: Data) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = data
        } else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: content)
    }
}

struct ContentView: View {
    @State var showMediaImporter = false
    @State var showJSONExporter = false
    var musicLibrary = MusicLibrary()
    @State var libraryJSON: JSONDocument?

    var body: some View {
        VStack {
            Button("Import Media") {
                showMediaImporter = true
            }
            .fileImporter(isPresented: $showMediaImporter, allowedContentTypes: musicLibrary.canImportTypes) { result in
                let url = try! result.get()
                Task {
                    try! await musicLibrary.importMedia(from: url)
                }
            }
            Button("Export Library") {
                let json = JSONEncoder()
                json.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                libraryJSON = JSONDocument(try! json.encode(musicLibrary))
                showJSONExporter = true
            }
            .fileExporter(isPresented: $showJSONExporter, document: libraryJSON, contentType: .json) { result in
                let _ = try! result.get()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
