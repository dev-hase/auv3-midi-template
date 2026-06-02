//
//  ArpApp.swift (iOS host app)
//  A minimal container app. Its real job is to carry the AUv3 app extension so
//  the system registers the plugin; the UI just explains how to use it.
//

import SwiftUI

@main
struct ArpApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
