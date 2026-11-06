import Foundation
@main enum PacksChecks { static func main() {
    var failed = 0
    func check(_ n: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + n); if !ok { failed += 1 } }
    for p in KeyPack.builtIn { check("built-in pack «\(p.name)» is valid and round-trips", p.valid && KeyPack.decode(p.encoded) == p) }
    let fromWeb = KeyPack.decode("eyJuYW1lIjoiVGVzdCDDsSIsImtleXMiOlt7ImxhYmVsIjoiR28iLCJ0ZXh0IjoiY29udGluw7phIMKreWHCuyIsImljb24iOiJhcnJvdy5yaWdodC5jaXJjbGUiLCJlbnRlciI6dHJ1ZX1dfQ")
    check("a pack encoded by the web page decodes in the app", fromWeb?.name == "Test ñ" && fromWeb?.keys.first?.text == "continúa «ya»")
    check("garbage is rejected", KeyPack.decode("not-a-pack") == nil)
    let big = KeyPack(name: "x", keys: Array(repeating: .init(label: "a", text: "b", icon: "c", enter: true), count: 13))
    check("more than 12 keys is rejected", KeyPack.decode(big.encoded) == nil)
    if failed > 0 { print("PACKS_FAILED \(failed)"); exit(1) }
    print("PACKS_OK — synthetic only")
} }
