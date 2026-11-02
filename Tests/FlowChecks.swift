import Foundation

@main
@MainActor
enum FlowChecks {
    static var checks = 0
    static let now = 1_800_000_000.0
    static func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
        do { guard try condition() else { fatalError("FAIL \(name)") } }
        catch { fatalError("FAIL \(name): \(error)") }
        checks += 1; print("PASS \(name)")
    }
    static func event(_ kind: String, session: String = "chat-a", cwd: String = "/tmp/project", turn: String = "turn-1", answer: String = "Finished", continued: Bool = false, prompt: String? = nil, tool: String? = nil, status: String? = nil, agent: String? = nil) throws -> FlowHookEvent {
        var value: [String: Any] = ["session_id":session,"cwd":cwd,"hook_event_name":kind,"turn_id":turn,"last_assistant_message":answer,"stop_hook_active":continued]
        value["prompt"] = prompt; value["tool_name"] = tool; value["status"] = status; value["agent_id"] = agent
        return try JSONDecoder().decode(FlowHookEvent.self, from: JSONSerialization.data(withJSONObject: value))
    }
    static func armed(_ count: Int = 3, idle: Bool = false) throws -> FlowDatabase {
        var db = FlowDatabase(); var def = MessageFlow(); def.repetitions = count
        db.sessions = [FlowSession(id:"chat-a",cwd:"/tmp/project",lastSeen:now,state:idle ? "idle":"running",turnID:"turn-1")]
        try db.arm(def,sessionID:"chat-a",now:now); return db
    }
    static func send(_ kind: String, _ db: inout FlowDatabase, turn: String = "turn-1", answer: String = "Finished", continued: Bool = false, prompt: String? = nil, tool: String? = nil, status: String? = nil) throws -> [String:String] {
        FlowEngine.handle(try event(kind,turn:turn,answer:answer,continued:continued,prompt:prompt,tool:tool,status:status),database:&db,now:now+1)
    }
    static func rejects(_ action: () throws -> Void) -> Bool { do { try action(); return false } catch { return true } }
    static func main() throws {
        var def = MessageFlow(); def.repetitions = 5
        check(try def.messages() == Array(repeating:"siguiente",count:5),"repeat expands to exact finite count")
        def.mode = "sequence"; def.steps = ["  Primero\ncon detalle.  ","Después","Final"]
        check(try def.messages() == def.steps,"sequence preserves exact wording and multiline text")
        def.mode = "repeat"; def.repetitions = 0; check(rejects{ _ = try def.messages() },"zero repeats rejected")
        def.repetitions = 51; check(rejects{ _ = try def.messages() },"unbounded repeats rejected")
        def.repetitions = 1; def.message = "  \n "; check(rejects{ _ = try def.messages() },"blank message rejected")
        def.message = String(repeating:"x",count:4097); check(rejects{ _ = try def.messages() },"oversized step rejected")
        var db = try armed(3)
        check(try send("Stop",&db)["reason"] == "siguiente" && db.run?.issued == 1,"first completion emits one message only")
        _ = try send("UserPromptSubmit",&db,turn:"turn-2",prompt:"siguiente")
        check(try send("Stop",&db,turn:"turn-2",answer:"Second finished")["reason"] == "siguiente","confirmed continuation advances after next completion")
        _ = try send("UserPromptSubmit",&db,turn:"turn-3",prompt:"siguiente")
        check(try send("Stop",&db,turn:"turn-3",answer:"Third finished")["reason"] == "siguiente" && db.run?.issued == 3,"third configured message emitted exactly once")
        _ = try send("UserPromptSubmit",&db,turn:"turn-4",prompt:"siguiente")
        check(try send("Stop",&db,turn:"turn-4",answer:"All finished").isEmpty && db.run?.state == "completed","last response finishes sequence without extra message")
        db = try armed(2)
        _ = try send("Stop",&db)
        check(try send("Stop",&db,answer:"Second result",continued:true)["reason"] == "siguiente","same-turn official stop_hook_active continuation supported")
        check(try send("Stop",&db,answer:"Third result",continued:true).isEmpty && db.run?.state == "completed","same-turn continuation remains bounded")
        db = try armed(); _ = try send("Stop",&db)
        check(try send("Stop",&db,turn:"old-turn",answer:"Late old result",continued:true).isEmpty && db.run?.issued == 1 && db.run?.state == "paused","late continuation from another turn cannot advance flow")
        db = try armed(); _ = try send("Stop",&db)
        check(try send("Stop",&db).isEmpty && db.run?.issued == 1 && db.run?.state == "paused","duplicate stop cannot consume or emit a second message")
        db = try armed(); _ = try send("Stop",&db)
        check(try send("Stop",&db,turn:"different",answer:"Unknown").isEmpty && db.run?.state == "paused","unconfirmed continuation pauses")
        db = try armed()
        check(FlowEngine.handle(try event("Stop",session:"chat-b"),database:&db,now:now+1).isEmpty && db.run?.issued == 0,"other chat cannot consume selected flow")
        check(FlowEngine.handle(try event("Stop",cwd:"/tmp/other"),database:&db,now:now+1).isEmpty && db.run?.state == "paused","changed working directory pauses selected chat")
        db = try armed()
        check(FlowEngine.handle(try event("Stop",agent:"child"),database:&db,now:now+1).isEmpty && db.run?.issued == 0,"subagent completion is ignored")
        for kind in ["PermissionRequest","Interrupt","SessionEnd","SessionStart"] {
            db = try armed(); check(try send(kind,&db).isEmpty && db.run?.state == "paused","\(kind) pauses without permission decision")
        }
        for tool in ["request_user_input","request_user_input_async","mcp__question__AskUserQuestion","functions.request_user_input_async","functions::request_user_input"] {
            db = try armed(); check(try send("PreToolUse",&db,tool:tool).isEmpty && db.run?.state == "paused","question tool \(tool) pauses")
        }
        db = try armed(); check(try send("PreToolUse",&db,tool:"Bash").isEmpty && db.run?.active == true,"ordinary tool use does not trigger a continuation")
        db = try armed(); check(try send("PostModelRequest",&db,status:"failed").isEmpty && db.run?.state == "paused","model failure pauses, no automatic retry")
        db = try armed(); check(try send("UserPromptSubmit",&db,prompt:"New direction").isEmpty && db.run?.state == "paused","manual message pauses automation instead of overriding steering")
        db = try armed(idle:true)
        check(try send("Stop",&db).isEmpty && db.run?.issued == 0,"idle arming never sends immediately")
        _ = try send("UserPromptSubmit",&db,prompt:"Initial task")
        check(try send("Stop",&db)["reason"] == "siguiente","first manually submitted task completes before flow begins")
        db = try armed()
        check(FlowEngine.handle(try event("Stop"),database:&db,now:now+16).isEmpty && db.run?.state == "paused","lost app heartbeat fails closed")
        db = try armed(); db.run?.expires = now-1
        check(FlowEngine.handle(try event("Stop"),database:&db,now:now+1).isEmpty && db.run?.issued == 0,"expired flow never emits")
        db = try armed(); check(try send("Stop",&db,answer:"").isEmpty && db.run?.state == "paused","missing completion evidence pauses")
        db = try armed(); db.run?.state = "cancelled"
        check(try send("Stop",&db).isEmpty && db.run?.issued == 0,"cancelled run cannot reactivate from hook")
        db = try armed(); db.run?.issued = -1
        check(rejects{try db.validate()},"corrupt negative index rejected before use")
        let helper = URL(fileURLWithPath:"/tmp/Agent Deck's App/Contents/Helpers/AgentDeckFlowHook")
        let existing = try JSONSerialization.data(withJSONObject:["description":"preserve","custom":17,"hooks":["Stop":[["hooks":[["type":"command","command":"existing-command","timeout":9]]]]]])
        let merged = try FlowConnector.merged(existing,helper:helper)
        let twice = try FlowConnector.merged(merged,helper:helper)
        check(merged == twice,"connector installation is idempotent")
        let object = try JSONSerialization.jsonObject(with:merged) as! [String:Any]
        check(object["description"] as? String == "preserve" && object["custom"] as? Int == 17,"connector preserves unrelated metadata")
        let restored = try JSONSerialization.jsonObject(with:FlowConnector.merged(merged,helper:helper,removing:true)) as! [String:Any]
        let hooks = restored["hooks"] as! [String:Any]
        let stops = hooks["Stop"] as! [[String:Any]]
        check(stops.count == 1 && (stops[0]["hooks"] as! [[String:Any]])[0]["command"] as? String == "existing-command","removal preserves other Stop handlers")
        check(FlowConnector.command(helper).contains("'\\''"),"helper path is shell-quoted including apostrophes")
        check(rejects{ _ = try FlowConnector.merged(Data("[]".utf8),helper:helper) },"malformed existing config is not replaced")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("agent-deck-flow-checks-"+UUID().uuidString)
        let storage = FlowStorage(folder:folder)
        defer { try? FileManager.default.removeItem(at:folder) }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let config = folder.appendingPathComponent("hooks.json")
        check(try FlowConnector.createIfAbsent(Data("original".utf8),at:config),"connector atomically creates only absent file")
        check(try !FlowConnector.createIfAbsent(Data("replacement".utf8),at:config) && String(contentsOf:config,encoding:.utf8) == "original","existing hooks file cannot be overwritten")
        try storage.transaction { $0 = try armed() }
        let controller = FlowController(storage:storage,reviewMode:true)
        check(controller.database.run?.state == "paused","native controller restart preserves progress and pauses")
        check((try storage.snapshot()).run?.state == "paused","restart pause persists across process boundary")
        let attributes = try FileManager.default.attributesOfItem(atPath:folder.appendingPathComponent("state.json").path)
        check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,"flow state is private mode0600")
        let serialized = try String(contentsOf:folder.appendingPathComponent("state.json"),encoding:.utf8)
        check(!serialized.contains("Initial task") && !serialized.contains("Second finished"),"history and unrelated prompts are not persisted")
        try Data("not-json".utf8).write(to:folder.appendingPathComponent("state.json"))
        check(rejects{ _ = try storage.snapshot() },"corrupt storage is reported without resetting")
        check(try String(contentsOf:folder.appendingPathComponent("state.json"),encoding:.utf8) == "not-json","corrupt file preserved for recovery")
        print("FLOW_CHECKS_OK \(checks) — synthetic only; no Codex hook installation, model request, permission approval or external message")
    }
}
