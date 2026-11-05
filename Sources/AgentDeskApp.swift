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
        store.hide = { [weak self] in self?.store.toggleCollapsed() }
        installHotkeys()
        _ = Sender.accessibilityGranted(prompt: true)
    }

    // MARK: URL scheme: agentdeck://toggle · dictate · press?n=3 · send?text=hola · show · style?name=glass
    // Para Atajos, Raycast, un Stream Deck físico o un script: `open "agentdeck://press?n=1"`.

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch url.host {
            case "toggle": togglePanel()
            case "show": panel.orderFrontRegardless(); store.collapsed = false
            case "dictate": DispatchQueue.main.async { self.store.toggleDictation() }
            case "style":
                if let n = q.first(where: { $0.name == "name" })?.value, let st = BarStyle(rawValue: n) {
                    store.style = st
                    status.menu?.items.first { $0.submenu?.items.first?.representedObject != nil }?.submenu?.items.forEach {
                        $0.state = ($0.representedObject as? String) == n ? .on : .off
                    }
                }
            case "press":
                if let n = q.first(where: { $0.name == "n" })?.value.flatMap(Int.init) { store.press(hotkey: n) }
            case "send":
                if let t = q.first(where: { $0.name == "text" })?.value, !t.isEmpty {
                    Sender.send(t, enter: (q.first { $0.name == "enter" }?.value ?? "1") != "0")
                }
            default: break
            }
        }
    }

    // MARK: barra de menús

    func installStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Agent Deck")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(withTitle: T.s("Fold or unfold the deck", "Plegar o desplegar el Deck"), action: #selector(togglePanel), keyEquivalent: "d")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(withTitle: T.s("Dictate to the chat", "Dictar al chat"), action: #selector(dictate), keyEquivalent: "m")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        let modeItem = NSMenuItem(title: T.s("Mode", "Modo"), action: nil, keyEquivalent: "")
        let modes = NSMenu()
        let dock = NSMenuItem(title: T.s("Bar (bottom of the screen)", "Barra (abajo)"), action: #selector(setDock), keyEquivalent: ""); dock.target = self
        let card = NSMenuItem(title: T.s("Floating card", "Tarjeta flotante"), action: #selector(setCard), keyEquivalent: ""); card.target = self
        modes.addItem(dock); modes.addItem(card)
        modeItem.submenu = modes
        menu.addItem(modeItem)
        let styleItem = NSMenuItem(title: T.s("Style", "Estilo"), action: nil, keyEquivalent: "")
        let styles = NSMenu()
        for st in BarStyle.allCases {
            let it = NSMenuItem(title: st.title, action: #selector(setStyle(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = st.rawValue; it.state = store.style == st ? .on : .off
            styles.addItem(it)
        }
        styleItem.submenu = styles
        menu.addItem(styleItem)
        menu.addItem(.separator())
        let login = NSMenuItem(title: T.s("Open at login", "Abrir al iniciar sesión"), action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(withTitle: T.s("Accessibility permission…", "Permiso de Accesibilidad…"), action: #selector(openAccessibility), keyEquivalent: "")
        menu.addItem(withTitle: T.s("Restore default keys", "Restaurar teclas de fábrica"), action: #selector(restoreDefaults), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: T.s("Quit Agent Deck", "Salir de Agent Deck"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        status.menu = menu
    }

    @objc func togglePanel() {
        if !panel.isVisible { panel.orderFrontRegardless(); store.collapsed = false; return }
        store.toggleCollapsed()
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSLog("Agent Deck: inicio de sesión: \(error)") }
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
    @objc func setStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let st = BarStyle(rawValue: raw) else { return }
        store.style = st
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }
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
