import AppKit
import Combine
import SwiftUI

/// Panel que no activa la app: el chat de IA sigue siendo la app activa, así que lo que el Desk escribe
/// le llega a él. Siempre encima y en todos los escritorios. Se arrastra por cualquier punto; al cambiar
/// de tamaño (teclas, plegado) conserva su centro inferior, con una animación corta, y no se sale de
/// la pantalla. La primera vez se coloca centrada abajo en la pantalla donde está el ratón.
final class FloatingPanel: NSPanel {
    private let store: DeskStore
    private let host: NSHostingView<DeskRoot>
    private var bag = Set<AnyCancellable>()
    private let anchorKey = "AgentDeskAnchor" // "x y" del centro inferior, en coordenadas de pantalla

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
        hasShadow = false // la sombra la dibuja la vista, para que acompañe al plegado
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        becomesKeyOnlyIfNeeded = true
        host.wantsLayer = true
        contentView = host
        relayout(animated: false, recenter: UserDefaults.standard.string(forKey: anchorKey) == nil)
        store.$keys.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(animated: true, recenter: false) }.store(in: &bag)
        store.$editing.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(animated: true, recenter: false) }.store(in: &bag)
        store.$collapsed.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            // durante la transición conviven las dos vistas y el tamaño medido es el grande: se recoloca al terminar
            self?.relayout(animated: true, recenter: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.relayout(animated: true, recenter: false) }
        }.store(in: &bag)
        store.$listening.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(animated: true, recenter: false) }.store(in: &bag)
        store.$partial.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(animated: false, recenter: false) }.store(in: &bag)
        store.$mode.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(animated: true, recenter: true) }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.relayout(animated: false, recenter: false)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            self?.rememberAnchor()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var screenUnderMouse: NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func rememberAnchor() {
        let a = NSPoint(x: frame.midX, y: frame.minY)
        UserDefaults.standard.set("\(a.x) \(a.y)", forKey: anchorKey)
    }

    private var savedAnchor: NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: anchorKey) else { return nil }
        let parts = s.split(separator: " ").compactMap { Double($0) }
        return parts.count == 2 ? NSPoint(x: parts[0], y: parts[1]) : nil
    }

    func relayout(animated: Bool, recenter: Bool) {
        host.rootView = DeskRoot(store: store)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        var anchor: NSPoint
        if recenter || savedAnchor == nil {
            let v = screenUnderMouse.visibleFrame
            anchor = NSPoint(x: v.midX, y: v.minY + 2)
        } else if isVisible, let saved = savedAnchor {
            anchor = saved // el centro inferior recordado: estable aunque una animación esté a medias
        } else {
            anchor = savedAnchor!
        }
        var target = NSRect(x: anchor.x - size.width / 2, y: anchor.y, width: size.width, height: size.height)
        // que no se salga de la pantalla donde está
        let screen = NSScreen.screens.first { $0.frame.intersects(target) } ?? screenUnderMouse
        let v = screen.visibleFrame
        target.origin.x = min(max(target.origin.x, v.minX - 20), v.maxX - target.width + 20)
        target.origin.y = min(max(target.origin.y, v.minY - 10), v.maxY - target.height + 30)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                self.animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true)
        }
        UserDefaults.standard.set("\(target.midX) \(target.minY)", forKey: anchorKey)
    }
}
