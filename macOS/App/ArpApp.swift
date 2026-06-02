//
//  ArpApp.swift (macOS host app)
//  Minimal container app that carries the AUv3 app extension so the system
//  registers the plugin (validate with `auval -v aumi arp1 Hase`).
//

import SwiftUI

@main
struct ArpApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
