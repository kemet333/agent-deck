import AppKit

/// Mantener Fn para hablar: al pulsar empieza a escuchar; al soltar, lo oído se escribe en el chat y se envía.
/// Funciona con la barra desplegada o plegada en el orbe. Un tap de eventos propio se queda solo con Fn,
/// para que macOS no abra a la vez sus emojis ni su dictado. Necesita el permiso de Accesibilidad.
/// Si con Fn pulsada se teclea otra tecla (Fn+flecha…), es un atajo: se cancela y no se envía nada.
/// Escape también cancela.
final class FnKey {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: DispatchWorkItem?
    private var down = false
    private var talking = false
    /// Lo que tarda en empezar a escuchar: un toque corto de Fn no abre el micro.
    private let holdDelay = 0.18
    var onStart: (() -> Void)?
    var onEnd: (() -> Void)?
    var onCancel: (() -> Void)?
    var installed: Bool { tap != nil }

    @discardableResult
    func install() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, ref in
            guard let ref else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<FnKey>.fromOpaque(ref).takeUnretainedValue()
            return me.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// true: el evento es nuestro y no sigue hacia las apps.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown {
            if code == 53, talking { abort(); return true } // Escape
            if down { abort() }                             // Fn + otra tecla: es un atajo, no voz
            return false
        }
        guard type == .flagsChanged, code == 63 else { return false }
        let flags = event.flags
        let others = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if flags.contains(.maskSecondaryFn) {
            guard others.isEmpty, !down else { return false }
            down = true
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.down else { return }
                self.talking = true
                self.onStart?()
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: work)
            return true
        }
        guard down else { return false }
        down = false
        pending?.cancel(); pending = nil
        if talking { talking = false; onEnd?() }
        return true
    }

    private func abort() {
        down = false
        pending?.cancel(); pending = nil
        if talking { talking = false; onCancel?() }
    }
}
