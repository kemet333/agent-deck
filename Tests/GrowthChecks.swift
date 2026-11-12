import Foundation

/// Crecer (0.19): el catálogo de la galería, el pack de equipo (leer, enlaces, mezclar con tus teclas, exportar) e invitar.
@main
struct GrowthChecks {
    static var failures = 0
    static func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FALLA: \(what)") } }

    static func main() {
        // el catálogo de la web: todos válidos, con español
        let path = CommandLine.arguments.dropFirst().first ?? "docs/packs/packs.json"
        let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
        let packs = Gallery.parse(data)
        check(packs.count == 9, "9 packs en packs.json: \(packs.count)")
        check(packs.allSatisfy { $0.es?.keys != nil && $0.pack(spanish: true).valid }, "todos con español")
        check(packs.first { $0.id == "claude-code" }?.pack(spanish: true).keys.first?.text == "haz un plan primero y espera a mi ok", "Claude Code en español")
        check(packs.first { $0.id == "trader-tradingview" }?.keys.allSatisfy { $0.apps == ["com.tradingview.tradingviewapp.desktop"] } == true, "el pack Trader solo en TradingView")
        check(Gallery.filter(packs, query: "atención").map(\.id) == ["support"], "buscar en español: \(Gallery.filter(packs, query: "atención").map(\.id))")
        check(Gallery.filter(packs, query: "TESTS codex").map(\.id) == ["codex"], "varias palabras, sin mayúsculas")
        check(Gallery.filter(packs, query: "", tool: "Cursor").count == 1, "por herramienta")
        check(Gallery.tools(packs).first == "TradingView" && Set(Gallery.tools(packs)).count == Gallery.tools(packs).count, "herramientas sin repetir")

        // un catálogo con un pack roto y un id repetido: solo entra el bueno
        let bad = #"{"version":1,"packs":[{"id":"a","name":"A","by":"x","tool":"t","about":"","keys":[{"label":"k","text":"hola","icon":"","enter":true}]},{"id":"a","name":"A2","by":"x","tool":"t","about":"","keys":[{"label":"k","text":"y","icon":"","enter":true}]},{"id":"b","name":"","by":"x","tool":"t","about":"","keys":[]}]}"#
        check(Gallery.parse(Data(bad.utf8)).map(\.name) == ["A"], "rotos y repetidos fuera")
        check(Gallery.parse(Data(#"{"version":2,"packs":[]}"#.utf8)).isEmpty, "otra versión del catálogo no se lee")
        let mail = Gallery.proposal(packs.first { $0.id == "claude-code" }!.pack(spanish: false), by: "Diego")?.absoluteString ?? ""
        check(mail.hasPrefix("mailto:hello@workwithprompted.com?subject=Agent%20Bar%20pack"), "proponer = borrador de correo: \(mail.prefix(70))")
        check(mail.contains("getagentbar.com/p/"), "el correo lleva el enlace del pack")

        // el archivo del equipo
        let json = """
        {"agentbar_team":1,"name":"  Prompted ","message":"Teclas del equipo","keys":[
          {"label":"Revisa","text":"revisa el PR {selección}","icon":"eye"},
          {"label":"Cliente","text":"contesta al cliente","apps":["com.apple.mail"],"hold":"y ponle en copia a soporte"}],
         "vocabulary":["Kemet","kemet","Brojjki","","<x>"]}
        """
        let t = Team.parse(Data(json.utf8))
        check(t?.name == "Prompted", "nombre limpio: \(t?.name ?? "nil")")
        check(t?.words == ["Kemet", "Brojjki"], "vocabulario sin repetidos ni raros: \(t?.words ?? [])")
        check(Team.parse(Data(#"{"agentbar_team":2,"name":"x","keys":[{"label":"a","text":"b"}]}"#.utf8)) == nil, "otra versión no")
        check(Team.parse(Data(#"{"agentbar_team":1,"name":"x","keys":[]}"#.utf8)) == nil, "sin teclas ni palabras no")
        let many = "{\"agentbar_team\":1,\"name\":\"x\",\"keys\":[" + Array(repeating: #"{"label":"a","text":"b"}"#, count: 25).joined(separator: ",") + "]}"
        check(Team.parse(Data(many.utf8)) == nil, "más de 24 teclas no")
        check(Team.parse(Data("no es json".utf8)) == nil, "basura no")

        // de dónde se baja
        check(Team.source("https://www.dropbox.com/s/abc/team.json?dl=0")?.absoluteString == "https://www.dropbox.com/s/abc/team.json?dl=1", "Dropbox → descarga")
        check(Team.source("https://drive.google.com/file/d/1AbC_d/view?usp=sharing")?.absoluteString == "https://drive.google.com/uc?export=download&id=1AbC_d", "Google Drive → descarga")
        check(Team.source("https://github.com/acme/team/blob/main/team.json")?.absoluteString == "https://raw.githubusercontent.com/acme/team/main/team.json", "GitHub → raw")
        check(Team.source("https://gist.github.com/ana/123abc")?.absoluteString == "https://gist.githubusercontent.com/ana/123abc/raw", "gist → raw")
        check(Team.source("http://example.com/team.json") == nil, "http no")
        check(Team.source("javascript:alert(1)") == nil, "otros esquemas no")
        check(Team.source("~/Library/Mobile Documents/team.json")?.isFileURL == true, "un archivo sí")
        check(Team.joinLink(URL(string: "https://acme.com/t.json?a=1")!) == "https://getagentbar.com/team/#https%3A%2F%2Facme.com%2Ft.json%3Fa%3D1", "enlace para unirse")
        check(Team.joinLink(URL(fileURLWithPath: "/tmp/t.json")) == nil, "un archivo local no da enlace")

        // mezclar con tus teclas: las tuyas se quedan, las del equipo detrás con atajos libres
        guard let team = t else { print("GROWTH_FAIL sin equipo"); exit(1) }
        let mine = [DeskKey(label: "Sigue", text: "sigue", hotkey: 1), DeskKey(label: "Tests", text: "pasa los tests", hotkey: 2)]
        let merged = Team.merge(mine, team)
        check(merged.count == 4 && merged.prefix(2).map(\.label) == ["Sigue", "Tests"], "tus teclas primero")
        check(merged[2].hotkey == 3 && merged[3].hotkey == 4, "atajos libres: \(merged.map { $0.hotkey ?? 0 })")
        check(merged[2].team == "Prompted" && merged[2].group == "Prompted", "marcadas como del equipo")
        check(merged[3].apps == ["com.apple.mail"] && merged[3].hold == "y ponle en copia a soporte", "solo en Mail y al mantener")
        check(merged[2].sendEnter, "envía por defecto")

        // actualizar: la que sigue conserva su atajo e id aunque cambie el texto; la quitada se va; las tuyas igual
        var moved = merged; moved[3].hotkey = 7
        var next = team
        next.keys = [TeamPack.Key(label: "Nueva", text: "algo nuevo"), TeamPack.Key(label: "Cliente", text: "contesta al cliente con calma")]
        let c = Team.changes(old: moved, new: next)
        check(c.added == 1 && c.changed == 1 && c.removed == 1, "cambios: \(c)")
        check(Team.changeNote(c, team: "Prompted") == "Prompted: 1 tecla nueva, 1 cambiada, 1 quitada" || Team.changeNote(c, team: "Prompted") == "Prompted: 1 new key, 1 changed, 1 removed", "nota: \(Team.changeNote(c, team: "Prompted") ?? "")")
        check(Team.changeNote((0, 0, 0), team: "x") == nil, "sin cambios, sin nota")
        let again = Team.merge(moved, next)
        check(again.map(\.label) == ["Sigue", "Tests", "Nueva", "Cliente"], "orden tras actualizar: \(again.map(\.label))")
        check(again[3].hotkey == 7 && again[3].id == moved[3].id, "conserva atajo e id")
        check(again[2].hotkey == 3, "la nueva coge el primer atajo libre: \(again[2].hotkey ?? 0)")
        check(Team.strip(again) == mine, "salir deja solo las tuyas")

        // tu atajo manda: si tienes ⌃⌥7 tuya, la del equipo coge otro
        var mine7 = mine; mine7.append(DeskKey(label: "Mía", text: "mía", hotkey: 7))
        let clash = Team.merge(mine7 + moved.suffix(2), next)
        check(clash.first { $0.label == "Cliente" }?.hotkey != 7, "no pisa tus atajos")

        // exportar: tus teclas (no las de otro equipo) y tu vocabulario; se vuelve a leer igual
        let out = Team.export(name: "Acme", keys: merged, vocabulary: ["Acme", "Kemet"], message: "hola")
        let back = Team.parse(out)
        check(back?.name == "Acme" && back?.keys.map(\.label) == ["Sigue", "Tests"], "exporta solo tus teclas: \(back?.keys.map(\.label) ?? [])")
        check(back?.words == ["Acme", "Kemet"] && back?.message == "hola" && back?.updated?.count == 10, "vocabulario, mensaje y fecha")

        // invitar
        check(Invite.clean("https://getagentbar.com/?aff=ZylBs") == "ZylBs", "código desde el enlace")
        check(Invite.clean("  ab_12-x  ") == "ab_12-x", "código limpio")
        check(Invite.clean("abc\"><script>") == "abc", "nada raro en el código")
        check(Invite.link(code: "ZylBs") == "https://getagentbar.com/?aff=ZylBs", "enlace de invitación")
        check(Invite.link(code: "") == "https://getagentbar.com/", "sin código, la web")
        let p = packs.first { $0.id == "claude-code" }!.pack(spanish: false)
        check(Invite.link(code: "ZylBs", pack: p) == "https://getagentbar.com/p/?aff=ZylBs#" + p.encoded, "pack con código")
        check(Invite.link(code: "", pack: p) == p.shareURL, "pack sin código = el enlace de siempre")
        check(Invite.message(code: "Z", pack: nil).hasSuffix("https://getagentbar.com/?aff=Z"), "el mensaje termina en el enlace")

        // las teclas guardadas antes de la 0.19 se leen sin equipo
        let old = #"[{"label":"a","text":"b"}]"#
        check((try? JSONDecoder().decode([DeskKey].self, from: Data(old.utf8)))?.first?.team == "", "teclas viejas = tuyas")

        if failures > 0 { print("GROWTH_FAIL \(failures)"); exit(1) }
        print("GROWTH_OK")
    }
}
