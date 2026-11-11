import Foundation

/// Cuándo devolver el portapapeles después de pegar (0.19.1). Antes se devolvía a los ~0,6 s fijos y, si el chat iba
/// lento (Claude o ChatGPT escribiendo una respuesta), leía el portapapeles cuando ya se había devuelto y pegaba lo que
/// hubiera antes en lugar del dictado. Ahora el texto se da «a demanda» y se sabe cuándo lo lee la app de destino:
/// se devuelve 0,3 s después de esa lectura (y nunca antes de que haya entrado el Intro).
enum PasteTiming {
    /// - tap: cuándo se pulsó ⌘V · firstRead: la primera vez que alguien pidió el texto · settle: lo mínimo (Intro incluido).
    static func restoreAt(tap: Date, firstRead: Date?, settle: TimeInterval) -> Date {
        let floor = tap.addingTimeInterval(settle)
        // nadie lo ha leído aún: el chat está ocupado; se espera hasta 8 s a que lo lea
        guard let r = firstRead else { return tap.addingTimeInterval(max(settle, 8)) }
        // lo leyó tras el ⌘V: es el pegado
        if r >= tap.addingTimeInterval(-0.02) { return max(floor, r.addingTimeInterval(0.3)) }
        // lo leyó antes del ⌘V (un gestor de portapapeles): no sabemos cuándo pega el chat; margen amplio
        return tap.addingTimeInterval(max(settle, 3))
    }
}
