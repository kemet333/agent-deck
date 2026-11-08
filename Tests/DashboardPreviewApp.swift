import AppKit
import SwiftUI

// Visual-only harness for the settings dashboard. Own bundle id and a temporary AGENT_DECK_FOLDER (set by the
// build script's caller): no AppDelegate, hotkeys, status item, microphone, API calls or the installed app's keys.
// Usage: DashboardPreview <pane> <light|dark>   → prints WINDOW <number> once the window is on screen.
@main
@MainActor
final class DashboardPreviewApp: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    static func main() { let app = NSApplication.shared; let d = DashboardPreviewApp(); app.delegate = d; app.setActivationPolicy(.regular); app.run() }
    func applicationDidFinishLaunching(_ n: Notification) {
        let args = CommandLine.arguments
        let pane = DashPane(rawValue: args.count > 1 ? args[1] : "general") ?? .general
        NSApp.appearance = NSAppearance(named: (args.count > 2 && args[2] == "dark") ? .darkAqua : .aqua)
        let store = DeskStore()
        let voice = VoiceController(storage: VoiceStorage(folder: DeskStore.folder), keyProvider: { "" }, microphonePermission: { false }, frontApp: { ("Preview", "test.synthetic") })
        voice.shortcutStatus = "Fn ready"
        window = makeDashboardWindow(root: DashboardView(store: store, voice: voice, pane: pane))
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { print("WINDOW \(self.window?.windowNumber ?? 0)"); fflush(stdout) }
    }
}
