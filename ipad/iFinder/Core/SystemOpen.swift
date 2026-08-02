import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Apertura de archivos en **otras apps** del iPad.
///
/// Dos rutas, deliberadamente distintas:
///
/// * `openInApp` — doble clic. Entrega el archivo a la app que lo abre
///   (Word, Excel, Pages…) sin que intervenga ninguna app del sistema.
/// * `presentOptions` — doble toque con tres dedos. Menú completo: abrir con,
///   copiar, imprimir, guardar en Archivos.
///
/// Sobre iPadOS: **no existe API pública para lanzar un archivo local en "su
/// app por defecto"**, porque el sistema no guarda asociaciones tipo → app
/// como macOS. `UIApplication.shared.open` con una URL `file://` devuelve
/// `false`, y el atajo `shareddocuments://` no abre la app del documento sino
/// **la app Archivos** — que es exactamente lo que se quería evitar aquí, así
/// que se ha eliminado. La única vía que entrega el archivo a la app destino
/// es `UIDocumentInteractionController`.
@MainActor
final class SystemOpen: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = SystemOpen()

    /// Se retiene mientras el menú está en pantalla; si no, desaparece.
    private var controller: UIDocumentInteractionController?

    private override init() {}

    // MARK: - Doble clic: entregar el archivo a su app

    /// Enseña la lista de apps capaces de abrir el archivo.
    ///
    /// Es la lista real de LaunchServices —con iconos y con la predeterminada
    /// primero—, no una construida a mano: enumerar esas apps desde código
    /// exigiría API privada, pero pedirle al sistema que las MUESTRE es público.
    ///
    /// - Returns: `false` si ninguna app declara ese tipo (entonces se ofrece
    ///   la hoja de compartir como salida).
    @discardableResult
    func openInApp(_ url: URL) -> Bool {
        present(url) { interaction, rect, view in
            interaction.presentOpenInMenu(from: rect, in: view, animated: true)
        }
    }

    // MARK: - Tres dedos: menú completo de opciones

    /// Menú con todo lo que el sistema sabe hacer con el archivo: abrir con,
    /// copiar, imprimir, guardar en Archivos, marcar…
    @discardableResult
    func presentOptions(_ url: URL) -> Bool {
        present(url) { interaction, rect, view in
            interaction.presentOptionsMenu(from: rect, in: view, animated: true)
        }
    }

    /// Tronco común: prepara el controlador, lo retiene y ancla el popover.
    private func present(_ url: URL,
                         show: (UIDocumentInteractionController, CGRect, UIView) -> Bool) -> Bool {
        guard let anchor = Self.topViewController() else { return false }

        let interaction = UIDocumentInteractionController(url: url)
        interaction.delegate = self
        // Se declara el tipo explícitamente además de por el nombre. El
        // controlador lo deduce de la extensión, pero decírselo cubre los casos
        // en que el archivo llega con un nombre pobre —de una nube, por
        // ejemplo— y evita volver a una lista vacía por un detalle así.
        if let type = UTType(filenameExtension: url.pathExtension) {
            interaction.uti = type.identifier
        }
        controller = interaction

        // El iPad exige un origen para el popover, y hay que dárselo en la
        // VENTANA correcta: con varias escenas abiertas, anclarlo a otra hacía
        // que la lista saliera flotando sobre una ventana distinta de aquella
        // donde se pulsó. `topViewController` ya elige la escena activa; el
        // rectángulo se calcula sobre SU vista, no sobre una cualquiera.
        let rect = CGRect(x: anchor.view.bounds.midX - 1,
                          y: anchor.view.bounds.midY - 1,
                          width: 2, height: 2)
        let shown = show(interaction, rect, anchor.view)
        if !shown {
            // ninguna app declara ese tipo: se ofrece la hoja de compartir
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = anchor.view
            share.popoverPresentationController?.sourceRect = rect
            anchor.present(share, animated: true)
        }
        return shown
    }

    // UIKit llama a estos desde fuera del actor principal: se marcan
    // nonisolated y el estado se toca ya dentro de él.
    nonisolated func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        Task { @MainActor in self.controller = nil }
    }

    nonisolated func documentInteractionControllerDidDismissOptionsMenu(_ controller: UIDocumentInteractionController) {
        Task { @MainActor in self.controller = nil }
    }

    /// Controlador visible de la escena activa (para presentar desde él).
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
