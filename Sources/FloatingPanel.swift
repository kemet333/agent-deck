import AppKit
import Combine
import SwiftUI

/// Panel que no activa la app: el chat de IA sigue siendo la app activa, así que lo que el Desk escribe
/// le llega a él. Siempre encima y en todos los escritorios. En modo dock se pega al borde inferior de
/// la pantalla donde está el ratón, centrado; en modo tarjeta flota y se arrastra por cualquier punto.
final class FloatingPanel: NSPanel {
    private let store: DeskStore
    private let host: NSHostingView<DeskRoot>
    private var bag = Set<AnyCancellable>()

    init(store: DeskStore) {
        self.store = store
        host = NSHostingView(rootView: DeskRoot(store: store))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        host.wantsLayer = true
        contentView = host
        relayout(toScreenUnderMouse: true)
        // Cambios de teclas o de modo cambian el tamaño: se vuelve a colocar.
        store.$keys.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(toScreenUnderMouse: false) }.store(in: &bag)
        store.$editing.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(toScreenUnderMouse: false) }.store(in: &bag)
        store.$mode.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(toScreenUnderMouse: true) }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.relayout(toScreenUnderMouse: false)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var screenForDock: NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func relayout(toScreenUnderMouse: Bool) {
        host.rootView = DeskRoot(store: store)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        switch store.mode {
        case .dock:
            isMovableByWindowBackground = false
            let screen = toScreenUnderMouse ? screenForDock : (self.screen ?? screenForDock)
            let v = screen.visibleFrame
            let origin = NSPoint(x: v.midX - size.width / 2, y: v.minY + 6)
            setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        case .card:
            isMovableByWindowBackground = true
            var origin = frame.origin
            if toScreenUnderMouse {
                let v = screenForDock.visibleFrame
                origin = NSPoint(x: v.maxX - size.width - 20, y: v.maxY - size.height - 20)
            }
            setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        }
    }
}
