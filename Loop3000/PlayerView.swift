import SwiftUI

struct PlayerView: View {
    @State var sliderValue = 0.0

    var body: some View {
        HStack {
            Button {

            } label: {
                Image(systemName: "backward.fill")
            }
            .font(.title2)
            .buttonStyle(.borderless)
            Button {

            } label: {
                Image(systemName: "pause.fill")
            }
            .font(.largeTitle)
            .buttonStyle(.borderless)
            Button {

            } label: {
                Image(systemName: "forward.fill")
            }
            .font(.title2)
            .buttonStyle(.borderless)
            Spacer(minLength: 15)
            Slider(value: $sliderValue, in: 0 ... 1)
        }
        .scenePadding([.leading, .trailing])
        .padding(.top, 32)
        .padding(.bottom, 28)
    }
}
