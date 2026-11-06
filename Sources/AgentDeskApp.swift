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
        if offerMoveToApplications() { return }
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
        // sin Accesibilidad todavía, el tap de Fn no se crea: se reintenta hasta que se dé el permiso, sin reabrir la app
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let hk = self.voiceHotkeys else { t.invalidate(); return }
                if hk.hasTap { t.invalidate(); return }
                if Sender.accessibilityGranted(prompt: false) { hk.install() }
            }
        }
        store.voice.showWorkspace = { [weak self] in self?.openVoice() }
        store.voice.showDeck = { [weak self] in guard let self else{return};self.voiceWindow?.orderOut(nil);self.store.collapsed=false;self.panel.orderFrontRegardless() }
        store.voice.onShortcutsChanged = { [weak self] in if self?.store.voice.active == true{self?.store.voice.cancel()};self?.voiceHotkeys?.install() }
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
            case "alert": // agentdeck://alert?app=Claude%20Code&kind=done|ask&place=proyecto
                let v = { (n: String) in q.first(where: { $0.name == n })?.value ?? "" }
                let msg = v("file").isEmpty ? v("msg") : DeskStore.hookMessage(file: v("file"))
                store.raiseAlert(app: v("app"), ask: v("kind") == "ask", place: v("place"), message: msg, host: v("host"))
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
        let hooksItem = NSMenuItem(title: T.s("Claude Code alerts…", "Avisos de Claude Code…"), action: #selector(connectClaude), keyEquivalent: "")
        hooksItem.target = self
        menu.addItem(hooksItem)
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
    @objc func setStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let st = BarStyle(rawValue: raw) else { return }
        store.style = st
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }
    /// Abierta desde Descargas o desde el disco, macOS la ejecuta desde una carpeta temporal y no deja darle
    /// Accesibilidad ni micrófono de forma estable. Se ofrece a copiarse en Aplicaciones y abrirse desde allí.
    /// Devuelve true si va a relanzarse desde Aplicaciones.
    func offerMoveToApplications() -> Bool {
        let here = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let path = here.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") { return false }
        if path.hasPrefix(home + "/Agent-Deck/") || UserDefaults.standard.bool(forKey: "neverMoveToApplications") { return false } // copia de desarrollo
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = T.s("Move Agent Bar to Applications?", "¿Muevo Agent Bar a Aplicaciones?")
        a.informativeText = T.s("macOS only keeps Accessibility and the microphone for apps in Applications. It will open from there.", "macOS solo mantiene Accesibilidad y el micrófono para las apps de Aplicaciones. Se abrirá desde allí.")
        a.addButton(withTitle: T.s("Move to Applications", "Mover a Aplicaciones"))
        a.addButton(withTitle: T.s("Not now", "Ahora no"))
        a.showsSuppressionButton = true
        a.suppressionButton?.title = T.s("Don't ask again", "No volver a preguntar")
        let answer = a.runModal()
        if a.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: "neverMoveToApplications") }
        guard answer == .alertFirstButtonReturn else { return false }
        let dest = URL(fileURLWithPath: "/Applications").appendingPathComponent(here.lastPathComponent)
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) } // la versión anterior, a la Papelera
            try fm.copyItem(at: here, to: dest)
        } catch {
            let e = NSAlert()
            e.messageText = T.s("Couldn't move it", "No se ha podido mover")
            e.informativeText = T.s("Drag Agent Bar into Applications in the Finder, then open it from there.", "Arrastra Agent Bar a Aplicaciones en el Finder y ábrela desde allí.")
            e.runModal()
            NSWorkspace.shared.activateFileViewerSelecting([here])
            return false
        }
        // el original, si está en una carpeta normal (no la temporal de macOS), a la Papelera
        if !path.contains("/AppTranslocation/") && !path.hasPrefix("/Volumes/") { try? fm.trashItem(at: here, resultingItemURL: nil) }
        let cfg = NSWorkspace.OpenConfiguration(); cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: cfg) { _, _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
        return true
    }

    /// Conectar los avisos de Claude Code: pregunta antes y explica exactamente qué cambia.
    @objc func connectClaude() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        if ClaudeHooks.installed {
            a.messageText = T.s("Claude Code alerts are on", "Los avisos de Claude Code están activos")
            a.informativeText = T.s("When Claude Code finishes or needs you, Agent Deck lights up and plays a sound. To turn them off, remove the two hooks with «agentdeck://alert» from ~/.claude/settings.json.", "Cuando Claude Code termina o te necesita, Agent Deck se enciende y suena. Para quitarlos, borra los dos ganchos con «agentdeck://alert» de ~/.claude/settings.json.")
            a.addButton(withTitle: T.s("Try an alert", "Probar un aviso")); a.addButton(withTitle: "OK")
            if a.runModal() == .alertFirstButtonReturn { store.raiseAlert(app: "Claude Code", ask: false, place: T.s("test", "prueba")) }
            return
        }
        a.messageText = T.s("Get an alert when Claude Code finishes?", "¿Avisarte cuando Claude Code termine?")
        a.informativeText = T.s("Agent Deck will add two hooks to ~/.claude/settings.json: one when Claude Code finishes (Stop) and one when it needs your permission or answer (Notification). A copy of the file is saved first as settings.json.agentdeck-backup. Nothing else changes. Restart Claude Code sessions to pick them up.", "Agent Deck añadirá dos ganchos a ~/.claude/settings.json: uno cuando Claude Code termina (Stop) y otro cuando necesita tu permiso o tu respuesta (Notification). Antes guarda una copia del archivo como settings.json.agentdeck-backup. No cambia nada más. Reinicia las sesiones de Claude Code para que los lean.")
        a.addButton(withTitle: T.s("Turn on alerts", "Activar avisos")); a.addButton(withTitle: T.s("Cancel", "Cancelar"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        switch ClaudeHooks.install() {
        case .added, .alreadyThere: store.raiseAlert(app: "Claude Code", ask: false, place: T.s("alerts on", "avisos activos"))
        case .failed(let why): let e = NSAlert(); e.messageText = why; e.runModal()
        }
    }
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
