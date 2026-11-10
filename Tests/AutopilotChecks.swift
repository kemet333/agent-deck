import Foundation

@main
enum AutopilotChecks {
    static func main() {
        var failed = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { failed += 1 } }
        check("no question: keep going", !Autopilot.shouldBrake("Done. I updated the login form and ran the tests."))
        check("«shall I continue?»: keep going", !Autopilot.shouldBrake("Tests pass. Shall I continue with the sign-up form?"))
        check("«¿sigo con…?»: keep going", !Autopilot.shouldBrake("Hecho el login. ¿Sigo con el formulario de registro?"))
        check("«which option?»: brake", Autopilot.shouldBrake("I can do it two ways. Which option do you prefer?"))
        check("«¿Postgres o SQLite?»: brake", Autopilot.shouldBrake("Antes de seguir: ¿uso Postgres o SQLite?"))
        check("«should I use A or B?»: brake", Autopilot.shouldBrake("Should I use Redis or Memcached for the cache?"))
        check("asks for a key: brake", Autopilot.shouldBrake("I need your Stripe API key to go on. Can you paste it?"))
        check("other question: brake", Autopilot.shouldBrake("What name should the new table have?"))
        // estado: se guarda, se gasta y caduca
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ap-\(UUID().uuidString)")
        setenv("AGENT_DECK_FOLDER", tmp.path, 1)
        Autopilot.start(2, message: "continue")
        check("starts with 2", Autopilot.load()?.remaining == 2)
        Autopilot.save(AutopilotState(remaining: 0, message: "continue", until: Date().timeIntervalSince1970 + 60))
        check("0 left is off", Autopilot.load() == nil)
        Autopilot.save(AutopilotState(remaining: 3, message: "continue", until: Date().timeIntervalSince1970 - 1))
        check("expired is off", Autopilot.load() == nil)
        // objetivo: tests en verde
        check("goal: «All tests pass.» reached", Autopilot.goalReached("tests", last: "Fixed the parser. All tests pass."))
        check("goal: «Todos los tests pasan» reached", Autopilot.goalReached("tests", last: "Arreglado. Todos los tests pasan (55)."))
        check("goal: «42 passed, 0 failed» reached", Autopilot.goalReached("tests", last: "Ran the suite: 42 passing, 0 failed."))
        check("goal: «2 tests still fail» not reached", !Autopilot.goalReached("tests", last: "Progress, but 2 tests still fail."))
        check("goal: «not all tests pass» not reached", !Autopilot.goalReached("tests", last: "Not all tests pass yet."))
        check("goal: «fallan 3» not reached", !Autopilot.goalReached("tests", last: "Los tests pasan casi todos; fallan 3."))
        check("no goal: never reached", !Autopilot.goalReached(nil, last: "All tests pass."))
        Autopilot.start(1, message: "go", goal: "tests", hours: 1)
        check("start keeps the goal", Autopilot.load()?.goal == "tests" && Autopilot.load()?.turns == 0)
        Autopilot.save(AutopilotState(remaining: 0, message: "go", until: Date().timeIntervalSince1970 + 60, goal: nil, turns: 3))
        check("used up: off but still readable for the summary", Autopilot.load() == nil && Autopilot.loadAny()?.turns == 3)
        // colas por agente
        AgentQueue.add("Kemet-Capital", "pasa los tests")
        check("queue: add returns the count", AgentQueue.add("Kemet-Capital", "haz el commit") == 2)
        check("queue: other folder gets nothing", AgentQueue.pop(place: "Brojjki") == nil)
        let first = AgentQueue.pop(place: "Kemet-Capital")
        check("queue: first in, first out", first?.text == "pasa los tests" && first?.left == 1)
        AgentQueue.add("Kémet", "y despliega")
        check("queue: «Kémet» is found from Kemet-Capital", AgentQueue.pop(place: "Kemet-Capital") != nil)
        try? FileManager.default.removeItem(at: tmp)
        if failed > 0 { print("AUTOPILOT_FAILED \(failed)"); exit(1) }
        print("AUTOPILOT_OK — synthetic only")
    }
}
