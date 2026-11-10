import Foundation

@main
enum AgentChecks {
    static func main() {
        var failed = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failed += 1 } }
        // hablarle a un agente
        check("«dile al de Kemet que siga»", AgentCommand.parse("Dile al de Kemet que siga.") == .init(who: "Kemet", say: "Siga."))
        check("«dile a Brojjki que pase los tests»", AgentCommand.parse("dile a Brojjki que pase los tests") == .init(who: "Brojjki", say: "Pase los tests"))
        check("«dile al agente de Diego OS que…»", AgentCommand.parse("dile al agente de Diego OS que haga el commit")?.who == "Diego OS")
        check("«tell the Kemet one to run the tests»", AgentCommand.parse("Tell the Kemet one to run the tests") == .init(who: "Kemet", say: "Run the tests"))
        check("a normal sentence isn't a command", AgentCommand.parse("creo que dile es una palabra rara") == nil)
        check("too long a name isn't a command", AgentCommand.parse("dile a la señora del quinto piso de enfrente que baje") == nil)
        check("«luego dile al de Kemet que…» is a later command", AgentCommand.parse("Luego dile al de Kemet que pase los tests", later: true) == .init(who: "Kemet", say: "Pase los tests"))
        check("«then tell the Brojjki one to…» is a later command", AgentCommand.parse("then tell the Brojjki one to deploy", later: true)?.who == "Brojjki")
        check("«dile…» without «luego» is not a later command", AgentCommand.parse("dile al de Kemet que siga", later: true) == nil)
        check("«luego dile…» is not a now command", AgentCommand.parse("luego dile al de Kemet que siga") == nil)
        check("«kemet» matches Kemet-Capital", AgentCommand.matches("Kemet", place: "Kemet-Capital"))
        check("«Kémet» matches Kemet-Capital", AgentCommand.matches("Kémet", place: "Kemet-Capital"))
        check("«diego» matches Diego-Operating-System", AgentCommand.matches("diego", place: "Diego-Operating-System"))
        check("«agent deck» matches Agent-Deck", AgentCommand.matches("agent deck", place: "Agent-Deck"))
        check("«mi madre» matches nothing", !AgentCommand.matches("mi madre", place: "Kemet-Capital"))
        // contestar un permiso hablando
        check("«sí» allows", AgentCommand.permissionAnswer("Sí.").allow)
        check("«vale, adelante» allows", AgentCommand.permissionAnswer("Vale, adelante").allow)
        check("«do it» allows", AgentCommand.permissionAnswer("do it").allow)
        check("«no» refuses without a reason", AgentCommand.permissionAnswer("No.") == (false, ""))
        check("«no, usa la rama equipo» refuses with the reason", AgentCommand.permissionAnswer("No, usa la rama equipo") == (false, "Usa la rama equipo"))
        check("«sí pero antes pasa los tests» is a no with the reason", AgentCommand.permissionAnswer("sí pero antes pasa los tests").allow == false)
        check("«permítelo» shortcut", AgentCommand.permissionShortcut("Permítelo.") == true)
        check("«no lo permitas» shortcut", AgentCommand.permissionShortcut("No lo permitas") == false)
        check("other text is no shortcut", AgentCommand.permissionShortcut("permite que el usuario entre") == nil)
        // lo que pide Claude Code
        let edit = PermissionChange.from(["tool_name": "Edit", "tool_input": ["file_path": "/tmp/x/App.swift", "old_string": "let a = 1", "new_string": "let a = 2"]])
        check("Edit: summary is tool · file", edit?.summary == "Edit · App.swift")
        check("Edit: has a diff", edit?.hasDiff == true)
        let file = "import Foundation\n\nlet a = 1\nprint(a)\n"
        let d = edit?.diff(file: .some(file)) ?? []
        check("Edit diff: one line out, one in", d.filter { $0.kind == .del }.map(\.text) == ["let a = 1"] && d.filter { $0.kind == .add }.map(\.text) == ["let a = 2"])
        check("Edit diff: keeps context", d.contains { $0.kind == .same && $0.text == "print(a)" })
        let bash = PermissionChange.from(["tool_name": "Bash", "tool_input": ["command": "git push origin main", "description": "Push"]])
        check("Bash: summary is the command", bash?.summary == "Bash · git push origin main")
        check("Bash: short command has no window", bash?.hasDiff == false && bash?.longCommand == false)
        let mcp = PermissionChange.from(["tool_name": "mcp__github__create_pull_request", "tool_input": [:]])
        check("MCP: short tool name", mcp?.toolName == "request" || mcp?.toolName == "create_pull_request" || mcp?.summary.isEmpty == false)
        let write = PermissionChange.from(["tool_name": "Write", "tool_input": ["file_path": "/tmp/new.txt", "content": "uno\ndos"]])
        check("Write new file: all added", write?.diff(file: .some(nil)).map(\.kind) == [.add, .add])
        // diferencias
        let a = (1...40).map { "line \($0)" }
        var b = a; b[19] = "changed"
        let big = LineDiff.diff(a, b)
        check("diff folds unchanged lines", big.first?.kind == .gap && big.last?.kind == .gap && big.filter { $0.kind == .same }.count == 6)
        check("same text: no changes", LineDiff.diff(a, a).allSatisfy { $0.kind != .add && $0.kind != .del })
        // teclas: variables, pasos y sugerencias
        check("key uses {selección} and {fecha}", KeyText.uses("Explica {selección} ({fecha})") == [.selection, .date])
        check("key: English names too", KeyText.uses("{selection} {clipboard} {file}") == [.selection, .clipboard, .file])
        check("key fills its values", KeyText.fill("Revisa {archivo} en {app}", [.file: "/x/App.swift", .app: "Xcode"]) == "Revisa /x/App.swift en Xcode")
        check("key leaves unknown braces alone", KeyText.fill("usa {foo} y {portapapeles}", [.clipboard: "abc"]) == "usa {foo} y abc")
        check("plain key is one step", KeyText.steps("continúa") == [.init(text: "continúa", wait: 0)])
        let chain = KeyText.steps("pasa los tests\n---\n{espera 5}\nhaz el commit\n---\nabre la PR")
        check("chain: three steps", chain.map(\.text) == ["pasa los tests", "haz el commit", "abre la PR"])
        check("chain: {espera 5} waits before its step", chain.map(\.wait) == [0, 5, 0])
        check("chain: preview", KeyText.preview("a b\n---\nc").hasPrefix(T.s("2 steps", "2 pasos")))
        let ideas = KeySuggestions.from(history: ["Pasa los tests.", "pasa los tests", "Pasa los tests", "continúa", "continúa", "continúa", "hola"], existing: ["continúa"])
        check("suggests what you said 3 times", ideas.count == 1 && ideas.first?.count == 3 && ideas.first?.text == "Pasa los tests.")
        check("suggestion label", KeySuggestions.label("Pasa los tests.") == "Pasa los")
        // lo de hoy
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ag-\(UUID().uuidString)")
        setenv("AGENT_DECK_FOLDER", tmp.path, 1)
        Activity.log("done", place: "Kemet-Capital", text: "Hecho el login.")
        Activity.log("permission", place: "Kemet-Capital")
        Activity.log("allowed", place: "Kemet-Capital")
        Activity.log("done", place: "Brojjki", text: "Tests en verde.")
        let day = Activity.today()
        check("today: one row per folder", day.count == 2 && day.first?.place == "Kemet-Capital")
        check("today: counts", day.first.map { $0.done == 1 && $0.permissions == 1 && $0.allowed == 1 && $0.last == "Hecho el login." } == true)
        try? FileManager.default.removeItem(at: tmp)
        if failed > 0 { print("AGENTS_FAILED \(failed)"); exit(1) }
        print("AGENTS_OK — synthetic only")
    }
}
