import Foundation

/// Diagnóstico (0.18): qué se marca como roto, en qué orden, los fallos de voice.log, archivos viejos y los informes de fallo.
@main
struct DoctorChecks {
    static var failures = 0
    static func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FALLA: \(what)") } }

    static func main() {
        let now = Date()
        // todo bien: ningún problema
        var i = Doctor.Input(); i.version = "0.18.0"; i.now = now
        check(Doctor.problems(Doctor.checks(i)).isEmpty, "todo bien no da problemas")
        check(Doctor.checks(i).allSatisfy { $0.level < .warn }, "todo bien: solo ok o info")

        // lo peor primero: sin Accesibilidad (fallo) va antes que una versión nueva (aviso)
        var bad = i; bad.accessibility = false; bad.update = "0.19.0"; bad.alertsPaused = true
        let p = Doctor.problems(Doctor.checks(bad))
        check(p.first?.id == "ax", "Accesibilidad primero")
        check(p.first?.actions.first?.fix == .accessibility, "Accesibilidad abre sus ajustes")
        check(p.map(\.id) == ["ax", "claude", "update"], "orden: fallos y luego avisos, en el orden de la lista: \(p.map(\.id))")
        check(p.first { $0.id == "claude" }?.actions.first?.fix == .resumeAlerts, "avisos en pausa → reanudar")

        // micrófono
        var m = i; m.mic = .denied
        check(Doctor.checks(m).first { $0.id == "mic" }?.level == .fail, "micro bloqueado es un fallo")
        m.mic = .notAsked
        check(Doctor.checks(m).first { $0.id == "mic" }?.actions.first?.fix == .microphoneAsk, "micro sin preguntar → permitir")
        m.mic = .granted; m.micDevice = false
        check(Doctor.checks(m).first { $0.id == "mic" }?.level == .warn, "sin micrófono conectado: aviso")

        // voz: sin clave y sin Pro es un fallo; con la de Apple no hace falta clave
        var v = i; v.keyConfigured = false
        check(Doctor.checks(v).first { $0.id == "voice" }?.level == .fail, "sin clave: fallo")
        v.proVoice = true
        check(Doctor.checks(v).first { $0.id == "voice" }?.level == .ok, "voz de Pro sin clave: bien")
        v.proVoice = false; v.appleEngine = true
        check(Doctor.checks(v).first { $0.id == "voice" }?.level == .ok, "motor de Apple sin clave: bien")
        v.speech = .denied
        check(Doctor.checks(v).first { $0.id == "voice" }?.actions.first?.fix == .speech, "Apple bloqueado → abrir ajustes")

        // Fn
        var f = i; f.fnReady = false
        check(Doctor.checks(f).first { $0.id == "fn" }?.level == .fail, "Fn sin tap: fallo")
        f.fnEnabled = false
        check(Doctor.checks(f).first { $0.id == "fn" }?.level == .info, "Fn apagado a propósito: solo info")
        f = i; f.lastFn = now.addingTimeInterval(-180)
        check(Doctor.checks(f).first { $0.id == "fn" }?.detail.contains("3 min") == true, "último uso de Fn")

        // Claude Code: copia vieja manda sobre todo lo demás; sin Claude Code, nada que arreglar
        var c = i; c.hooksOld = true; c.hooksInstalled = false; c.alertsPaused = true
        let cc = Doctor.checks(c).first { $0.id == "claude" }
        check(cc?.level == .fail && cc?.actions.first?.fix == .connectClaude, "ganchos de otra copia → arreglar")
        c = i; c.claudePresent = false; c.hooksInstalled = false
        check(Doctor.checks(c).first { $0.id == "claude" }?.level == .info, "sin Claude Code: info")
        c = i; c.helperOK = false
        check(Doctor.checks(c).first { $0.id == "claude" }?.level == .fail, "sin ayudante: fallo")
        c = i; c.urlHandler = "~/Downloads/Agent Bar.app"
        check(Doctor.checks(c).first { $0.id == "url" }?.actions.first?.fix == .registerHere, "otra copia con agentdeck:// → usar esta")

        // voice.log: solo cuentan los fallos de las últimas 24 h
        let iso = ISO8601DateFormatter()
        let log = """
        \(iso.string(from: now.addingTimeInterval(-90_000))) openAI gpt-transcribe/gpt-5.5 fallo: muy viejo
        \(iso.string(from: now.addingTimeInterval(-600))) openAI gpt-transcribe/gpt-5.5 Fn: empieza (mantener)
        \(iso.string(from: now.addingTimeInterval(-500))) openAI gpt-transcribe/gpt-5.5 fallo: OpenAI no responde · 503
        \(iso.string(from: now.addingTimeInterval(-400))) openAI gpt-transcribe/gpt-5.5 envío: no hay campo de texto
        \(iso.string(from: now.addingTimeInterval(-300))) openAI gpt-transcribe/gpt-5.5 listo en 2.1 s
        basura sin fecha
        """
        let fl = Doctor.failures(log: log)
        check(fl.count == 3, "tres fallos en el log: \(fl.count)")
        var l = i; l.voiceFailures = fl
        let lc = Doctor.checks(l).first { $0.id == "voicelog" }
        check(lc?.level == .warn && lc?.title.contains("2") == true, "dos en 24 h: \(lc?.title ?? "")")
        check(lc?.detail.contains("no hay campo") == true, "el motivo del último")

        // archivos viejos de los ganchos
        let st = Doctor.stale([("a.json.waiting", now.addingTimeInterval(-7200)), ("b.json", now.addingTimeInterval(-60))], now: now)
        check(st == ["a.json.waiting"], "solo lo de más de una hora: \(st)")

        // informe .ips de macOS
        let ips = """
        {"app_name":"AgentDesk","timestamp":"2026-11-10 14:02:11.00 +0100","app_version":"0.17.0","bug_type":"309","os_version":"macOS 15.3 (24D60)"}
        {"procName":"AgentDesk","exception":{"type":"EXC_BREAKPOINT","signal":"SIGTRAP"},"faultingThread":1,"usedImages":[{"name":"AgentDesk","path":"/Users/diego/Applications/Agent Bar.app"},{"name":"libswiftCore.dylib"}],"threads":[{"frames":[]},{"triggered":true,"frames":[{"imageIndex":1,"symbol":"_assertionFailure"},{"imageIndex":0,"symbol":"DeskStore.raiseAlert"},{"imageIndex":0,"imageOffset":4096}]}]}
        """
        let crash = Doctor.crash(ips: ips, file: "AgentDesk-2026-11-10-140211.ips")
        check(crash?.version == "0.17.0", "versión del fallo")
        check(crash?.kind == "EXC_BREAKPOINT · SIGTRAP", "tipo del fallo: \(crash?.kind ?? "")")
        check(crash?.frames.count == 3 && crash?.frames[1] == "AgentDesk  DeskStore.raiseAlert", "funciones del hilo que falló: \(crash?.frames ?? [])")
        check(crash?.frames[2] == "AgentDesk  0x1000", "sin símbolo, el desplazamiento")
        check(crash.map { Calendar.current.component(.minute, from: $0.date) } == 2, "fecha del fallo")
        check(Doctor.crash(ips: "nada", file: "x") == nil, "un archivo que no es un informe")
        let text = crash.map(Doctor.crashText) ?? ""
        check(!text.contains("/Users/"), "el texto del fallo no lleva rutas personales")
        let mail = crash.flatMap(Doctor.crashMail)?.absoluteString ?? ""
        check(mail.hasPrefix("mailto:hello@workwithprompted.com?subject="), "borrador de correo: \(mail.prefix(60))")
        var cr = i; cr.crash = crash
        let crc = Doctor.checks(cr).first { $0.id == "crash" }
        check(crc?.actions.map(\.fix) == [.sendCrash, .dismissCrash], "fallo → enviar o ignorar")

        // el informe para soporte no lleva la carpeta personal ni claves
        var r = bad; r.voiceFailures = [Doctor.Failure(date: now, reason: "clave sk-abcdefghijklmnop en /Users/diego/x")]
        let rep = Doctor.report(Doctor.checks(r), r, os: "macOS 15.3")
        check(rep.contains("✗") && rep.contains("Agent Bar 0.18.0"), "informe con estado y versión")
        check(!rep.contains("/Users/diego") && !rep.contains("sk-abcdefghijklmnop"), "informe limpio: \(rep)")

        if failures > 0 { print("DOCTOR_FAIL \(failures)"); exit(1) }
        print("DOCTOR_OK")
    }
}
