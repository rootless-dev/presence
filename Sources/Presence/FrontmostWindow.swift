import AppKit
import SwiftUI

/// Brings the window hosting this view to the front, activating the app.
///
/// Clicking a menu bar item doesn't activate an `LSUIElement` app, so a
/// window opened from the menu can appear behind whatever had focus — with
/// nothing in the Dock to click, it's easy to miss entirely.
struct FrontmostWindow: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view has no window until it's in the hierarchy; asking on the
        // next runloop pass is what makes `view.window` available.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.collectionBehavior.insert(.moveToActiveSpace)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
