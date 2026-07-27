import Foundation

/// Arranque de la app, para distinguir lo que pide el usuario de lo que
/// restaura el sistema.
///
/// iPadOS vuelve a abrir las ventanas de la sesión anterior, y en SwiftUI eso
/// no se puede desactivar: `SceneRestorationBehavior.disabled` está declarado
/// `@available(iOS, unavailable)` — solo existe en macOS y visionOS. Así que la
/// app no lo impide, lo deshace: una ventana de vista previa que aparece sola
/// durante el arranque, sin que nadie la haya pedido, se cierra.
@MainActor
enum AppLaunch {
    private static let started = Date()

    /// El usuario abrió una previa a propósito.
    private static var requested = false

    /// Ventana de esos primeros instantes en los que cualquier previa que
    /// aparezca viene de la restauración, no de un toque.
    private static let graceInterval: TimeInterval = 2.5

    static func markPreviewRequested() { requested = true }

    /// ¿Esta previa la ha restaurado el sistema?
    static var isRestoredWindow: Bool {
        !requested && Date().timeIntervalSince(started) < graceInterval
    }
}
