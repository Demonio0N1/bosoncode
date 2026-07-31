import SwiftUI

/// Acciones de la ventana que tiene el foco.
///
/// Los menús del sistema no ven el estado de ninguna ventana: se lo tiene que
/// contar la propia ventana activa. Con varias abiertas, cada una publica las
/// suyas y el atajo cae en la que estás usando.
struct BosonActions {
    let openTerminal: () -> Void
}

private struct BosonActionsKey: FocusedValueKey {
    typealias Value = BosonActions
}

extension FocusedValues {
    var boson: BosonActions? {
        get { self[BosonActionsKey.self] }
        set { self[BosonActionsKey.self] = newValue }
    }
}

/// Menú de la barra superior de iPadOS.
///
/// Aquí está la diferencia con el botón oculto que había dentro de la vista: un
/// atajo declarado en `.commands` lo registra iPadOS a nivel de APLICACIÓN, y
/// responde tenga el foco quien lo tenga. El botón oculto, en cambio, depende
/// de estar en la cadena de respondedores, y justo después de conectar esa
/// cadena todavía no llega a él — por eso ⌃⌥T no hacía nada al entrar en una
/// máquina y sí funcionaba tras el primer toque.
struct BosonCommands: Commands {
    @FocusedValue(\.boson) private var actions

    var body: some Commands {
        CommandMenu("Terminal") {
            Button("Terminal en ventana propia") {
                actions?.openTerminal()
            }
            // OJO: sin `.disabled`, y es deliberado. Un elemento de menú
            // desactivado SIGUE quedándose el atajo, así que desactivarlo
            // cuando no hay ventana activa impediría que lo recogiera el
            // UIKeyCommand del editor. Prefiere no hacer nada a bloquearlo.
            .keyboardShortcut("t", modifiers: [.control, .option])
        }
    }
}
