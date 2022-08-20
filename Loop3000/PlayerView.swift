import SwiftUI
import Combine

struct PlayerView: View {
    @EnvironmentObject private var model: ViewModel

    private var ac: [any Cancellable] = []

    private var currentTimestampString: String {
        let description = model.currentTimestamp.description
        return String(description[..<description.index(description.startIndex, offsetBy: 5)])
    }

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
                (model.playing && !model.paused ? Label("Pause", systemImage: "pause.fill") : Label("Play", systemImage: "play.fill"))
                    .labelStyle(.iconOnly)
            }
            .font(.largeTitle)
            .buttonStyle(.borderless)
            .frame(width: 25)
            Button {
                model.playNext()
            } label: {
                Label("Play next track", systemImage: "forward.fill")
                    .labelStyle(.iconOnly)
            }
            .font(.title2)
            .buttonStyle(.borderless)
            Text(currentTimestampString)
                .padding([.leading, .trailing], 5)
                .font(.body.monospacedDigit())
            Slider(value: $model.playerSliderValue, in: 0 ... 1)
                .disabled(!model.playing && !model.paused)
        }
        .frame(height: 27)
        .scenePadding([.leading, .trailing])
        .padding(.top, 32)
        .padding(.bottom, 28)
    }
}
