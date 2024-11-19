// PasteApp.swift

import SwiftUI

@main
struct PasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate // Integrate AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}