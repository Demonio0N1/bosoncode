import SwiftUI

/// Navegación por el contenido con las flechas del Magic Keyboard.
///
/// Va como modificador aparte por dos razones: mantiene la ventana legible y,
/// sobre todo, deja en un solo sitio la regla de cuándo **no** debe actuar
/// (mientras se renombra un archivo, las flechas son del campo de texto).
///
/// `.onKeyPress` solo recibe teclas si la vista tiene el foco, de ahí el
/// `.focusable()` en la ventana: sin él las flechas se quedan en la barra
/// lateral y el área de archivos nunca las ve.
struct ArrowKeyNavigation: ViewModifier {
    @ObservedObject var model: BrowserViewModel
    /// Falso mientras hay un campo de texto activo.
    var enabled: Bool

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow) { move(.up) }
            .onKeyPress(.downArrow) { move(.down) }
            .onKeyPress(.leftArrow) { move(.left) }
            .onKeyPress(.rightArrow) { move(.right) }
        // Intro NO se toca: en el Finder renombra, y ese atajo ya existe.
        // Abrir es ⌘O / ⌘↓, como en macOS.
    }

    /// En la rejilla, arriba y abajo saltan una fila entera; en lista y en
    /// columnas se mueven de uno en uno y los lados navegan carpetas.
    private var columns: Int {
        model.viewMode == .icons ? max(1, model.gridColumnCount) : 1
    }

    private func move(_ direction: BrowserViewModel.MoveDirection) -> KeyPress.Result {
        guard enabled else { return .ignored }
        Task { await model.moveSelection(direction, columns: columns) }
        return .handled
    }
}
