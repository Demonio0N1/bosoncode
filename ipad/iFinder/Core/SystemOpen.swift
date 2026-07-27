import SwiftUI
import UIKit

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

    /// Abre el archivo en la app que lo maneja, sin que la app Archivos
    /// aparezca en ningún momento.
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
        controller = interaction

        // el iPad exige un origen para el popover
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
