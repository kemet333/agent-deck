// Captura de los tres estilos de la barra sin tocar la pantalla: ImageRenderer sobre un fondo propio,
// con ese fondo desenfocado haciendo de escritorio. Uso: style-preview <carpeta de salida>
import AppKit
import SwiftUI

struct Wallpaper: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: 0x1c1c21), Color(hex: 0x0b0b0d)], center: .center, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color(hex: 0xff5b1f, alpha: 0.6), .clear], center: UnitPoint(x: 0.12, y: 1), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: 0xff8c50, alpha: 0.25), .clear], center: UnitPoint(x: 0.92, y: 0), startRadius: 0, endRadius: 460)
        }
    }
}

MainActor.assumeIsolated {
    let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
    let size = CGSize(width: 1100, height: 220)
    let wallR = ImageRenderer(content: Wallpaper().frame(width: size.width, height: size.height))
    wallR.scale = 2
    guard let wall = wallR.nsImage else { fatalError("sin fondo") }
    let store = DeskStore()
    store.collapsed = false
    // escuchando (Fn pulsada) con la barra plegada: el orbe con la luz y lo que va oyendo
    do {
        store.listening = true; store.partial = "make the header sticky and"; store.level = 0.09
        let view = ZStack { Image(nsImage: wall).resizable(); Orb(store: store) }
            .frame(width: size.width, height: size.height)
            .environment(\.barTheme, Theme.of(.glass)).environment(\.snapshotBackdrop, wall)
        let r = ImageRenderer(content: view); r.scale = 2
        if let cg = r.cgImage { try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("listening.png")) }
        store.listening = false; store.partial = ""; store.level = 0
    }
    for st in BarStyle.allCases {
        for orb in [false, true] {
            let view = ZStack {
                Image(nsImage: wall).resizable()
                if orb { Orb(store: store) } else { Bar(store: store) }
            }
            .frame(width: size.width, height: size.height)
            .environment(\.barTheme, Theme.of(st))
            .environment(\.snapshotBackdrop, wall)
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let cg = r.cgImage else { fatalError("no se pudo dibujar \(st)") }
            let rep = NSBitmapImageRep(cgImage: cg)
            let file = out.appendingPathComponent("\(st.rawValue)\(orb ? "-orb" : "").png")
            try! rep.representation(using: .png, properties: [:])!.write(to: file)
            print(file.path)
        }
    }
}
