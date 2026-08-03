import SwiftUI
import UniformTypeIdentifiers

/// Recibe lo que se suelta desde OTRA app.
///
/// ## Por qué no basta `dropDestination(for: URL.self)`
///
/// Ese modificador solo acepta lo que el origen sepa entregar como una `URL`, y
/// muchas apps no entregan rutas. **Fotos es el caso claro**: al arrastrar una
/// foto vende los DATOS de la imagen —`public.jpeg`, `public.heic`—, no un
/// archivo en disco, porque la foto vive en su propia base de datos y puede que
/// ni siquiera esté descargada de iCloud. Sin URL, la suelta simplemente no se
/// reconocía y el gesto no hacía nada.
///
/// Aquí se pide en cambio una **representación de archivo** de lo que sea que
/// traiga (`.item`, la raíz de todos los tipos). El sistema se encarga de
/// materializarlo —descargando de iCloud si hace falta— y entrega un archivo
/// temporal. Así entran por igual las fotos, los archivos de Archivos y lo que
/// mande cualquier otra app.
enum IncomingDrop {

    /// Copia a un temporal propio todo lo soltado y devuelve las rutas.
    ///
    /// - Important: la URL que da el sistema **solo vive durante la llamada**,
    ///   así que se copia dentro del propio bloque. Guardarla para después deja
    ///   una ruta que ya no existe, y ese es el fallo clásico de este API.
    static func stage(_ providers: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in providers {
                group.addTask { await stageOne(provider) }
            }
            var staged: [URL] = []
            for await url in group {
                if let url { staged.append(url) }
            }
            return staged
        }
    }

    private static func stageOne(_ provider: NSItemProvider) async -> URL? {
        // El nombre sugerido se lee AQUÍ, fuera del bloque: `NSItemProvider` no
        // es `Sendable` y capturarlo dentro cruza un límite de concurrencia.
        let suggested = provider.suggestedName
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.item.identifier
            ) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let inbox = FileManager.default.temporaryDirectory
                    .appendingPathComponent("entrante", isDirectory: true)
                try? FileManager.default.createDirectory(at: inbox,
                                                         withIntermediateDirectories: true)
                // Un nombre útil. Fotos entrega archivos con nombres internos
                // tipo "IMG_0001.HEIC" o directamente un identificador, así que
                // se prefiere el que la app de origen sugiera y se conserva la
                // extensión del temporal, que es la que dice el tipo real.
                let ext = url.pathExtension
                var name = suggested ?? url.lastPathComponent
                if !ext.isEmpty, (name as NSString).pathExtension.isEmpty {
                    name = (name as NSString).appendingPathExtension(ext) ?? name
                }
                let target = inbox.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: target)
                do {
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: target)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
