import SwiftUI

struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context _: Self.Context) -> NSView {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .sidebar
        return visualEffect
    }
    func updateNSView(_: NSView, context _: Context) {}
}

struct Sidebar: View {
    var body: some View {
        VStack {
            Spacer()
        }
        .scenePadding()
        .frame(width: 200)
        .background(SidebarMaterial())
    }
}
