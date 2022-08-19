import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var model: ViewModel

    @State private var sliderValue = 0.0

    var body: some View {
        HStack {
            Button {
                model.playPrevious()
            } label: {
                Label("Play previous track", systemImage: "backward.fill")
                    .labelStyle(.iconOnly)
            }
            .font(.title2)
            .buttonStyle(.borderless)
            Button {
                if model.playing {
                    model.pause()
                } else {
                    model.resume()
                }
            } label: {
                (model.playing ? Label("Pause", systemImage: "pause.fill") : Label("Play", systemImage: "play.fill"))
                    .labelStyle(.iconOnly)
            }
            .font(.largeTitle)
            .buttonStyle(.borderless)
            Button {
                model.playNext()
            } label: {
                Label("Play next track", systemImage: "forward.fill")
                    .labelStyle(.iconOnly)
            }
            .font(.title2)
            .buttonStyle(.borderless)
            Spacer(minLength: 15)
            Slider(value: $sliderValue, in: 0 ... 1)
        }
        .frame(height: 27)
        .scenePadding([.leading, .trailing])
        .padding(.top, 32)
        .padding(.bottom, 28)
    }
}
