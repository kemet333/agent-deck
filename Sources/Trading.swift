import Foundation

/// Agent Bar para traders (0.21, Diego 12/11/2026): ejecutar en TradingView con teclas y voz, para mecanizar la ejecución.
/// Fase 1: los atajos de trading de TradingView (⇧B / ⇧S a mercado, ⇧⌥B / ⇧⌥S límite) con el preset de orden activo
/// (cantidad, stop y objetivo) y una calculadora de contratos por riesgo. Cerrar, invertir y mover el stop no tienen
/// atajo en TradingView: fase 2, con la API de Tradovate. Nada se ejecuta sin que el trader pulse.
enum Trading {
    static let tradingView = ["com.tradingview.tradingviewapp.desktop"]

    /// Futuros que se operan con Tradovate y las cuentas de fondeo: dólares por punto y tamaño del tick.
    struct Instrument: Equatable, Hashable, Identifiable {
        let symbol: String; let name: String; let pointValue: Double; let tick: Double
        var id: String { symbol }
        var tickValue: Double { pointValue * tick }
    }
    static let instruments: [Instrument] = [
        Instrument(symbol: "MNQ", name: "Micro Nasdaq 100", pointValue: 2, tick: 0.25),
        Instrument(symbol: "NQ", name: "Nasdaq 100", pointValue: 20, tick: 0.25),
        Instrument(symbol: "MES", name: "Micro S&P 500", pointValue: 5, tick: 0.25),
        Instrument(symbol: "ES", name: "S&P 500", pointValue: 50, tick: 0.25),
        Instrument(symbol: "M2K", name: "Micro Russell 2000", pointValue: 5, tick: 0.1),
        Instrument(symbol: "RTY", name: "Russell 2000", pointValue: 50, tick: 0.1),
        Instrument(symbol: "MYM", name: "Micro Dow", pointValue: 0.5, tick: 1),
        Instrument(symbol: "YM", name: "Dow", pointValue: 5, tick: 1),
        Instrument(symbol: "MGC", name: "Micro Gold", pointValue: 10, tick: 0.1),
        Instrument(symbol: "GC", name: "Gold", pointValue: 100, tick: 0.1),
        Instrument(symbol: "MCL", name: "Micro Crude Oil", pointValue: 100, tick: 0.01),
        Instrument(symbol: "CL", name: "Crude Oil", pointValue: 1000, tick: 0.01),
    ]

    struct Size: Equatable { let contracts: Int; let riskPerContract: Double; let realRisk: Double; let stopTicks: Int }
    /// Contratos para no pasar de `risk` dólares con un stop de `stopPoints` puntos (hacia abajo: nunca más riesgo del dicho).
    static func size(risk: Double, stopPoints: Double, instrument: Instrument) -> Size? {
        guard risk > 0, stopPoints > 0 else { return nil }
        let ticks = Int((stopPoints / instrument.tick).rounded(.up))
        let perContract = Double(ticks) * instrument.tickValue
        guard perContract > 0 else { return nil }
        let n = Int((risk / perContract).rounded(.down))
        return Size(contracts: n, riskPerContract: perContract, realRisk: Double(n) * perContract, stopTicks: ticks)
    }
    /// El riesgo en dólares a partir de un % de la cuenta.
    static func risk(percent: Double, of balance: Double) -> Double { max(0, balance * percent / 100) }

    /// «12,5 $» / «$12.50».
    static func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.maximumFractionDigits = v.rounded() == v ? 0 : 2
        f.locale = Locale(identifier: T.es ? "es_ES" : "en_US")
        return f.string(from: NSNumber(value: v)) ?? "\(v) $"
    }
}
