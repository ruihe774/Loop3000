import SwiftUI
import Combine

struct PlayerView: View {
    @EnvironmentObject private var model: AppModel

    @State private var sliderValue = 0.0
    @State private var duration = Int.max
    @State private var editing = false
    private var targetTimestamp: CueTime {
        CueTime(value: Int(Double(duration) * sliderValue))
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
            Text(editing ? targetTimestamp.shortDescription : model.currentTimestamp.shortDescription)
                .padding([.leading, .trailing], 5)
                .font(.body.monospacedDigit())
            Slider(value: $sliderValue, in: 0 ... 1, onEditingChanged: { editing = $0 })
                .onAppear {
                    updateDuration(model.playingItem)
                    updateTimestamp(model.currentTimestamp)
                }
                .onChange(of: model.playingItem) { playingItem in
                    updateDuration(playingItem)
                    updateTimestamp(model.currentTimestamp)
                }
                .onReceive(model.refreshTimer) { _ in
                    updateTimestamp(model.currentTimestamp)
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

    private func updateDuration(_ itemId: UUID?) {
        if let track = itemId
            .flatMap({ model.musicLibrary.locatePlaylistItem(by: $0)?.1 })
            .flatMap({ model.musicLibrary.getTrack(by: $0.trackId) }) {
            duration = track.end.value - track.start.value
        }
    }

    private func updateTimestamp(_ timestamp: CueTime) {
        guard !editing else { return }
        sliderValue = Double(timestamp.value) / Double(duration)
    }
}
