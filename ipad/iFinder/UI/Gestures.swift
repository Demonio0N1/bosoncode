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
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: PassThroughView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fired() { action() }
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
}
