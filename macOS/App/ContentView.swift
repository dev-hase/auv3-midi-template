//
//  ContentView.swift (macOS host app)
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
            Text("This app installs the **Arp** Audio Unit MIDI extension.\n\nValidate it with `auval -v aumi arp1 Hase`, then load it as a MIDI effect in Logic Pro, Live, or any AUv3 host.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
        }
        .padding(32)
        .frame(width: 480, height: 300)
    }
}

#Preview {
    ContentView()
}
