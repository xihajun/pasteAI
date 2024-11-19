// AppDelegate.swift

import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow! // Keep a reference to the window

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Add this line
        UserDefaults.standard.set(false, forKey: "NSTextInputContextIdentifier")

        // Disable window tabbing (modified here)
        NSWindow.allowsAutomaticWindowTabbing = false

        // Configure the window here
        if let window = NSApplication.shared.windows.first {
            self.window = window
            configureWindow(window)
        }
    }

    private func configureWindow(_ window: NSWindow) {
        // Avoid removing the .titled style mask
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = NSColor.clear

        // Modified here: Use tabbingMode instead of allowsAutomaticWindowTabbing
        window.tabbingMode = .disallowed

        // Set the window level and make it key
        window.level = .normal
        window.makeKeyAndOrderFront(nil)
    }
}

class CustomWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }
}