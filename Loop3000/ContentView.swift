//
//  ContentView.swift
//  Loop3000
//
//  Created by 見崎かすみ on 2022/8/10.
//
//

import SwiftUI

struct ContentView: View {
    @State var testingCueSheetParser = false

    var body: some View {
        VStack {
            Button("Test CueSheetParser") {
                testingCueSheetParser = true
            }
                    .fileImporter(isPresented: $testingCueSheetParser, allowedContentTypes: [.data]) { result in
                        let url = try! result.get()
                        print(url)
                        let parser = CueSheetParser()
                        let grabber = FLACGrabber()
                        Task {
                            let v = try! await parser.parse(url: url)
                            try! await grabber.grab(tracks: v.tracks)
//                            let json = JSONEncoder()
//                            json.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
//                            let s = String(data: try! json.encode(v.tracks), encoding: .utf8)!
//                            print(s)
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
