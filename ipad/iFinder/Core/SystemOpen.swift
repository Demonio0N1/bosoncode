import SwiftUI
import UIKit

/// Apertura de archivos en **otras apps** del iPad.
///
/// Hay dos rutas distintas, y conviene no confundirlas:
///
/// * `launchDirectly` — doble clic. Intenta abrir sin preguntar nada.
/// * `presentOpenMenu` — toque con tres dedos. Muestra "Abrir con…" para
///   elegir app a mano.
///
/// Nota importante sobre iPadOS: **no existe API pública para lanzar un archivo
/// local en "su app por defecto"**, porque el sistema no guarda una asociación
/// tipo → app como macOS. Lo más parecido a una apertura sin menús es cederle
/// el archivo a la app Archivos con `shareddocuments://`, que aplica el manejo
/// del sistema. Si eso falla, se recurre al menú.
@MainActor
final class SystemOpen: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = SystemOpen()

    /// Se retiene mientras el menú está en pantalla; si no, desaparece.
    private var controller: UIDocumentInteractionController?

    private override init() {}

    // MARK: - Doble clic: abrir sin menús

    /// Abre el archivo directamente, sin interfaz intermedia.
    ///
    /// - Parameters:
    ///   - original: ruta real del archivo (la que ve la app Archivos).
    ///   - copy: copia en el contenedor propio, para el plan B.
    /// - Returns: `false` si ninguna ruta directa funcionó y hubo que
    ///   recurrir al menú.
    @discardableResult
    func launchDirectly(original: URL, copy: URL) async -> Bool {
        // 1. Esquemas que el sistema sabe abrir por sí solo.
        if !original.isFileURL, await UIApplication.shared.open(original) { return true }

        // 2. Cesión a la app Archivos: abre el documento con el manejo por
        //    defecto del sistema, sin pasar por ninguna lista de apps.
        if let handoff = Self.sharedDocumentsURL(for: original),
           await UIApplication.shared.open(handoff) {
            return true
        }

        // 3. Sin ruta directa: se ofrece elegir app.
        presentOpenMenu(copy)
        return false
    }

    /// `shareddocuments://<ruta>` — la vía que usa el propio sistema para
    /// saltar a un documento concreto dentro de Archivos.
    private static func sharedDocumentsURL(for url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let encoded = url.path.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) ?? url.path
        return URL(string: "shareddocuments://" + encoded)
    }

    // MARK: - Tres dedos: elegir app

    /// Presenta "Abrir con…" para el archivo indicado.
    /// - Returns: `false` si no hay ninguna app capaz de abrirlo (entonces se
    ///   muestra la hoja de compartir).
    @discardableResult
    func presentOpenMenu(_ url: URL) -> Bool {
        guard let anchor = Self.topViewController() else { return false }

        let interaction = UIDocumentInteractionController(url: url)
        interaction.delegate = self
        controller = interaction

        // el iPad exige un origen para el popover
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
