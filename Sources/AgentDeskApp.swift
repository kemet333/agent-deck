import AppKit
import ServiceManagement
import SwiftUI

@main
@MainActor
struct AgentDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings {
            DeckSettingsView(store: delegate.store)
                .frame(minWidth: 680, idealWidth: 760, minHeight: 540, idealHeight: 680)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DeskStore()
    var panel: FloatingPanel!
    var status: NSStatusItem!
    var monitor: Any?
    var voiceHotkeys: VoiceHotkeys?
    var voiceWindow: NSWindow?
    var flowWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = FloatingPanel(store: store)
        panel.orderFrontRegardless()
        installStatusItem()
        _ = store.flows // Load saved definitions; previously active runs restart paused.
        store.showFlows = { [weak self] in self?.openFlows() }
        store.showMenu = { [weak self] in
            guard let self = self, let menu = self.status.menu else { return }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
        store.hide = { [weak self] in self?.store.toggleCollapsed() }
        installHotkeys()
        voiceHotkeys = VoiceHotkeys(voice: store.voice); voiceHotkeys?.install()
        store.voice.showWorkspace = { [weak self] in self?.openVoice() }
        store.voice.showDeck = { [weak self] in guard let self else{return};self.voiceWindow?.orderOut(nil);self.store.collapsed=false;self.panel.orderFrontRegardless() }
        store.voice.onShortcutsChanged = { [weak self] in if self?.store.voice.active == true{self?.store.voice.cancel()};self?.voiceHotkeys?.install() }
        _ = Sender.accessibilityGranted(prompt: true)
    }

    // MARK: URL scheme: agentdeck://toggle · dictate · press?n=3 · send?text=hola · show
    // Para Atajos, Raycast, un Stream Deck físico o un script: `open "agentdeck://press?n=1"`.

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch url.host {
            case "toggle": togglePanel()
            case "show": panel.orderFrontRegardless(); store.collapsed = false
            case "dictate": DispatchQueue.main.async { self.store.toggleDictation() }
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
        menu.addItem(withTitle: T.s("Message flows…", "Flujos de mensajes…"), action: #selector(openFlows), keyEquivalent: "f")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(withTitle: T.s("Pause message flow", "Pausar flujo de mensajes"), action: #selector(pauseFlow), keyEquivalent: "p")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(withTitle: T.s("Dictate to the chat", "Dictar al chat"), action: #selector(dictate), keyEquivalent: "m")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(withTitle: T.s("Voice, drafts & history…", "Voz, borradores e historial…"), action: #selector(openVoice), keyEquivalent: ",")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(withTitle: T.s("Paste last transcription", "Pegar última transcripción"), action: #selector(pasteLastVoice), keyEquivalent: "l")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        let modeItem = NSMenuItem(title: T.s("Mode", "Modo"), action: nil, keyEquivalent: "")
        let modes = NSMenu()
        let dock = NSMenuItem(title: T.s("Bar (bottom of the screen)", "Barra (abajo)"), action: #selector(setDock), keyEquivalent: ""); dock.target = self
        let card = NSMenuItem(title: T.s("Floating card", "Tarjeta flotante"), action: #selector(setCard), keyEquivalent: ""); card.target = self
        modes.addItem(dock); modes.addItem(card)
        modeItem.submenu = modes
        menu.addItem(modeItem)
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
    @objc func pasteLastVoice() { store.voice.pasteLast() }
    @objc func openVoice() {
        if voiceHotkeys?.hasTap == false && !store.voice.active { voiceHotkeys?.install() }
        if voiceWindow == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:680),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title=T.s("Agent Deck · Voice", "Agent Deck · Voz");window.minSize=NSSize(width:680,height:540);window.isReleasedWhenClosed=false
            window.contentView=NSHostingView(rootView:VoiceWorkspaceView(voice:store.voice));window.center();voiceWindow=window
        }
        voiceWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func openFlows() {
        if flowWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 730), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Agent Deck · Flujos"; window.minSize = NSSize(width: 640, height: 540); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: FlowWorkspaceView(flow: store.flows)); window.center(); flowWindow = window
        }
        flowWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func pauseFlow() { store.flows.pause() }
    func applicationWillTerminate(_ notification: Notification) { store.flows.shutdown();voiceHotkeys?.uninstall();store.voice.shutdown();Sender.shutdown() }
    @objc func dictate() { DispatchQueue.main.async { self.store.toggleDictation() } }
    @objc func setDock() { store.mode = .dock }
    @objc func setCard() { store.mode = .card }
    @objc func quit() { NSApp.terminate(nil) }

    // MARK: atajos globales ⌃⌥1…9 y ⌃⌥D

    func installHotkeys() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods=event.modifierFlags.intersection([.control,.option,.command,.shift]), code=event.keyCode, chars=event.charactersIgnoringModifiers
            Task { @MainActor [weak self] in
                guard let self,mods == [.control,.option] else { return }
                if code == 2 { self.togglePanel(); return }
                if code == 3 { self.openFlows(); return }
                if code == 35 { self.pauseFlow(); return }
                if code == 43 { self.openVoice(); return }
                if code == 37 { self.store.voice.pasteLast(); return }
                if code == 46 { self.store.toggleDictation(); return }
                if let chars,let n=Int(chars),(1...9).contains(n){self.store.press(hotkey:n)}
            }
        }
    }
}
