import SwiftUI
import UIKit

/// Escalona las ventanas nuevas para que no se tapen por completo.
///
/// **Por qué no es un desplazamiento de posición.** iPadOS no deja colocar una
/// ventana en unas coordenadas concretas: `Scene.defaultPosition` y
/// `defaultWindowPlacement` están declaradas `@available(iOS, unavailable)`, y
/// el `systemFrame` de UIKit solo existe en Mac Catalyst. Quien decide dónde va
/// cada ventana es el sistema, y no hay API pública que lo cambie.
///
/// Lo que sí controlamos es el **tamaño**. Cada ventana nueva nace un escalón
/// más pequeña que la anterior, así que al quedar centrada deja asomar los
/// bordes de la que hay debajo: se ve que hay varias y se puede volver a la
/// anterior tocando el borde visible. Es la misma señal visual que da la
/// cascada de macOS, obtenida por el único camino disponible aquí.
@MainActor
enum WindowCascade {
    /// Cuántas ventanas se han abierto en esta sesión.
    private static var opened = 0

    /// Niveles antes de volver al tamaño original. Con más escalones las
    /// ventanas acabarían diminutas.
    private static let steps = 4

    static func nextSize(base: CGSize) -> CGSize {
        let level = opened % steps
        opened += 1
        return CGSize(width: max(360, base.width - CGFloat(level) * 48),
                      height: max(300, base.height - CGFloat(level) * 40))
    }
}

/// Aplica el tamaño escalonado a la escena que contiene esta vista.
struct CascadingWindowSize: UIViewRepresentable {
    let base: CGSize

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let size = WindowCascade.nextSize(base: base)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let restrictions = view.window?.windowScene?.sizeRestrictions else { return }
            // iPadOS solo respeta un tamaño inicial si mínimo y máximo
            // coinciden; se suelta enseguida para no atar la ventana
            restrictions.minimumSize = size
            restrictions.maximumSize = size
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                restrictions.minimumSize = CGSize(width: 280, height: 220)
                restrictions.maximumSize = CGSize(width: 10000, height: 10000)
                restrictions.allowsFullScreen = true
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
