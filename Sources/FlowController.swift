import AppKit
import Combine
import Foundation
import Darwin

enum FlowConnector {
    static let marker = "Agent Deck · flujo de mensajes"
    static var helper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AgentDeckFlowHook") }
    static var configuration: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json") }
    static func command(_ helper: URL) -> String { "'" + helper.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func groups(helper: URL) -> [String: [[String: Any]]] {
        var result: [String: [[String: Any]]] = [:]
        for event in FlowEngine.events.sorted() {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command(helper), "timeout": 3, "statusMessage": marker]]]
            if event == "PreToolUse" { group["matcher"] = "(^|__|[.:])(request_user_input|request_user_input_async|AskUserQuestion)$" }
            result[event] = [group]
        }
        return result
    }
    static func merged(_ data: Data?, helper: URL, removing: Bool = false) throws -> Data {
        var root: [String: Any] = [:]
        if let data {
            guard data.count <= 1_048_576, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FlowIssue(message: "La configuración de hooks existente no es válida. No se ha sustituido.") }
            root = object
        }
        guard root["hooks"] == nil || root["hooks"] is [String: Any] else { throw FlowIssue(message: "La estructura de hooks existente no es compatible.") }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, additions) in groups(helper: helper) {
            guard hooks[event] == nil || hooks[event] is [[String: Any]] else { throw FlowIssue(message: "El evento \(event) no tiene una lista de hooks válida.") }
            var current = hooks[event] as? [[String: Any]] ?? []
            // Modify only our exact command + marker; preserve other handlers, groups and metadata.
            current = current.compactMap { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                var copy = group
                let kept = handlers.filter { !($0["command"] as? String == command(helper) && $0["statusMessage"] as? String == marker) }
                if kept.isEmpty && kept.count != handlers.count { return nil }
                copy["hooks"] = kept; return copy
            }
            if !removing { current.append(contentsOf: additions) }
            hooks[event] = current
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
    static func install() throws -> String {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw FlowIssue(message: "Falta el conector compilado en esta app. Compila o instala la candidata completa.") }
        let fm = FileManager.default, target = configuration
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let new = try merged(nil, helper: helper)
        let created = try createIfAbsent(new, at: target)
        if !created {
            // Never replace any existing user hooks file, including one created by another writer
            // during setup. Export only our fragment: no other configuration or secrets copied.
            let ownFolder = FlowStorage.standard.folder
            try fm.createDirectory(at: ownFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let fragment = ownFolder.appendingPathComponent("Codex-hooks-fragment.json")
            try new.write(to: fragment, options: .atomic); try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fragment.path)
            return "Ya existe hooks.json y no se ha modificado. El fragmento del conector está en \(fragment.path). Combínalo con tu configuración y revisa/confía en los hooks desde Ajustes → Hooks de Codex."
        }
        return "Conector preparado. En Codex, abre Ajustes → Hooks y revisa/confía en estos hooks. Si tu versión no los recarga, reinicia Codex cuando acabes tu tarea."
    }
    static func createIfAbsent(_ data: Data, at target: URL) throws -> Bool {
        let fm = FileManager.default
        let stage = target.deletingLastPathComponent().appendingPathComponent(".agent-deck-hooks-" + UUID().uuidString)
        defer { try? fm.removeItem(at: stage) }
        try data.write(to: stage, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stage.path)
        // Atomic hard-link publication creates a complete file or fails with EEXIST. It cannot
        // overwrite a concurrent editor's file, symlink, directory or an existing configuration.
        if link(stage.path, target.path) == 0 { return true }
        if errno == EEXIST { return false }
        throw FlowIssue(message: "No se ha podido crear la configuración de Codex. La configuración existente no se ha sustituido.")
    }
}

@MainActor
final class FlowController: ObservableObject {
    @Published private(set) var database = FlowDatabase()
    @Published var error = ""
    @Published var connectionNote = ""
    let storage: FlowStorage
    let reviewMode: Bool
    private var timer: Timer?
    var active: Bool { database.run?.active == true }

    init(storage: FlowStorage = .standard, reviewMode: Bool = false) {
        self.storage = storage; self.reviewMode = reviewMode
        perform { db in if db.run?.active == true { db.run?.pause("Agent Bar se ha reiniciado. Revisa el flujo antes de reanudarlo.") } }
        if !reviewMode {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        }
    }
    private func perform(_ action: (inout FlowDatabase) throws -> Void) {
        do {
            let value = try storage.transaction { db -> FlowDatabase in try action(&db); return db }
            if value != database { database = value }; error = ""
        } catch { self.error = error.localizedDescription }
    }
    func refresh() {
        let now = Date().timeIntervalSince1970
        perform { db in
            if db.run?.active == true {
                if now > db.run!.expires || now < db.run!.created || now > db.run!.leaseUntil { db.run?.pause("El flujo ha caducado o Agent Bar dejó de estar disponible. Revisa antes de reanudarlo.") }
                else { db.run?.leaseUntil = now + 15 }
            }
        }
    }
    func save(_ definition: MessageFlow) {
        perform { db in
            _ = try definition.messages()
            if let i = db.definitions.firstIndex(where: { $0.id == definition.id }) { db.definitions[i] = definition }
            else {
                guard db.definitions.count < 30 else { throw FlowIssue(message: "Puedes guardar hasta 30 flujos.") }
                db.definitions.append(definition)
            }
        }
    }
    func arm(_ definition: MessageFlow, sessionID: String) {
        guard !reviewMode else { return }
        let now = Date().timeIntervalSince1970
        perform { db in try db.arm(definition, sessionID: sessionID, now: now) }
    }
    func pause() { perform { $0.run?.pause("Pausado por ti. No se enviarán más mensajes del flujo.") } }
    func cancel() { perform { db in db.run?.state = "cancelled"; db.run?.note = "Flujo cancelado. La respuesta que ya estaba en curso sigue en Codex."; db.run?.leaseUntil = 0 } }
    func resume() {
        guard !reviewMode else { return }
        let now = Date().timeIntervalSince1970
        perform { db in
            guard var run = db.run, run.state == "paused", now <= run.expires,
                  let session = db.sessions.first(where: { $0.id == run.sessionID }), session.cwd == run.cwd,
                  !["needsInput", "ended", "error"].contains(session.state) else { throw FlowIssue(message: "Resuelve primero el estado de Codex o programa un flujo nuevo.") }
            run.state = "armed"; run.expectedPromptHash = nil; run.turnID = session.turnID
            run.waitingForInitialPrompt = session.state != "running"; run.leaseUntil = now + 15
            run.note = run.waitingForInitialPrompt ? "Envía tu próxima tarea en ese chat; se conserva el progreso del flujo." : "Reanudado; esperando el final de la respuesta actual."
            db.run = run
        }
    }
    func connect() {
        guard !reviewMode else { return }
        do { connectionNote = try FlowConnector.install(); error = "" }
        catch { self.error = error.localizedDescription }
    }
    func shutdown() { timer?.invalidate(); timer = nil; if active { pause() } }
}
