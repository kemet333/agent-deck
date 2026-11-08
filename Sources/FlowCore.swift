import Foundation
import CryptoKit
import Darwin

struct FlowIssue: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct MessageFlow: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name = "Siguiente × 5"
    var mode = "repeat"
    var message = "siguiente"
    var repetitions = 5
    var steps = ["Revisa los cambios y ejecuta las pruebas.", "Corrige los fallos encontrados.", "Resume el resultado y lo que queda pendiente."]

    func messages() throws -> [String] {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120 else { throw FlowIssue(message: "Pon un nombre de hasta 120 caracteres.") }
        guard mode == "repeat" || mode == "sequence" else { throw FlowIssue(message: "Modo de flujo desconocido.") }
        guard (1...50).contains(repetitions) else { throw FlowIssue(message: "Elige entre 1 y 50 repeticiones.") }
        let result = mode == "repeat" ? Array(repeating: message, count: repetitions) : steps
        guard (1...50).contains(result.count) else { throw FlowIssue(message: "La secuencia admite entre 1 y 50 mensajes.") }
        guard result.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 4096 }), result.reduce(0, { $0 + $1.utf8.count }) <= 65536 else { throw FlowIssue(message: "Cada mensaje debe tener texto y como máximo 4 KB; el flujo completo admite 64 KB.") }
        return result // Preserve the exact user-authored text, including whitespace and paragraphs.
    }
}

struct FlowSession: Codable, Identifiable, Equatable {
    var id: String
    var cwd: String
    var lastSeen: Double
    var state: String
    var turnID: String?
}

struct FlowRun: Codable, Equatable {
    var id = UUID().uuidString
    var definition: MessageFlow
    var sessionID: String
    var cwd: String
    var messages: [String]
    var issued = 0
    var state = "armed"
    var note = "Esperando el final de la respuesta."
    var created: Double
    var expires: Double
    var leaseUntil: Double
    var waitingForInitialPrompt: Bool
    var expectedPromptHash: String?
    var turnID: String?
    var fingerprints: [String] = []
    var active: Bool { ["armed", "waitingResponse"].contains(state) }
    mutating func pause(_ reason: String) { state = "paused"; note = reason; leaseUntil = 0 }
}

struct FlowDatabase: Codable, Equatable {
    var version = 1
    var definitions: [MessageFlow] = [MessageFlow()]
    var sessions: [FlowSession] = []
    var run: FlowRun?
    var bridgeLastSeen: Double?

    func validate() throws {
        guard version == 1, definitions.count <= 30, sessions.count <= 60,
              Set(definitions.map(\.id)).count == definitions.count,
              Set(sessions.map(\.id)).count == sessions.count else { throw FlowIssue(message: "Estado de flujos incompatible o duplicado.") }
        for definition in definitions { _ = try definition.messages() }
        guard sessions.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 200 && $0.cwd.hasPrefix("/") && $0.cwd.utf8.count <= 4096 && $0.lastSeen.isFinite }) else { throw FlowIssue(message: "Hay un chat de destino inválido.") }
        if let run {
            guard run.messages == (try run.definition.messages()), (0...run.messages.count).contains(run.issued),
                  run.created.isFinite, run.expires.isFinite, run.leaseUntil.isFinite,
                  run.expires >= run.created, run.expires - run.created <= 86400,
                  run.fingerprints.count <= 51, !run.sessionID.isEmpty, run.cwd.hasPrefix("/"),
                  ["armed", "waitingResponse", "paused", "cancelled", "completed"].contains(run.state) else { throw FlowIssue(message: "El flujo guardado no es válido. Se conserva el archivo sin ejecutarlo.") }
        }
    }

    mutating func arm(_ definition: MessageFlow, sessionID: String, now: Double) throws {
        guard run?.active != true else { throw FlowIssue(message: "Pausa o cancela el flujo actual antes de programar otro.") }
        guard let session = sessions.first(where: { $0.id == sessionID }), now >= session.lastSeen, now - session.lastSeen <= 86400, session.state != "ended" else { throw FlowIssue(message: "Selecciona un chat detectado recientemente por el conector de Codex.") }
        guard session.state != "needsInput" else { throw FlowIssue(message: "Resuelve primero la aprobación o pregunta pendiente en Codex.") }
        run = FlowRun(definition: definition, sessionID: session.id, cwd: session.cwd, messages: try definition.messages(), created: now, expires: now + 86400, leaseUntil: now + 15, waitingForInitialPrompt: session.state != "running", turnID: session.turnID)
        if run!.waitingForInitialPrompt { run!.note = "Envía tu tarea inicial en ese chat. El flujo empezará cuando termine su respuesta." }
    }
}

