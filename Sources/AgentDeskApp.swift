import AppKit
import Combine
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = DeskStore()
    var panel: FloatingPanel!
    var status: NSStatusItem!
    var monitor: Any?
    var voiceHotkeys: VoiceHotkeys?
    var voiceWindow: NSWindow?
    var tutorialWindow: NSWindow?
    var proWindow: NSWindow?
    var flowWindow: NSWindow?
    var dashWindow: NSWindow?
    var styleSync: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if offerMoveToApplications() { return }
        migrateFromAgentDeck()
        Chime.prepare()
        LearnedVocabulary.refresh(); Activity.prune()
        panel = FloatingPanel(store: store)
        panel.orderFrontRegardless()
        installStatusItem()
        _ = store.flows // Load saved definitions; previously active runs restart paused.
        store.showFlows = { [weak self] in self?.openFlows() }
        // el engranaje de la barra abre el panel de ajustes (antes, el menú de la barra de menús)
        store.showMenu = { [weak self] in self?.openDashboard() }
        store.hide = { [weak self] in self?.store.toggleCollapsed() }
        store.showPro = { [weak self] in self?.openPro() }
        // el último chat de IA que tuviste delante, para «Explica» y «Captura»
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let b = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.store.noteActivated(b) }
        }
        installHotkeys()
        // versiones nuevas: se mira al abrir y una vez al día; si hay, se dice en el orbe y en el menú
        Updater.shared.start()
        NotificationCenter.default.addObserver(forName: Updater.foundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let v = Updater.shared.available?.version else { return }
                self?.store.flashNote(T.s("Agent Bar \(v) is available: Settings → Update", "Hay una Agent Bar nueva (\(v)): Ajustes → Actualizar"), for: 6)
            }
        }
        // la primera vez, el tutorial que lo explica y lo deja configurado
        if !UserDefaults.standard.bool(forKey: "tutorialDone") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.openTutorial() } }
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
                // un permiso trae lo que quiere hacer (orden, archivo, cambios): se lee antes de que hookMessage borre el archivo
                let change = v("kind") == "permission" ? PermissionChange.read(file: v("file")) : nil
                let msg = change?.summary ?? (v("file").isEmpty ? v("msg") : DeskStore.hookMessage(file: v("file")))
                if change != nil { DeskStore.dropHookFile(v("file")) }
                store.raiseAlert(app: v("app"), ask: v("kind") != "done", place: v("place"), message: msg, host: v("host"), token: v("file"), waiting: v("wait") == "1", change: change,
                                 autopilotEnd: v("ap"), turns: Int(v("n")) ?? 0)
            case "queued": // el gancho mandó lo siguiente de la cola de esa carpeta
                let v = { (n: String) in q.first(where: { $0.name == n })?.value ?? "" }
                store.queueSent(place: v("place"), left: Int(v("left")) ?? 0)
            case "released": // el gancho de esa conversación dejó de esperar
                store.alertReleased(token: q.first(where: { $0.name == "file" })?.value ?? "")
            case "autopilot": // lo manda AgentBarClaudeHook cada vez que el piloto sigue solo
                let v = { (n: String) in q.first(where: { $0.name == n })?.value ?? "" }
                store.autopilotTurn(left: Int(v("left")) ?? 0, place: v("place"))
            case "press":
                if let n = q.first(where: { $0.name == "n" })?.value.flatMap(Int.init) { store.press(hotkey: n) }
            case "pack": // agentdeck://pack?d=<base64url>: un pack compartido; siempre pregunta antes
                if let d = q.first(where: { $0.name == "d" })?.value, let p = KeyPack.decode(d) { offerPack(p) }
                else { store.flashNote(T.s("That pack link isn't valid", "Ese enlace de pack no es válido")) }
            case "send":
                if let t = q.first(where: { $0.name == "text" })?.value, !t.isEmpty {
                    Sender.send(t, enter: (q.first { $0.name == "enter" }?.value ?? "1") != "0")
                }
            default: break
            }
        }
    }

    // MARK: barra de menús

    /// La marca de Agent Bar para la barra de menús (plantilla: macOS la pinta en claro u oscuro): la barra, dos teclas y la principal.
    static func menuBarMark() -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 14), flipped: false) { _ in
            NSColor.black.set()
            let bar = NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 18, height: 10), xRadius: 5, yRadius: 5)
            bar.lineWidth = 1.4; bar.stroke()
            NSBezierPath(ovalIn: NSRect(x: 4.1, y: 5.6, width: 2.8, height: 2.8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 7.9, y: 5.6, width: 2.8, height: 2.8)).fill()
            NSBezierPath(roundedRect: NSRect(x: 11.6, y: 4.4, width: 5.2, height: 5.2), xRadius: 2.6, yRadius: 2.6).fill()
            return true
        }
        img.isTemplate = true; img.accessibilityDescription = "Agent Bar"
        return img
    }

    /// Agent Deck pasó a llamarse Agent Bar (0.12): la app nueva es «Agent Bar.app». Al abrirla desde Aplicaciones, los ganchos
    /// de Claude Code y de Codex que apuntaban a la copia vieja pasan a esta (con copia antes), y la copia vieja se cierra y va a la Papelera.
    func migrateFromAgentDeck() {
        let here = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard here.lastPathComponent == "Agent Bar.app" else { return }
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        let oldDir = here.deletingLastPathComponent().appendingPathComponent("Agent Deck.app")
        let oldHelpers = oldDir.path + "/Contents/Helpers/", newHelpers = here.path + "/Contents/Helpers/"
        for file in [home.appendingPathComponent(".claude/settings.json"), home.appendingPathComponent(".codex/hooks.json")] {
            guard var text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let before = text
            text = text.replacingOccurrences(of: oldHelpers, with: newHelpers)
            text = text.replacingOccurrences(of: oldHelpers.replacingOccurrences(of: "/", with: "\\/"), with: newHelpers.replacingOccurrences(of: "/", with: "\\/"))
            guard text != before, (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil else { continue }
            let backup = file.deletingLastPathComponent().appendingPathComponent(file.lastPathComponent + ".agentdeck-backup")
            try? fm.removeItem(at: backup); try? fm.copyItem(at: file, to: backup)
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
        guard fm.fileExists(atPath: oldDir.path), Bundle(url: oldDir)?.bundleIdentifier == Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "") where app.processIdentifier != me { app.terminate() }
        NSWorkspace.shared.recycle([oldDir]) { _, error in if let error { NSLog("Agent Bar: no se pudo llevar Agent Deck a la Papelera: \(error)") } }
    }

    func installStatusItem() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = Self.menuBarMark()
        }
        // Lo justo: todo lo demás vive en Ajustes (el panel), que ya lo tiene todo con su explicación.
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(withTitle: T.s("Settings…", "Ajustes…"), action: #selector(openDashboard), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: T.s("Show or hide the bar", "Mostrar u ocultar la barra"), action: #selector(togglePanel), keyEquivalent: "d")
        menu.items.last?.keyEquivalentModifierMask = [.control, .option]
        let alerts = NSMenuItem(title: T.s("Claude Code alerts", "Avisos de Claude Code"), action: #selector(toggleClaudeAlerts(_:)), keyEquivalent: "")
        alerts.tag = 7001
        menu.addItem(alerts)
        menu.addItem(.separator())
        menu.addItem(withTitle: T.s("Quit Agent Bar", "Salir de Agent Bar"), action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        status.menu = menu
    }

    @objc func togglePanel() {
        if !panel.isVisible { panel.orderFrontRegardless(); store.collapsed = false; return }
        store.toggleCollapsed()
    }


    @objc func openAccessibility() {
        _ = Sender.accessibilityGranted(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Un pack (de la lista o de un enlace): enseña sus teclas y pregunta si añadirlas o reemplazar las tuyas.
    func offerPack(_ p: KeyPack) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = T.s("Add the «\(p.name)» pack?", "¿Añadir el pack «\(p.name)»?")
        a.informativeText = p.keys.prefix(12).map { "• \($0.label) — «\($0.text.prefix(80))»" }.joined(separator: "\n")
        a.addButton(withTitle: T.s("Add to my keys", "Añadir a mis teclas"))
        a.addButton(withTitle: T.s("Replace my keys", "Reemplazar mis teclas"))
        a.addButton(withTitle: T.s("Cancel", "Cancelar"))
        switch a.runModal() {
        case .alertFirstButtonReturn: store.install(p, replace: false)
        case .alertSecondButtonReturn: store.install(p, replace: true)
        default: break
        }
    }
    @objc func shareKeys() {
        Sender.copy(store.currentPack.shareURL)
        store.flashNote(T.s("Link copied: paste it anywhere", "Enlace copiado: pégalo donde quieras"), for: 3)
    }
    @objc func morePacks() { if let u = URL(string: "https://getagentbar.com/packs/") { NSWorkspace.shared.open(u) } }
    @objc func openPro() {
        if proWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Agent Bar Pro"; w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ProView(license: License.shared)); w.center(); proWindow = w
        }
        proWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openTutorial() {
        if tutorialWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = T.s("Welcome to Agent Bar", "Bienvenido a Agent Bar"); w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(store: store, voice: store.voice,
                connectClaude: { [weak self] in self?.connectClaude() },
                finish: { [weak self] in UserDefaults.standard.set(true, forKey: "tutorialDone"); self?.tutorialWindow?.close(); self?.store.collapsed = false; self?.panel.orderFrontRegardless() }))
            w.center(); tutorialWindow = w
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in UserDefaults.standard.set(true, forKey: "tutorialDone") }
        }
        tutorialWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openVoice() {
        if voiceHotkeys?.hasTap == false && !store.voice.active { voiceHotkeys?.install() }
        if voiceWindow == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:680),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title=T.s("Agent Bar · Voice", "Agent Bar · Voz");window.minSize=NSSize(width:680,height:540);window.isReleasedWhenClosed=false
            window.contentView=NSHostingView(rootView:VoiceWorkspaceView(voice:store.voice));window.center();voiceWindow=window
        }
        voiceWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func openFlows() {
        if flowWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 730), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Agent Bar · Flujos"; window.minSize = NSSize(width: 640, height: 540); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: FlowWorkspaceView(flow: store.flows)); window.center(); flowWindow = window
        }
        flowWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func pauseFlow() { store.flows.pause() }
    /// El panel de ajustes: lo abre el engranaje de la barra y «Ajustes…» del menú.
    @objc func openDashboard() {
        if dashWindow == nil {
            let actions = DashboardActions(
                connectClaude: { [weak self] in self?.connectClaude() },
                removeClaudeAlerts: { [weak self] in self?.removeClaudeAlerts() },
                openVoice: { [weak self] in self?.openVoice() },
                openFlows: { [weak self] in self?.openFlows() },
                pauseFlow: { [weak self] in self?.pauseFlow() },
                openTutorial: { [weak self] in self?.openTutorial() },
                openAccessibility: { [weak self] in self?.openAccessibility() },
                offerPack: { [weak self] p in self?.offerPack(p) },
                shareKeys: { [weak self] in self?.shareKeys() },
                morePacks: { [weak self] in self?.morePacks() },
                toggleBar: { [weak self] in self?.togglePanel() },
                quit: { [weak self] in self?.quit() },
                relaunch: {
                    // abre otra copia de esta app cuando esta ya se ha cerrado, para cambiar de idioma
                    let path = Bundle.main.bundleURL.path
                    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
                    p.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
                    try? p.run(); NSApp.terminate(nil)
                })
            dashWindow = makeDashboardWindow(root: DashboardView(store: store, voice: store.voice, actions: actions))
        }
        dashWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationWillTerminate(_ notification: Notification) { store.flows.shutdown();voiceHotkeys?.uninstall();store.voice.shutdown();Sender.shutdown() }
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
    // MARK: avisos de Claude Code: encender, apagar, quitar

    @objc func installUpdate() { Updater.shared.install(); openDashboard() }

    /// Al abrir el menú, el interruptor de avisos enseña el estado real (o «Activar…» si aún no están puestos).
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let old = menu.items.first(where: { $0.tag == 7002 }) { menu.removeItem(old) }
        if let v = Updater.shared.available?.version {
            let up = NSMenuItem(title: T.s("Update to \(v)…", "Actualizar a la \(v)…"), action: #selector(installUpdate), keyEquivalent: "")
            up.target = self; up.tag = 7002; menu.insertItem(up, at: 0)
        }
        guard let it = menu.items.first(where: { $0.tag == 7001 }) else { return }
        if ClaudeHooks.installed {
            it.title = T.s("Claude Code alerts", "Avisos de Claude Code")
            it.action = #selector(toggleClaudeAlerts(_:)); it.state = ClaudeHooks.paused ? .off : .on
        } else {
            it.title = ClaudeHooks.oldVersion ? T.s("Update Claude Code alerts…", "Actualizar avisos de Claude Code…") : T.s("Turn on Claude Code alerts…", "Activar avisos de Claude Code…")
            it.action = #selector(connectClaude); it.state = .off
        }
    }
    @objc func toggleClaudeAlerts(_ sender: NSMenuItem) {
        ClaudeHooks.paused.toggle()
        if ClaudeHooks.paused { store.setAutopilot(0) }
        store.flashNote(ClaudeHooks.paused ? T.s("Claude Code alerts off", "Avisos de Claude Code apagados") : T.s("Claude Code alerts on", "Avisos de Claude Code activados"))
    }
    @objc func removeClaudeAlerts() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = T.s("Remove Agent Bar from Claude Code?", "¿Quitar Agent Bar de Claude Code?")
        a.informativeText = T.s("The Agent Bar hooks are removed from ~/.claude/settings.json (a backup is saved first). Nothing else changes. Restart Claude Code sessions. You can turn them on again any time.", "Se quitan los ganchos de Agent Bar de ~/.claude/settings.json (antes se guarda una copia). No cambia nada más. Reinicia las sesiones de Claude Code. Puedes volver a activarlos cuando quieras.")
        a.addButton(withTitle: T.s("Remove", "Quitar")); a.addButton(withTitle: T.s("Cancel", "Cancelar"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        switch ClaudeHooks.uninstall() {
        case .failed(let why): let e = NSAlert(); e.messageText = why; e.runModal()
        default: store.setAutopilot(0); store.flashNote(T.s("Removed from Claude Code", "Quitado de Claude Code"))
        }
    }

    @objc func connectClaude() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        if ClaudeHooks.permissionsInstalled {
            a.messageText = T.s("Claude Code alerts are on", "Los avisos de Claude Code están activos")
            a.informativeText = T.s("When Claude Code finishes or needs you, Agent Bar lights up and plays a sound. To turn them off, remove the two hooks with «agentdeck://alert» from ~/.claude/settings.json.", "Cuando Claude Code termina o te necesita, Agent Bar se enciende y suena. Para quitarlos, borra los dos ganchos con «agentdeck://alert» de ~/.claude/settings.json.")
            a.addButton(withTitle: T.s("Try an alert", "Probar un aviso")); a.addButton(withTitle: "OK")
            if a.runModal() == .alertFirstButtonReturn { store.raiseAlert(app: "Claude Code", ask: false, place: T.s("test", "prueba")) }
            return
        }
        let upgrade = ClaudeHooks.installed
        if upgrade {
            a.messageText = T.s("Answer Claude Code's permissions from the bar?", "¿Contestar los permisos de Claude Code desde la barra?")
            a.informativeText = T.s("When Claude Code asks to run a command or change a file, a card shows what it wants with Allow, No and See changes. Saying no can carry your reason, and Claude adjusts. With no answer in 60 s, Claude shows its usual dialog. Agent Bar adds one hook (PermissionRequest) to ~/.claude/settings.json and saves a backup first. Restart Claude Code sessions to pick it up.", "Cuando Claude Code pida ejecutar una orden o cambiar un archivo, una tarjeta te enseña qué quiere con Permitir, No y Ver cambios. Al decir que no puedes darle el motivo, y Claude se adapta. Sin respuesta en 60 s, Claude enseña su diálogo de siempre. Agent Bar añade un gancho (PermissionRequest) a ~/.claude/settings.json y antes guarda una copia. Reinicia las sesiones de Claude Code para que lo use.")
            a.addButton(withTitle: T.s("Add", "Añadir")); a.addButton(withTitle: T.s("Cancel", "Cancelar"))
        } else {
        a.messageText = T.s("Get an alert when Claude Code finishes?", "¿Avisarte cuando Claude Code termine?")
        a.informativeText = T.s("Agent Bar will add three hooks to ~/.claude/settings.json: when Claude Code finishes (Stop), when it needs your answer (Notification), and when it asks for permission (PermissionRequest), so you can allow or refuse from the bar; with no answer in 60 s Claude shows its usual dialog. A copy of the file is saved first as settings.json.agentdeck-backup. Nothing else changes. Restart Claude Code sessions to pick them up.", "Agent Bar añadirá tres ganchos a ~/.claude/settings.json: cuando Claude Code termina (Stop), cuando necesita tu respuesta (Notification) y cuando pide permiso (PermissionRequest), para que permitas o no desde la barra; sin respuesta en 60 s, Claude enseña su diálogo de siempre. Antes guarda una copia del archivo como settings.json.agentdeck-backup. No cambia nada más. Reinicia las sesiones de Claude Code para que los lean.")
        a.addButton(withTitle: T.s("Turn on alerts", "Activar avisos")); a.addButton(withTitle: T.s("Cancel", "Cancelar"))
        }
        guard a.runModal() == .alertFirstButtonReturn else { return }
        switch ClaudeHooks.install() {
        case .added, .alreadyThere:
            if upgrade { store.flashNote(T.s("Permissions from the bar: restart Claude Code", "Permisos desde la barra: reinicia Claude Code"), for: 4) }
            else { store.raiseAlert(app: "Claude Code", ask: false, place: T.s("alerts on", "avisos activos")) }
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
                if code == 14 { self.store.explainSelection(); return } // E
                if code == 1 { self.store.snapScreen(); return }        // S
                if let chars,let n=Int(chars),(1...9).contains(n){self.store.press(hotkey:n)}
            }
        }
    }
}
