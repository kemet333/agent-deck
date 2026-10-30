import AppKit
import SwiftUI

/// Panel flotante que no activa la app: el chat de IA sigue siendo la app activa, así que lo que el Desk
/// escribe le llega a él. Siempre encima, en todos los escritorios, se arrastra por cualquier punto.
final class FloatingPanel: NSPanel {
    init(store: DeskStore) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        let host = NSHostingView(rootView: DeskView(store: store))
        host.wantsLayer = true
        contentView = host
        setFrameAutosaveName("AgentDeskPanel")
        if !setFrameUsingName("AgentDeskPanel"), let screen = NSScreen.main {
            let v = screen.visibleFrame
            setFrameOrigin(NSPoint(x: v.maxX - 340, y: v.maxY - 400))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
