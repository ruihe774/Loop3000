import SwiftUI
import Combine

struct PlayerView: View {
    @EnvironmentObject private var model: ViewModel

    @State private var sliderValue = 0.0
    @State private var duration = Int.max
    @State private var editing = false
    private var targetTimestamp: Timestamp {
        Timestamp(value: Int(Double(duration) * sliderValue))
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
            Text(editing ? targetTimestamp.briefDescription : model.currentTimestamp.briefDescription)
                .padding([.leading, .trailing], 5)
                .font(.body.monospacedDigit())
            Slider(value: $sliderValue, in: 0 ... 1, onEditingChanged: { editing = $0 })
                .onChange(of: model.playingItem) { playingItem in
                    if let track = playingItem.map({ model.musicLibrary.getTrack(by: $0.trackId) }) {
                        duration = track.end.value - track.start.value
                    }
                }
                .onChange(of: model.currentTimestamp) { timestamp in
                    guard !editing else { return }
                    sliderValue = Double(timestamp.value) / Double(duration)
                }
                .onChange(of: editing) { editing in
                    if !editing {
                        model.seek(to: targetTimestamp)
                    }
                }
                .disabled(!model.playing && !model.paused)
        }
        .frame(height: 27)
        .scenePadding([.leading, .trailing])
        .padding(.top, 32)
        .padding(.bottom, 28)
    }
}
