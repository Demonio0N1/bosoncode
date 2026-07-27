import SwiftUI
import UIKit

/// Doble toque con tres dedos.
///
/// SwiftUI no permite filtrar por número de dedos, así que se superpone una
/// vista de UIKit con un `UITapGestureRecognizer` de tres toques. El truco
/// está en `point(inside:with:)`: la vista solo "existe" para el sistema de
/// eventos cuando hay tres dedos en pantalla, de modo que los toques normales
/// (uno o dos dedos) la atraviesan y llegan a la fila de SwiftUI que hay debajo.
struct ThreeFingerTapView: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> PassThroughView {
        let view = PassThroughView()
        let recognizer = UITapGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.fired))
        recognizer.numberOfTouchesRequired = 3
        recognizer.numberOfTapsRequired = 2
        recognizer.cancelsTouchesInView = false
        // segundo cerrojo: con el trackpad, los toques indirectos pueden
        // contarse de forma rara; aquí se comprueba el número real de dedos
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: PassThroughView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fired() { action() }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            recognizer.numberOfTouches == 3
        }
    }

    /// Solo intercepta cuando hay tres dedos; el resto pasa de largo.
    final class PassThroughView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            (event?.allTouches?.count ?? 0) >= 3 && super.point(inside: point, with: event)
        }
    }
}

extension View {
    /// Ejecuta la acción al hacer **doble** toque con tres dedos.
    func onThreeFingerDoubleTap(perform action: @escaping () -> Void) -> some View {
        overlay(ThreeFingerTapView(action: action))
    }

    /// Toques de un archivo, mutuamente excluyentes.
    ///
    /// `ExclusiveGesture` es la pieza clave: evalúa el primer gesto y solo si
    /// **no** llega a reconocerse pasa al segundo. Así el doble clic nunca
    /// dispara además la selección, ni deja a medias un gesto que otro
    /// modificador pueda recoger.
    ///
    /// El menú contextual no entra en esta jerarquía a propósito: vive en su
    /// propio reconocedor (pulsación larga con el dedo, clic secundario con el
    /// trackpad), que son entradas que el `TapGesture` no reconoce. Por
    /// construcción no pueden dispararse a la vez.
    func fileTapGestures(_ model: BrowserViewModel,
                         item: FileItem,
                         level: Int) -> some View {
        contentShape(Rectangle())
            .gesture(
                ExclusiveGesture(
                    // 1º: doble clic → abrir, y nada más
                    TapGesture(count: 2).onEnded {
                        Task { await model.openDoubleClick(item, at: level) }
                    },
                    // 2º: clic simple → seleccionar
                    TapGesture(count: 1).onEnded {
                        Task { await model.select(item, at: level) }
                    }
                )
            )
    }
}
