import SwiftUI
import UIKit

/// Abre un archivo en **otra app** del iPad, como el doble clic de macOS.
///
/// `UIDocumentInteractionController` es el equivalente de "Abrir con…": muestra
/// las apps capaces de manejar ese tipo y le entrega el archivo a la elegida.
/// Como el destino es otro proceso, el archivo debe estar en un sitio que
/// pueda leer: por eso se le pasa siempre una copia en el contenedor propio.
@MainActor
final class SystemOpen: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = SystemOpen()

    /// Se retiene mientras el menú está en pantalla; si no, desaparece.
    private var controller: UIDocumentInteractionController?

    private override init() {}

    /// Presenta "Abrir con…" para el archivo indicado.
    /// - Returns: `false` si no hay ninguna app capaz de abrirlo.
    @discardableResult
    func openInDefaultApp(_ url: URL) -> Bool {
        guard let anchor = Self.topViewController() else { return false }

        let interaction = UIDocumentInteractionController(url: url)
        interaction.delegate = self
        controller = interaction

        // menú de apps compatibles, anclado al centro (iPad exige un origen)
        let rect = CGRect(x: anchor.view.bounds.midX - 1,
                          y: anchor.view.bounds.midY - 1,
                          width: 2, height: 2)
        let shown = interaction.presentOpenInMenu(from: rect, in: anchor.view, animated: true)
        if !shown {
            // ninguna app declara ese tipo: se ofrece la hoja de compartir
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = anchor.view
            share.popoverPresentationController?.sourceRect = rect
            anchor.present(share, animated: true)
        }
        return shown
    }

    func documentInteractionControllerDidDismissOpenInMenu(_ controller: UIDocumentInteractionController) {
        self.controller = nil
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
