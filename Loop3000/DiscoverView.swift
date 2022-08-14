import SwiftUI
import Combine

extension URL: Identifiable {
    public var id: String {
        absoluteString
    }
}

struct DiscoverView: View {
    @EnvironmentObject var model: ViewModel
    @State private var dotCount = 0
    private var dotTimer = Timer.publish(every: 0.5, on: .main, in: .default)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Discovering your music" + String(repeating: ".", count: dotCount))
                .font(.headline)
                .padding()
            Divider()
            List(dedup(model.musicLibrary.requesting)) { url in
                let text = url.isFileURL ? url.path : url.absoluteString
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.5)
                    Text(text)
                        .help(text)
                        .scaledToFit()
                }
                .frame(height: 16)
            }
            .listStyle(.plain)
        }
        .onReceive(dotTimer, perform: { _ in
            self.dotCount = (self.dotCount + 1) % 4
        })
    }

    private func dedup(_ urls: [URL]) -> [URL] {
        var uniques: [URL] = []
        var met: Set<URL> = []
        for url in urls {
            if !met.contains(url) {
                uniques.append(url)
                met.insert(url)
            }
        }
        return uniques
    }

    private var ac: [any Cancellable] = []

    init() {
        ac.append(dotTimer.connect())
    }
}
