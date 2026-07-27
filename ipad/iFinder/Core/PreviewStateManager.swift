import SwiftUI

/// Registro de ventanas de vista previa abiertas.
///
/// IMPORTANTE: ya no decide **qué** muestra cada ventana — eso viaja como
/// valor de escena, para que cada ventana conserve su archivo aunque la
/// principal cambie de selección. Aquí solo se anota qué URLs están abiertas,
/// que es lo que necesita la barra espaciadora para alternar.
@MainActor
final class PreviewStateManager: ObservableObject {
    static let shared = PreviewStateManager()

    @Published private(set) var openURLs: Set<URL> = []

    private init() {}

    var isAnyOpen: Bool { !openURLs.isEmpty }

    func isOpen(_ url: URL) -> Bool { openURLs.contains(url) }

    func opened(_ url: URL) { openURLs.insert(url) }

    func closed(_ url: URL) { openURLs.remove(url) }
}
