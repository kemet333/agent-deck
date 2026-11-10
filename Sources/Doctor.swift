import Foundation

/// Diagnóstico (0.18, «que no falle»): mira todo lo que hace falta para que Agent Bar funcione y, para cada cosa que
/// falla, dice qué pasa en una línea y da el botón que lo arregla. Aquí solo la lógica (sin AppKit), para probarla;
/// lo que se lee del Mac está en DoctorLive.swift. Nada sale del Mac: el informe se copia y el de un fallo se abre como
/// borrador de correo que el usuario revisa y envía, o no.
enum Doctor {
    enum Level: Int, Comparable { case ok, info, warn, fail; static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue } }
    enum Fix: String, Equatable {
        case accessibility, microphone, microphoneAsk, speech, connectClaude, resumeAlerts, update, moveToApplications
        case registerHere, testKey, voiceSettings, sendCrash, dismissCrash, reinstall
    }
    struct Action: Equatable { let fix: Fix; let title: String }
    struct Check: Identifiable, Equatable {
        let id: String; let title: String; var detail: String = ""; let level: Level; var actions: [Action] = []
    }
    enum Perm: Equatable { case granted, notAsked, denied }

    struct Input: Equatable {
        var version = "0"
        var accessibility = true
        var mic: Perm = .granted
        var micDevice = true
        var appleEngine = false
        var speech: Perm = .granted
        var keyConfigured = true
        var proVoice = false
        var fnEnabled = true
        var fnReady = true
        var lastFn: Date?
        var voiceFailures: [Failure] = []
        var claudePresent = true
        var hooksInstalled = true
        var hooksOld = false
        var permissionsInstalled = true
        var alertsPaused = false
        var permissionsPaused = false
        var helperOK = true
        var urlHandler: String?          // la app que abre agentdeck://, si no es esta
        var inApplications = true
        var update: String?              // versión nueva disponible
        var dataWritable = true
        var crash: Crash?
        var now = Date()
    }

    static func checks(_ i: Input) -> [Check] {
        var out: [Check] = []
        // escribir por ti
        out.append(i.accessibility
            ? Check(id: "ax", title: T.s("Accessibility is on", "Accesibilidad concedida"), detail: T.s("Agent Bar can type and send for you.", "Agent Bar puede escribir y enviar por ti."), level: .ok)
            : Check(id: "ax", title: T.s("Accessibility is off", "Falta el permiso de Accesibilidad"), detail: T.s("Without it Agent Bar can't type, send or hear Fn. Turn on Agent Bar in the list.", "Sin él Agent Bar no puede escribir, enviar ni oír la tecla Fn. Activa Agent Bar en la lista."), level: .fail, actions: [Action(fix: .accessibility, title: T.s("Open settings", "Abrir ajustes"))]))
        // micrófono
        switch i.mic {
        case .denied:
            out.append(Check(id: "mic", title: T.s("The microphone is blocked", "El micrófono está bloqueado"), detail: T.s("Dictation can't hear you. Turn on Agent Bar in Privacy → Microphone.", "El dictado no te oye. Activa Agent Bar en Privacidad → Micrófono."), level: .fail, actions: [Action(fix: .microphone, title: T.s("Open settings", "Abrir ajustes"))]))
        case .notAsked:
            out.append(Check(id: "mic", title: T.s("The microphone hasn't been allowed yet", "Aún no has permitido el micrófono"), detail: T.s("macOS asks once; dictation needs it.", "macOS lo pregunta una vez; el dictado lo necesita."), level: .warn, actions: [Action(fix: .microphoneAsk, title: T.s("Allow", "Permitir"))]))
        case .granted:
            out.append(i.micDevice
                ? Check(id: "mic", title: T.s("Microphone ready", "Micrófono listo"), level: .ok)
                : Check(id: "mic", title: T.s("No microphone found", "No hay ningún micrófono"), detail: T.s("Connect one, or open the lid of the Mac.", "Conecta uno o abre la tapa del Mac."), level: .warn))
        }
        // motor de voz
        if i.appleEngine {
            switch i.speech {
            case .denied: out.append(Check(id: "voice", title: T.s("Apple dictation is blocked", "El dictado de Apple está bloqueado"), detail: T.s("Turn on Agent Bar in Privacy → Speech Recognition, or switch to OpenAI in Voice.", "Activa Agent Bar en Privacidad → Reconocimiento de voz, o cambia a OpenAI en Voz."), level: .fail, actions: [Action(fix: .speech, title: T.s("Open settings", "Abrir ajustes"))]))
            case .notAsked: out.append(Check(id: "voice", title: T.s("Apple dictation needs permission", "El dictado de Apple necesita permiso"), detail: T.s("macOS asks the first time you dictate.", "macOS lo pregunta la primera vez que dictas."), level: .info))
            case .granted: out.append(Check(id: "voice", title: T.s("Voice: Apple, on this Mac", "Voz: la de Apple, en este Mac"), level: .ok))
            }
        } else if i.keyConfigured {
            out.append(Check(id: "voice", title: T.s("Voice: OpenAI with your key", "Voz: OpenAI con tu clave"), detail: T.s("Test it to see that it works and has credit.", "Pruébala para ver que funciona y tiene saldo."), level: .ok, actions: [Action(fix: .testKey, title: T.s("Test key", "Probar clave"))]))
        } else if i.proVoice {
            out.append(Check(id: "voice", title: T.s("Voice: included with Pro", "Voz: la incluida en Pro"), level: .ok))
        } else {
            out.append(Check(id: "voice", title: T.s("Your OpenAI key is missing", "Falta tu clave de OpenAI"), detail: T.s("Voice uses your own key. Add it, or switch to Apple's voice in Voice.", "La voz usa tu propia clave. Añádela o cambia a la voz de Apple en Voz."), level: .fail, actions: [Action(fix: .voiceSettings, title: T.s("Add key", "Añadir clave"))]))
        }
        // Fn
        if !i.fnEnabled {
            out.append(Check(id: "fn", title: T.s("Fn is off", "Fn está apagado"), detail: T.s("Turn it on in Voice. The Dictate button still works.", "Se enciende en Voz. El botón Dictar sigue funcionando."), level: .info, actions: [Action(fix: .voiceSettings, title: T.s("Voice", "Voz"))]))
        } else if !i.fnReady {
            out.append(Check(id: "fn", title: T.s("Fn isn't listening", "Fn no escucha"), detail: i.accessibility ? T.s("Restart Agent Bar. If it keeps happening, turn Accessibility off and on again for Agent Bar.", "Reinicia Agent Bar. Si sigue pasando, quita y vuelve a dar Accesibilidad a Agent Bar.") : T.s("It needs Accessibility. Agent Bar retries every 3 seconds.", "Necesita Accesibilidad. Agent Bar lo reintenta cada 3 segundos."), level: .fail, actions: [Action(fix: .accessibility, title: T.s("Open settings", "Abrir ajustes"))]))
        } else {
            out.append(Check(id: "fn", title: T.s("Fn is listening", "Fn escucha"), detail: i.lastFn.map { T.s("Last used ", "Último uso: ") + ago($0, now: i.now) } ?? T.s("Hold Fn and speak.", "Mantén Fn y habla."), level: .ok))
        }
        // fallos de voz recientes
        let day = i.voiceFailures.filter { i.now.timeIntervalSince($0.date) < 86_400 }
        if let last = day.last {
            out.append(Check(id: "voicelog", title: day.count == 1 ? T.s("1 voice failure in the last 24 h", "1 fallo de voz en las últimas 24 h") : T.s("\(day.count) voice failures in the last 24 h", "\(day.count) fallos de voz en las últimas 24 h"), detail: ago(last.date, now: i.now).capitalizedFirst + ": " + String(last.reason.prefix(140)), level: .warn))
        } else {
            out.append(Check(id: "voicelog", title: T.s("No voice failures in 24 h", "Sin fallos de voz en 24 h"), level: .ok))
        }
        // Claude Code
        if !i.claudePresent && !i.hooksInstalled {
            out.append(Check(id: "claude", title: T.s("Claude Code isn't on this Mac", "Claude Code no está en este Mac"), detail: T.s("Alerts and Autopilot work with Claude Code.", "Los avisos y Autopilot funcionan con Claude Code."), level: .info))
        } else if i.hooksOld {
            out.append(Check(id: "claude", title: T.s("Alerts point to another copy of Agent Bar", "Los avisos apuntan a otra copia de Agent Bar"), detail: T.s("Claude Code still calls an old or moved copy, so nothing lights up. Fix it and restart Claude Code.", "Claude Code sigue llamando a una copia vieja o movida y no se enciende nada. Arréglalo y reinicia Claude Code."), level: .fail, actions: [Action(fix: .connectClaude, title: T.s("Fix", "Arreglar"))]))
        } else if !i.hooksInstalled {
            out.append(Check(id: "claude", title: T.s("Claude Code alerts are off", "Avisos de Claude Code sin activar"), detail: T.s("Know when it finishes, answer its permissions and let Autopilot keep going.", "Entérate cuando termine, contesta sus permisos y deja que Autopilot siga solo."), level: .info, actions: [Action(fix: .connectClaude, title: T.s("Turn on…", "Activar…"))]))
        } else if !i.helperOK {
            out.append(Check(id: "claude", title: T.s("The alerts helper is missing", "Falta el ayudante de los avisos"), detail: T.s("This copy of Agent Bar is incomplete. Download it again.", "Esta copia de Agent Bar está incompleta. Vuelve a descargarla."), level: .fail, actions: [Action(fix: .reinstall, title: T.s("Download", "Descargar"))]))
        } else if i.alertsPaused {
            out.append(Check(id: "claude", title: T.s("Claude Code alerts are paused", "Los avisos de Claude Code están en pausa"), detail: T.s("Nothing lights up or waits when Claude Code finishes, and Autopilot doesn't run.", "No se enciende ni espera nada cuando Claude Code termina, y Autopilot no funciona."), level: .warn, actions: [Action(fix: .resumeAlerts, title: T.s("Resume", "Reanudar"))]))
        } else if !i.permissionsInstalled {
            out.append(Check(id: "claude", title: T.s("Claude Code alerts are on", "Avisos de Claude Code activos"), detail: T.s("Permissions from the bar aren't added yet.", "Aún no has añadido los permisos desde la barra."), level: .ok, actions: [Action(fix: .connectClaude, title: T.s("Add…", "Añadir…"))]))
        } else {
            out.append(Check(id: "claude", title: T.s("Claude Code alerts are on", "Avisos de Claude Code activos"), detail: i.permissionsPaused ? T.s("Permissions from the bar are off.", "Los permisos desde la barra están apagados.") : T.s("With permissions from the bar.", "Con los permisos desde la barra."), level: .ok))
        }
        if let other = i.urlHandler {
            out.append(Check(id: "url", title: T.s("Another copy of Agent Bar gets the alerts", "Otra copia de Agent Bar recibe los avisos"), detail: other, level: .fail, actions: [Action(fix: .registerHere, title: T.s("Use this one", "Usar esta"))]))
        }
        // dónde vive y versión
        if !i.inApplications {
            out.append(Check(id: "where", title: T.s("Agent Bar isn't in Applications", "Agent Bar no está en Aplicaciones"), detail: T.s("macOS forgets its permissions elsewhere, and updates need it there.", "Fuera de ahí macOS olvida sus permisos y no se puede actualizar sola."), level: .warn, actions: [Action(fix: .moveToApplications, title: T.s("Move", "Mover"))]))
        }
        if let v = i.update {
            out.append(Check(id: "update", title: T.s("Version \(v) is available", "Hay una versión nueva: \(v)"), detail: T.s("Keeps your keys, key and settings.", "Conserva tus teclas, tu clave y tus ajustes."), level: .warn, actions: [Action(fix: .update, title: T.s("Update", "Actualizar"))]))
        } else {
            out.append(Check(id: "update", title: T.s("Version \(i.version)", "Versión \(i.version)"), detail: T.s("Checked once a day.", "Se comprueba una vez al día."), level: .ok))
        }
        if !i.dataWritable {
            out.append(Check(id: "data", title: T.s("Agent Bar can't save its settings", "Agent Bar no puede guardar sus ajustes"), detail: "~/Library/Application Support/Agent Deck", level: .fail))
        }
        if let c = i.crash {
            out.append(Check(id: "crash", title: T.s("Agent Bar quit unexpectedly ", "Agent Bar se cerró de golpe ") + ago(c.date, now: i.now), detail: T.s("Version \(c.version) · \(c.kind). Sending the report helps fix it; you see it before it goes.", "Versión \(c.version) · \(c.kind). Enviar el informe ayuda a arreglarlo; lo ves antes de que salga."), level: .warn, actions: [Action(fix: .sendCrash, title: T.s("Send report…", "Enviar informe…")), Action(fix: .dismissCrash, title: T.s("Ignore", "Ignorar"))]))
        }
        return out
    }

    /// Lo que hay que arreglar, lo peor primero; el orden de la lista se mantiene entre los del mismo nivel.
    static func problems(_ c: [Check]) -> [Check] {
        c.enumerated().filter { $0.element.level >= .warn }.sorted { ($0.element.level, -$0.offset) > ($1.element.level, -$1.offset) }.map(\.element)
    }

    // MARK: voice.log

    struct Failure: Equatable { let date: Date; let reason: String }
    /// Los fallos de voice.log (solo motivos: lo dictado nunca se escribe ahí). Líneas «<ISO> <motor> <modelos> fallo: …»,
    /// y los envíos que no llegaron («envío: …», «envío rápido: …»).
    static func failures(log: String) -> [Failure] {
        let iso = ISO8601DateFormatter()
        var out: [Failure] = []
        for line in log.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, let d = iso.date(from: String(parts[0])) else { continue }
            let rest = String(parts[3])
            for p in ["fallo: ", "envío: ", "envío rápido: "] where rest.hasPrefix(p) {
                out.append(Failure(date: d, reason: String(rest.dropFirst(p.count)))); break
            }
        }
        return out
    }

    // MARK: archivos viejos de los ganchos

    /// Lo que dejaron ganchos que ya no esperan (el más largo espera 11 min): todo lo de más de una hora.
    static func stale(_ files: [(name: String, modified: Date)], now: Date = Date()) -> [String] {
        files.filter { now.timeIntervalSince($0.modified) > 3600 }.map(\.name)
    }

    // MARK: informes de fallo

    struct Crash: Equatable {
        let date: Date; let version: String; let os: String; let kind: String; let frames: [String]; let file: String
    }
    /// Lee un informe .ips de macOS (una línea de cabecera JSON y el cuerpo JSON). Solo se queda con lo que sirve para
    /// arreglarlo: versión, sistema, tipo de fallo y las funciones del hilo que falló, sin rutas de tu carpeta personal.
    static func crash(ips: String, file: String) -> Crash? {
        guard let nl = ips.firstIndex(of: "\n") else { return nil }
        let head = (try? JSONSerialization.jsonObject(with: Data(ips[..<nl].utf8))) as? [String: Any] ?? [:]
        let body = (try? JSONSerialization.jsonObject(with: Data(ips[ips.index(after: nl)...].utf8))) as? [String: Any] ?? [:]
        guard !head.isEmpty || !body.isEmpty else { return nil }
        let ts = (head["timestamp"] as? String) ?? (body["captureTime"] as? String) ?? ""
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        var date: Date?
        for fmt in ["yyyy-MM-dd HH:mm:ss.SS Z", "yyyy-MM-dd HH:mm:ss.SSSS Z", "yyyy-MM-dd HH:mm:ss Z"] where date == nil { f.dateFormat = fmt; date = f.date(from: ts) }
        let headVersion = (head["app_version"] as? String) ?? ""
        let version = !headVersion.isEmpty ? headVersion : ((body["bundleInfo"] as? [String: Any])?["CFBundleShortVersionString"] as? String ?? "?")
        let os = (head["os_version"] as? String) ?? ((body["osVersion"] as? [String: Any])?["train"] as? String) ?? ""
        let ex = body["exception"] as? [String: Any] ?? [:]
        var kind = [ex["type"] as? String, ex["signal"] as? String].compactMap { $0 }.joined(separator: " · ")
        if let r = (body["termination"] as? [String: Any])?["indicator"] as? String, kind.isEmpty { kind = r }
        if kind.isEmpty { kind = T.s("unknown", "desconocido") }
        let images = (body["usedImages"] as? [[String: Any]] ?? []).map { ($0["name"] as? String) ?? "?" }
        let threads = body["threads"] as? [[String: Any]] ?? []
        let ft = body["faultingThread"] as? Int ?? threads.firstIndex { ($0["triggered"] as? Bool) == true } ?? 0
        var frames: [String] = []
        if ft < threads.count {
            for fr in (threads[ft]["frames"] as? [[String: Any]] ?? []).prefix(14) {
                let img = (fr["imageIndex"] as? Int).flatMap { $0 < images.count ? images[$0] : nil } ?? "?"
                let sym = (fr["symbol"] as? String) ?? "0x" + String(fr["imageOffset"] as? Int ?? 0, radix: 16)
                frames.append(img + "  " + sym)
            }
        }
        return Crash(date: date ?? Date.distantPast, version: version, os: os, kind: kind, frames: frames, file: file)
    }
    static func crashText(_ c: Crash) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        return (["Agent Bar \(c.version) · \(c.os)", f.string(from: c.date) + " · " + c.kind, ""] + c.frames).joined(separator: "\n")
    }
    /// El correo del informe: un borrador para hello@workwithprompted.com que el usuario lee y envía si quiere.
    static func crashMail(_ c: Crash) -> URL? {
        var u = URLComponents(); u.scheme = "mailto"; u.path = "hello@workwithprompted.com"
        u.queryItems = [URLQueryItem(name: "subject", value: "Agent Bar \(c.version) · " + T.s("crash report", "informe de fallo")),
                        URLQueryItem(name: "body", value: T.s("What were you doing when it closed? (optional)\n\n\n", "¿Qué hacías cuando se cerró? (opcional)\n\n\n") + crashText(c))]
        return u.url
    }

    // MARK: informe para soporte

    /// El estado entero en texto, para pegarlo en un correo o un issue. Sin lo dictado, sin claves y sin rutas personales.
    static func report(_ checks: [Check], _ i: Input, os: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        var lines = ["Agent Bar \(i.version) · \(os)", f.string(from: i.now), ""]
        for c in checks {
            let mark: String
            switch c.level { case .ok: mark = "✓"; case .info: mark = "·"; case .warn: mark = "!"; case .fail: mark = "✗" }
            lines.append("\(mark) \(c.title)" + (c.detail.isEmpty ? "" : " — \(c.detail)"))
        }
        let recent = i.voiceFailures.suffix(5)
        if !recent.isEmpty {
            lines += ["", T.s("Last voice failures (reasons only):", "Últimos fallos de voz (solo motivos):")]
            lines += recent.map { f.string(from: $0.date) + "  " + String($0.reason.prefix(200)) }
        }
        return scrub(lines.joined(separator: "\n"))
    }
    /// Quita la carpeta personal (lleva el nombre de usuario) y cualquier cosa con pinta de clave.
    static func scrub(_ s: String) -> String {
        var out = s.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        out = out.replacingOccurrences(of: "/Users/[^/\\s]+", with: "~", options: .regularExpression)
        return out.replacingOccurrences(of: "sk-[A-Za-z0-9_-]{8,}", with: "sk-…", options: .regularExpression)
    }

    /// «hace 3 min», «hace 2 h», «el 10/11 a las 14:02».
    static func ago(_ d: Date, now: Date) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return T.s("just now", "ahora mismo") }
        if s < 3600 { return T.s("\(Int(s / 60)) min ago", "hace \(Int(s / 60)) min") }
        if s < 86_400 { return T.s("\(Int(s / 3600)) h ago", "hace \(Int(s / 3600)) h") }
        let f = DateFormatter(); f.dateFormat = T.es ? "d/M 'a las' H:mm" : "MMM d 'at' H:mm"; f.locale = Locale(identifier: T.es ? "es_ES" : "en_US")
        return (T.es ? "el " : "on ") + f.string(from: d)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
