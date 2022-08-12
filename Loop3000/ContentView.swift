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
    @State var musicLibrary = MusicLibrary()
    @State var libraryJSON: JSONDocument?
    @State var discovering = false

    var body: some View {
        VStack {
            if discovering {
                ProgressView()
            } else {
                Button("Discover Media") {
                    showMediaImporter = true
                }
                .fileImporter(isPresented: $showMediaImporter, allowedContentTypes: [.folder]) { result in
                    let url = try! result.get()
                    Task {
                        discovering = true
                        defer { discovering = false }
                        print(try! await musicLibrary.discover(at: url, recursive: true))
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
