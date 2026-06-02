//
//  ContentView.swift (iOS host app)
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pianokeys")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Arp AUv3 MIDI")
                .font(.largeTitle).bold()
            Text("This app installs the **Arp** Audio Unit MIDI extension.\n\nOpen an AUv3 host (AUM, Cubasis, GarageBand…), add **Arp** as a MIDI effect, route a keyboard into it and its output into an instrument.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
