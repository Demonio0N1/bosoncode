import SwiftUI
import UIKit

/// Deja que la escena que contiene esta vista se redimensione libremente.
struct CascadingWindowSize: UIViewRepresentable {
    /// Se conserva el parámetro aunque ya no imponga nada: quien lo pasa dice
    /// qué tamaño espera, y ese dato vive ahora en el `.defaultSize` de la
    /// escena. Quitarlo obligaría a tocar todas las llamadas sin ganar nada.
    let base: CGSize

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        // Solo se sueltan las restricciones; NO se fuerza ningún tamaño.
        //
        // Antes se apretaba mínimo == máximo un instante para imponer el
        // tamaño inicial y se soltaba 0,4 s después. Funcionaba, pero se veía:
        // la ventana aparecía, daba un salto y se quedaba. Y si la habías
        // movido o ajustado en ese margen, te la cambiaba debajo de la mano.
        //
        // Ese truco era necesario cuando iPadOS ignoraba `.defaultSize`. Con el
        // sistema de ventanas actual sí lo respeta, y las escenas ya lo
        // declaran, así que forzarlo solo aporta el salto.
        for delay in [0.2, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let restrictions = view.window?.windowScene?.sizeRestrictions else { return }
                restrictions.minimumSize = CGSize(width: 280, height: 220)
                restrictions.maximumSize = CGSize(width: 10000, height: 10000)
                restrictions.allowsFullScreen = true
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
