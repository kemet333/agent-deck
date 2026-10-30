import AppKit
import ServiceManagement
import SwiftUI

@main
struct AgentDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DeskStore()
    var panel: FloatingPanel!
    var status: NSStatusItem!
    var monitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = FloatingPanel(store: store)
        panel.orderFrontRegardless()
        installStatusItem()
        store.showMenu = { [weak self] in
            guard let self = self, let menu = self.status.menu else { return }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        store.hide = { [weak self] in self?.panel.orderOut(nil) }
        installHotkeys()
        _ = Sender.accessibilityGranted(prompt: true)
    }

    // MARK: barra de menús

    func installStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Agent Desk")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Mostrar u ocultar el Desk", action: #selector(togglePanel), keyEquivalent: "d")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(withTitle: "Dictar al chat", action: #selector(dictate), keyEquivalent: "m")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        let modeItem = NSMenuItem(title: "Modo", action: nil, keyEquivalent: "")
        let modes = NSMenu()
        let dock = NSMenuItem(title: "Dock (barra abajo)", action: #selector(setDock), keyEquivalent: ""); dock.target = self
        let card = NSMenuItem(title: "Tarjeta flotante", action: #selector(setCard), keyEquivalent: ""); card.target = self
        modes.addItem(dock); modes.addItem(card)
        modeItem.submenu = modes
        menu.addItem(modeItem)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(withTitle: "Permiso de Accesibilidad…", action: #selector(openAccessibility), keyEquivalent: "")
        menu.addItem(withTitle: "Restaurar teclas de fábrica", action: #selector(restoreDefaults), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de Agent Desk", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        status.menu = menu
    }

    @objc func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSLog("Agent Desk: inicio de sesión: \(error)") }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc func openAccessibility() {
        _ = Sender.accessibilityGranted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func restoreDefaults() { store.restoreDefaults() }
    @objc func dictate() { DispatchQueue.main.async { self.store.toggleDictation() } }
    @objc func setDock() { store.mode = .dock }
    @objc func setCard() { store.mode = .card }
    @objc func quit() { NSApp.terminate(nil) }

    // MARK: atajos globales ⌃⌥1…9 y ⌃⌥D

    func installHotkeys() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
            guard mods == [.control, .option] else { return }
            if event.keyCode == 2 { self.togglePanel(); return } // D
            if event.keyCode == 46 { DispatchQueue.main.async { self.store.toggleDictation() }; return } // M
            if let chars = event.charactersIgnoringModifiers, let n = Int(chars), (1...9).contains(n) {
                self.store.press(hotkey: n)
            }
        }
    }
}
