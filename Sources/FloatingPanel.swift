import AppKit
import Combine
import SwiftUI

/// Panel que no activa la app: el chat de IA sigue siendo la app activa, así que lo que el Desk escribe
/// le llega a él. Siempre encima y en todos los escritorios. Se arrastra por cualquier punto; al cambiar
/// de tamaño (teclas, plegado) conserva su centro inferior, con una animación corta, y no se sale de
/// la pantalla. La primera vez se coloca centrada abajo en la pantalla donde está el ratón.
@MainActor
final class FloatingPanel: NSPanel {
    private let store: DeskStore
    private let host: NSHostingView<DeskRoot>
    private var bag = Set<AnyCancellable>()
    private let anchorKey = "AgentDeskAnchor" // "x y" del centro inferior, en coordenadas de pantalla
    private let edgeKey = "AgentDeskEdge"     // "left" o "right": el orbe escondido en ese lateral
    /// Arrastre del orbe a mano: el orbe es un botón y se quedaría el clic, así que el panel lo mueve él.
    private var dragFrom: NSPoint?
    private var frameFrom: NSRect = .zero
    private var dragging = false
    private var samples: [(t: TimeInterval, p: NSPoint)] = []
    /// Lo que asoma del orbe escondido en un lateral.
    private let peek: CGFloat = 14

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
        store.$voiceWorking.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(animated: true, recenter: false) }.store(in: &bag)
        store.$voiceNeedsAttention.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(animated: true, recenter: false) }.store(in: &bag)
        store.$partial.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(animated: false, recenter: false) }.store(in: &bag)
        store.$mode.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.relayout(animated: true, recenter: true) }.store(in: &bag)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout(animated: false, recenter: false) }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rememberAnchor() }
        }
    }

    private var orbMode: Bool { store.mode == .dock && store.collapsed }

    private var edge: String? {
        get { UserDefaults.standard.string(forKey: edgeKey) }
        set { UserDefaults.standard.set(newValue, forKey: edgeKey) }
    }

    /// Con la barra plegada: arrastrar mueve el orbe a cualquier sitio; lanzarlo hacia un lado (o soltarlo
    /// pegado al borde) lo esconde en ese lateral, asomando un poco. Un clic sin arrastrar lo despliega, como siempre.
    override func sendEvent(_ e: NSEvent) {
        guard orbMode else { super.sendEvent(e); return }
        switch e.type {
        case .leftMouseDown:
            dragFrom = NSEvent.mouseLocation; frameFrom = frame; dragging = false; samples = []
            super.sendEvent(e)
        case .leftMouseDragged:
            guard let from = dragFrom else { super.sendEvent(e); return }
            let p = NSEvent.mouseLocation
            if !dragging, hypot(p.x - from.x, p.y - from.y) > 4 {
                dragging = true
                // el botón del orbe suelta el clic fuera de sí mismo: no se despliega al acabar el arrastre
                if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000), modifierFlags: [],
                                               timestamp: e.timestamp, windowNumber: windowNumber, context: nil,
                                               eventNumber: e.eventNumber, clickCount: 1, pressure: 0) { super.sendEvent(up) }
            }
            guard dragging else { super.sendEvent(e); return }
            setFrameOrigin(NSPoint(x: frameFrom.minX + p.x - from.x, y: frameFrom.minY + p.y - from.y))
            samples.append((e.timestamp, p)); if samples.count > 6 { samples.removeFirst() }
        case .leftMouseUp:
            dragFrom = nil
            guard dragging else { super.sendEvent(e); return }
            dragging = false
            fling()
        default:
            super.sendEvent(e)
        }
    }

    /// Al soltar: velocidad horizontal de los últimos movimientos y adónde llegaría el orbe con ella.
    private func fling() {
        var vx: CGFloat = 0
        if let a = samples.first, let b = samples.last, b.t > a.t { vx = (b.p.x - a.p.x) / CGFloat(b.t - a.t) }
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) } ?? screenUnderMouse
        let v = screen.visibleFrame
        let landing = frame.midX + vx * 0.2
        if vx < -900 || landing < v.minX + 30 { edge = "left" }
        else if vx > 900 || landing > v.maxX - 30 { edge = "right" }
        else { edge = nil }
        relayout(animated: true, recenter: false, anchor: NSPoint(x: frame.midX, y: frame.minY))
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

    func relayout(animated: Bool, recenter: Bool, anchor dropped: NSPoint? = nil) {
        host.rootView = DeskRoot(store: store)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        var anchor: NSPoint
        // al tocar el orbe escondido en un lateral, la barra vuelve a su sitio de siempre (centrada abajo);
        // luego se puede volver a arrastrar donde se quiera
        var recenter = recenter
        if !orbMode, edge != nil { edge = nil; recenter = true }
        if let dropped = dropped {
            anchor = dropped
        } else if recenter || savedAnchor == nil {
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
        if orbMode, !store.listening, let side = edge { // dictando, la cápsula sale entera para leer lo que oye
            // el orbe mide su anchura menos el margen de la sombra (30 a cada lado, DockView)
            let orb = max(size.width - 60, 30)
            let mid = side == "left" ? v.minX - orb / 2 + peek : v.maxX + orb / 2 - peek
            target.origin.x = mid - size.width / 2
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = dropped != nil ? 0.38 : 0.32
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                self.animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true)
        }
        UserDefaults.standard.set("\(target.midX) \(target.minY)", forKey: anchorKey)
    }
}