struct FlowHookEvent: Decodable {
    var session_id: String?
    var cwd: String?
    var hook_event_name: String?
    var turn_id: String?
    var agent_id: String?
    var agent_type: String?
    var prompt: String?
    var last_assistant_message: String?
    var stop_hook_active: Bool?
    var tool_name: String?
    var status: String?
}

enum FlowEngine {
    static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static let events = Set(["SessionStart", "UserPromptSubmit", "Stop", "Interrupt", "PermissionRequest", "PreToolUse", "PostModelRequest", "SessionEnd"])

    static func handle(_ event: FlowHookEvent, database db: inout FlowDatabase, now: Double) -> [String: String] {
        guard let kind = event.hook_event_name, events.contains(kind), event.agent_id == nil, event.agent_type == nil,
              let id = event.session_id, !id.isEmpty, id.utf8.count <= 200,
              let cwd = event.cwd, cwd.hasPrefix("/"), cwd.utf8.count <= 4096 else { return [:] }
        db.bridgeLastSeen = now
        let old = db.sessions.first(where: { $0.id == id })
        let tool = event.tool_name?.replacingOccurrences(of: "::", with: "__").replacingOccurrences(of: ".", with: "__").components(separatedBy: "__").last ?? ""
        let question = kind == "PreToolUse" && ["request_user_input", "request_user_input_async", "AskUserQuestion"].contains(tool)
        let failed = kind == "PostModelRequest" && ["failed", "cancelled"].contains(event.status ?? "")
        let needsInput = kind == "PermissionRequest" || question
        var session = old ?? FlowSession(id: id, cwd: cwd, lastSeen: now, state: "idle")
        session.cwd = cwd; session.lastSeen = now
        if let turn = event.turn_id { session.turnID = turn }
        if kind == "UserPromptSubmit" { session.state = "running" }
        if kind == "Stop" || kind == "Interrupt" { session.state = "idle" }
        if kind == "SessionEnd" { session.state = "ended" }
        if needsInput { session.state = "needsInput" }
        if failed { session.state = "error" }
        db.sessions.removeAll { $0.id == id }
        db.sessions.append(session)
        db.sessions = Array(db.sessions.sorted { $0.lastSeen > $1.lastSeen }.prefix(60))
        guard var run = db.run, run.sessionID == id, run.active else { return [:] }
        defer { db.run = run }
        guard run.cwd == cwd else { run.pause("El directorio del chat ha cambiado. Revisa el destino."); return [:] }
        guard now >= run.created, now <= run.expires, now <= run.leaseUntil else { run.pause("El flujo ha caducado o Agent Bar no está disponible. Revisa y vuelve a programarlo."); return [:] }
        if needsInput { run.pause("Codex necesita tu aprobación o una respuesta. El flujo está pausado."); return [:] }
        if failed { run.pause("Codex ha comunicado un fallo o cancelación. Revisa el chat antes de continuar."); return [:] }
        if ["Interrupt", "SessionEnd", "SessionStart"].contains(kind) { run.pause("El chat se ha interrumpido, cerrado o reanudado. El flujo está pausado."); return [:] }
        if kind == "UserPromptSubmit" {
            guard let prompt = event.prompt else { run.pause("No se ha podido comprobar el mensaje de Codex."); return [:] }
            if run.waitingForInitialPrompt {
                run.waitingForInitialPrompt = false; run.turnID = event.turn_id
            } else if let expected = run.expectedPromptHash, digest(prompt) == expected {
                run.expectedPromptHash = nil; run.turnID = event.turn_id
            } else {
                run.pause("Has escrito otro mensaje en este chat. Revisa el flujo antes de seguir.")
            }
            return [:]
        }
        guard kind == "Stop", !run.waitingForInitialPrompt else { return [:] }
        guard let turn = event.turn_id, !turn.isEmpty, let answer = event.last_assistant_message, !answer.isEmpty, let continued = event.stop_hook_active else {
            run.pause("El evento de fin no tiene datos suficientes para continuar con seguridad."); return [:]
        }
        // Store only a digest of the completion. No assistant text or transcript is retained.
        let fingerprint = digest(turn + "\u{0}" + answer)
        guard !run.fingerprints.contains(fingerprint) else { run.pause("Evento de finalización repetido. No se ha duplicado el mensaje."); return [:] }
        if run.expectedPromptHash != nil {
            // Some hosts continue within the same turn rather than emitting UserPromptSubmit.
            // The official stop_hook_active flag and a new completion identify that continuation.
            guard continued, run.turnID == turn else { run.pause("No se ha confirmado la continuación anterior en el mismo turno. Revisa el chat."); return [:] }
            run.expectedPromptHash = nil
        } else if let expectedTurn = run.turnID, expectedTurn != turn {
            run.pause("Ha cambiado el turno sin un mensaje confirmado. Revisa el chat."); return [:]
        }
        run.fingerprints.append(fingerprint); run.turnID = turn
        guard run.issued < run.messages.count else {
            run.state = "completed"; run.note = "Secuencia terminada: todas las continuaciones han finalizado."; run.leaseUntil = 0
            return [:]
        }
        let message = run.messages[run.issued]
        run.issued += 1; run.expectedPromptHash = digest(message); run.state = "waitingResponse"
        run.note = "Continuación \(run.issued) de \(run.messages.count) emitida; esperando la siguiente respuesta."
        return ["decision": "block", "reason": message]
    }
}

