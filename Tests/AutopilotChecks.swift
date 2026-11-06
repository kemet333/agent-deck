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
        try? FileManager.default.removeItem(at: tmp)
        if failed > 0 { print("AUTOPILOT_FAILED \(failed)"); exit(1) }
        print("AUTOPILOT_OK — synthetic only")
    }
}
