import SwiftUI

fileprivate struct ClickableModifier: ViewModifier {
    @State private var hovering = false
    private let enabled: Bool

    func body(content: Content) -> some View {
        content
            .onHover { hover in withAnimation { hovering = hover } }
            .background(RoundedRectangle(cornerRadius: 3).fill(
                hovering && enabled ? Color.interactiveBackgroundColor : .clear
            ))
    }

    init(enabled: Bool = true) {
        self.enabled = enabled
    }
}

extension View {
    func clickable(enabled: Bool = true) -> some View {
        modifier(ClickableModifier(enabled: enabled))
    }
}

struct PlayerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var windowModel: WindowModel

    @State private var sliderValue = 0.0
    @State private var duration = Int.max
    @State private var editing = false
    private var targetTimestamp: CueTime {
        CueTime(value: Int(Double(duration) * sliderValue))
    }
	
	@State var userVolume:Float = 1.0
	@State var volumeEditing = false

    var body: some View {
        HStack {
            Button {
                model.playPrevious()
            } label: {
                Label("Play previous track", systemImage: "backward.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 25, height: 25)
            }
            .font(.title2)
            .buttonStyle(.borderless)
            Button {
                if model.playbackState == .playing {
                    model.pause()
                } else {
                    windowModel.resume()
                }
            } label: {
                (model.playbackState == .playing ? Label("Pause", systemImage: "pause.fill") : Label("Play", systemImage: "play.fill"))
                    .labelStyle(.iconOnly)
                    .frame(width: 25, height: 25)
            }
            .font(.largeTitle)
            .buttonStyle(.borderless)
            Button {
                model.playNext()
            } label: {
                Label("Play next track", systemImage: "forward.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 25, height: 25)
            }
            .font(.title2)
            .buttonStyle(.borderless)
            Text(editing ? targetTimestamp.shortDescription : model.currentTimestamp.shortDescription)
                .padding([.leading, .trailing], 5)
                .font(.body.monospacedDigit())
            Slider(value: $sliderValue, in: 0 ... 1, onEditingChanged: { editing = $0 })
                .onAppear {
                    updateDuration(model.playingPiece)
                    updateTimestamp(model.currentTimestamp)
                }
                .onChange(of: model.playingPiece) { playingPiece in
                    updateDuration(playingPiece)
                    updateTimestamp(model.currentTimestamp)
                }
                .onReceive(model.guiRefreshTimer) { _ in
                    updateTimestamp(model.currentTimestamp)
                }
                .onChange(of: editing) { editing in
                    if !editing {
                        model.seek(to: targetTimestamp)
                    }
                }
                .disabled(model.playbackState == .stopped)
			Divider()
			Slider(value: $userVolume, in: 0.0...1.0, onEditingChanged: { volumeEditing = $0 })
				.frame(maxWidth: 100)
				.onChange(of: volumeEditing, perform: { volumeEditing in
					if !volumeEditing {
						model.setVol(to: userVolume)
					}
				})
				
        }
        .frame(height: 25)
        .scenePadding([.leading, .trailing])
        .padding(.top, 32)
        .padding(.bottom, 30)
        .overlay {
            if let piece = model.playingPiece, let title = piece.uiTitle {
                HStack {
                    Spacer()
                    Button {
                        windowModel.selectedList = piece.playlistId
                        windowModel.selectedPiece = piece
                    } label: {
                        Label(title, systemImage: "waveform")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .padding(3)
                            .clickable(enabled: windowModel.selectedList != piece.playlistId || windowModel.selectedPiece != piece)
                    }
                    .buttonStyle(.borderless)
                }
                .offset(CGSize(width: -20, height: 20))
            } else {
                Spacer()
            }
        }
    }

    private func updateDuration(_ piece: MusicPiece?) {
        (piece?.duration?.value).map { duration = $0 }
    }

    private func updateTimestamp(_ timestamp: CueTime) {
        guard !editing else { return }
        sliderValue = Double(timestamp.value) / Double(duration)
    }
}