/// Both the native app and short-lived Codex helper use the same private, locked JSON store.
/// Only one transaction can consume a step; cancelled/restarted runs never re-arm themselves.
struct FlowStorage {
    let folder: URL
    static var standard: FlowStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FlowStorage(folder: base.appendingPathComponent("Agent Deck/Flows", isDirectory: true))
    }
    func transaction<T>(_ action: (inout FlowDatabase) throws -> T) throws -> T {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attrs = try fm.attributesOfItem(atPath: folder.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory, (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw FlowIssue(message: "La carpeta de flujos no es un directorio privado válido.") }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let lock = open(folder.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw FlowIssue(message: "No se puede abrir el bloqueo de flujos.") }
        defer { close(lock) }
        var lockStat = Darwin.stat()
        guard fstat(lock, &lockStat) == 0, (lockStat.st_mode & S_IFMT) == S_IFREG, lockStat.st_uid == getuid() else { throw FlowIssue(message: "El bloqueo de flujos no es un archivo privado válido.") }
        let until = Date().addingTimeInterval(0.3)
        while flock(lock, LOCK_EX | LOCK_NB) != 0 {
            guard Date() < until else { throw FlowIssue(message: "Los flujos están ocupados. Vuelve a intentarlo.") }
            usleep(5_000)
        }
        defer { flock(lock, LOCK_UN) }
        let url = folder.appendingPathComponent("state.json")
        var db = FlowDatabase()
        if fm.fileExists(atPath: url.path) {
            let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { throw FlowIssue(message: "No se puede leer el estado de flujos.") }
            var stat = Darwin.stat()
            guard fstat(fd, &stat) == 0, (stat.st_mode & S_IFMT) == S_IFREG, stat.st_size <= 1_048_576, stat.st_uid == getuid() else { close(fd); throw FlowIssue(message: "Estado de flujos inválido.") }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            let bytes = try handle.read(upToCount: 1_048_577) ?? Data()
            guard bytes.count <= 1_048_576 else { throw FlowIssue(message: "Estado de flujos demasiado grande.") }
            db = try JSONDecoder().decode(FlowDatabase.self, from: bytes)
            try db.validate()
        }
        let before = db
        let result = try action(&db)
        try db.validate()
        if db != before || !fm.fileExists(atPath: url.path) {
            let data = try JSONEncoder().encode(db)
            guard data.count <= 1_048_576 else { throw FlowIssue(message: "El estado de flujos ha superado el límite local.") }
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return result
    }
    func snapshot() throws -> FlowDatabase { try transaction { $0 } }
}
