import AppKit
import SwiftUI

/// Ajustes → Trading (0.21): preparar TradingView, el pack Trader y la calculadora de contratos por riesgo.
@MainActor
struct TradingPane: View {
    @ObservedObject var store: DeskStore
    var actions = DashboardActions()
    @AppStorage("tradeSymbol") private var symbol = "MNQ"
    @AppStorage("tradeRiskMode") private var riskInPercent = false
    @AppStorage("tradeRisk") private var risk = 200.0
    @AppStorage("tradeBalance") private var balance = 50_000.0
    @AppStorage("tradePercent") private var percent = 0.5
    @State private var stop = 20.0

    private var instrument: Trading.Instrument { Trading.instruments.first { $0.symbol == symbol } ?? Trading.instruments[0] }
    private var dollars: Double { riskInPercent ? Trading.risk(percent: percent, of: balance) : risk }
    private var traderPack: GalleryPack? { GalleryStore.shared.packs.first { $0.id == "trader-tradingview" } ?? GalleryStore.bundled.first { $0.id == "trader-tradingview" } }
    private var hasPack: Bool { store.keys.contains { $0.apps.contains(Trading.tradingView[0]) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            // 1. calculadora
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(T.s("Position size", "Tamaño de la posición")).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Picker("", selection: $symbol) { ForEach(Trading.instruments) { Text("\($0.symbol) · \($0.name)").tag($0.symbol) } }.labelsHidden().frame(width: 220)
                }
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("", selection: $riskInPercent) { Text(T.s("Risk $", "Riesgo $")).tag(false); Text(T.s("Risk %", "Riesgo %")).tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
                        if riskInPercent {
                            HStack(spacing: 6) { field($percent, width: 60); Text(T.s("% of", "% de")).foregroundStyle(.secondary); field($balance, width: 90); Text("$").foregroundStyle(.secondary) }
                        } else {
                            HStack(spacing: 6) { field($risk, width: 90); Text(T.s("$ per trade", "$ por operación")).foregroundStyle(.secondary) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T.s("Stop", "Stop")).font(.system(size: 11)).foregroundStyle(.secondary)
                        HStack(spacing: 6) { field($stop, width: 70); Text(T.s("points", "puntos")).foregroundStyle(.secondary) }
                    }
                }.font(.system(size: 12))
                if let s = Trading.size(risk: dollars, stopPoints: stop, instrument: instrument) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(s.contracts)").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(s.contracts == 0 ? Color(hex: 0xff9f0a) : Color(hex: 0x32d74b))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.contracts == 1 ? T.s("contract of \(instrument.symbol)", "contrato de \(instrument.symbol)") : T.s("contracts of \(instrument.symbol)", "contratos de \(instrument.symbol)")).font(.system(size: 13, weight: .medium))
                            Text(s.contracts == 0
                                 ? T.s("The stop is too wide for that risk: one contract risks \(Trading.money(s.riskPerContract)).", "El stop es demasiado amplio para ese riesgo: un contrato arriesga \(Trading.money(s.riskPerContract)).")
                                 : T.s("Real risk \(Trading.money(s.realRisk)) · \(s.stopTicks) ticks × \(Trading.money(instrument.tickValue)) per contract", "Riesgo real \(Trading.money(s.realRisk)) · \(s.stopTicks) ticks × \(Trading.money(instrument.tickValue)) por contrato"))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x32d74b).opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x32d74b).opacity(0.2), lineWidth: 0.5))

            // 2. pack
            DashSection(title: T.s("Keys for TradingView", "Teclas para TradingView"), footer: T.s("They only act with TradingView in front; in any other app they do nothing. Pressing Buy again is how you scale in. Close, reverse and move the stop have no TradingView shortcut: they come with the Tradovate connection.",
                                                                                                    "Solo actúan con TradingView delante; en otra app no hacen nada. Promediar es pulsar otra vez Compra (o Vende). Cerrar, invertir y mover el stop no tienen atajo en TradingView: llegarán con la conexión a Tradovate.")) {
                DashRow(title: T.s("Trader pack", "Pack Trader"), detail: T.s("Buy and sell at market or limit with your preset, center the DOM", "Compra y vende a mercado o límite con tu preset, centra el DOM"), symbol: "chart.line.uptrend.xyaxis", divider: false) {
                    Button(hasPack ? T.s("Added", "Añadido") : T.s("Add…", "Añadir…")) { if let p = traderPack { actions.offerPack(p.pack(spanish: T.es)) } }
                        .controlSize(.small).disabled(hasPack || traderPack == nil)
                }
            }

            // 3. preparar TradingView
            DashSection(title: T.s("Set up TradingView once", "Prepara TradingView una vez"), footer: T.s("Try it on a demo account first. Agent Bar only presses TradingView's own shortcuts: the order, its size and its brackets are TradingView's.",
                                                                                                         "Pruébalo primero en una cuenta demo. Agent Bar solo pulsa los atajos de TradingView: la orden, su tamaño y sus brackets son los de TradingView.")) {
                step(1, T.s("Connect your broker (Tradovate) in TradingView's Trading Panel.", "Conecta tu bróker (Tradovate) en el panel de Trading de TradingView."))
                step(2, T.s("Open an order, set the quantity from the calculator above and your stop and target, then «Save order preset…».", "Abre una orden, pon la cantidad de la calculadora de arriba, tu stop y tu objetivo, y «Guardar preset de orden…»."))
                step(3, T.s("Apply that preset to the chart's Buy/Sell buttons.", "Aplica ese preset a los botones Comprar/Vender del gráfico."))
                step(4, T.s("Choose «Place orders without confirmation» to fire with one key, or keep confirmation while you learn.", "Elige «Colocar órdenes sin confirmación» para disparar con una tecla, o deja la confirmación mientras aprendes."), divider: false)
            }
        }
        .onAppear { GalleryStore.shared.refresh() }
    }

    private func field(_ v: Binding<Double>, width: CGFloat) -> some View {
        TextField("", value: v, format: .number).textFieldStyle(.roundedBorder).frame(width: width).multilineTextAlignment(.trailing)
    }
    private func step(_ n: Int, _ text: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(n)").font(.system(size: 11, weight: .bold, design: .rounded)).frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            if divider { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, 46) }
        }
    }
}
