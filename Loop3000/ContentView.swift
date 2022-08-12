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
    @State var showLibraryImporter = false
    @State var showJSONExporter = false
    @State var musicLibrary = MusicLibrary()
    @State var libraryJSON: JSONDocument?
    @State var discovering = false
    @State var errMsg: String?

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
                        let errors = try! await musicLibrary.discover(at: url, recursive: true).errors
                        DispatchQueue.main.async {
                            errMsg = "\(errors)"
                        }
                    }
                }
                Button("Import Library") {
                    showLibraryImporter = true
                }
                .fileImporter(isPresented: $showLibraryImporter, allowedContentTypes: [.json]) { result in
                    let url = try! result.get()
                    let json = JSONDecoder()
                    musicLibrary = try! json.decode(MusicLibrary.self, from: try! Data(contentsOf: url))
                }
                Button("Consolidate") {
                    musicLibrary.consolidate()
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
            if let errMsg = errMsg {
                Text(verbatim: errMsg)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
