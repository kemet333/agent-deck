import Foundation

/// Agent Bar para traders (0.21): {pulsa …} en las teclas y la calculadora de contratos por riesgo.
@main
struct TradingChecks {
    static var failures = 0
    static func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FALLA: \(what)") } }

    static func main() {
        // combinaciones
        let b = KeyText.combo("⇧B")
        check(b?.key == 11 && b?.flags == KeyText.shiftBit && b?.label == "⇧B", "⇧B: \(String(describing: b))")
        let ob = KeyText.combo("⇧⌥B")
        check(ob?.flags == KeyText.shiftBit | KeyText.optionBit && ob?.label == "⌥⇧B", "⇧⌥B: \(ob?.label ?? "")")
        check(KeyText.combo("shift+alt+s")?.flags == KeyText.shiftBit | KeyText.optionBit && KeyText.combo("shift+alt+s")?.key == 1, "con palabras")
        check(KeyText.combo("mayús+b")?.key == 11, "mayús en español")
        check(KeyText.combo("cmd+enter")?.key == 36 && KeyText.combo("cmd+enter")?.flags == KeyText.commandBit, "cmd+enter")
        check(KeyText.combo("hiper+b") == nil && KeyText.combo("") == nil && KeyText.combo("⇧") == nil, "lo que no se entiende, nada")

        // pasos: {pulsa …} es un paso propio, con su espera
        let s = KeyText.steps("{pulsa ⇧B}\n{espera 0,5}\n{press shift+b}")
        check(s.count == 2 && s[0].press?.label == "⇧B" && s[1].press?.label == "⇧B" && s[1].wait == 0.5, "dos pulsaciones con espera: \(s)")
        let mixed = KeyText.steps("sigue\n{pulsa ⇧S}\nhecho")
        check(mixed.map { $0.press?.label ?? $0.text } == ["sigue", "⇧S", "hecho"], "texto y pulsación mezclados: \(mixed.map { $0.press?.label ?? $0.text })")
        check(KeyText.steps("{pulsa algo raro}").first?.press == nil, "una pulsación que no se entiende se escribe tal cual")
        check(KeyText.preview("{pulsa ⇧B}").contains("⇧B"), "la vista previa dice qué pulsa")
        check(KeyText.uses("{pulsa ⇧B}").isEmpty, "{pulsa} no es una variable")

        // calculadora
        let mnq = Trading.instruments.first { $0.symbol == "MNQ" }!
        let a = Trading.size(risk: 200, stopPoints: 20, instrument: mnq)
        check(a?.contracts == 5 && a?.realRisk == 200 && a?.stopTicks == 80, "MNQ 200 $ / 20 pt = 5: \(String(describing: a))")
        let nq = Trading.instruments.first { $0.symbol == "NQ" }!
        check(Trading.size(risk: 300, stopPoints: 20, instrument: nq)?.contracts == 0, "NQ: un contrato arriesga 400 $ → 0")
        check(Trading.size(risk: 450, stopPoints: 10.1, instrument: nq)?.stopTicks == 41, "el stop se redondea al tick de arriba")
        check(Trading.size(risk: 450, stopPoints: 10.1, instrument: nq)?.contracts == 2, "nunca más riesgo del dicho (2 × 205 $)")
        check(Trading.size(risk: 0, stopPoints: 10, instrument: nq) == nil && Trading.size(risk: 10, stopPoints: 0, instrument: nq) == nil, "sin riesgo o sin stop, nada")
        check(Trading.risk(percent: 0.5, of: 50_000) == 250, "0,5 % de 50.000 = 250")
        check(Trading.instruments.first { $0.symbol == "CL" }?.tickValue == 10 && Trading.instruments.first { $0.symbol == "MES" }?.tickValue == 1.25, "valor del tick")

        if failures > 0 { print("TRADING_FAIL \(failures)"); exit(1) }
        print("TRADING_OK")
    }
}
