import Foundation

/// Disponibilidad real de un archivo de iCloud / File Provider.
///
/// El estado que publica el sistema (`ubiquitousItemDownloadingStatus`) tarda
/// en pasar a `.current` porque espera a que **toda** la sincronización acabe
/// (metadatos, versiones, conflictos). Pero para *leer* el archivo basta con
/// que sus datos estén materializados, cosa que ocurre bastante antes.
///
/// Esta clase decide con una prueba directa —¿puedo leer bytes?— en lugar de
/// fiarse del estado global, y así abre el archivo en cuanto es utilizable.
enum ICloudAvailability {

    /// Prueba definitiva: ¿el archivo se puede leer AHORA?
    ///
    /// Intenta abrir un descriptor y leer el primer bloque. Si el proveedor no
    /// lo ha materializado, la lectura falla o devuelve vacío; si responde con
    /// datos, el archivo ya sirve aunque iCloud siga diciendo "descargando".
    static func isUsable(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        else { return false }
        if values.isDirectory == true { return true }
        let size = values.fileSize ?? 0
        guard size > 0 else { return false }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let probe = try? handle.read(upToCount: min(size, 4096))
        return (probe?.isEmpty == false)
    }

    /// Progreso informado por el sistema (0-1), si el proveedor lo publica.
    static func progress(of url: URL) -> Double? {
        let query = NSMetadataQuery()
        // (consulta puntual sin arrancar el query: se leen los valores del URL)
        _ = query
        guard let values = try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
        ]) else { return nil }
        switch values.ubiquitousItemDownloadingStatus {
        case .current, .downloaded: return 1
        case .notDownloaded: return 0
        default: return nil
        }
    }

    /// Espera hasta que el archivo sea **utilizable**, no hasta que iCloud lo
    /// declare completo. Devuelve en cuanto se puede leer.
    ///
    /// - Parameters:
    ///   - url: archivo en iCloud o en un File Provider.
    ///   - timeout: plazo máximo; pasado, lanza para no bloquear la interfaz.
    ///   - onProgress: informe opcional para la barra de estado.
    static func waitUntilUsable(_ url: URL,
                                timeout: TimeInterval = 60,
                                onProgress: (@Sendable (Double?) -> Void)? = nil) async throws {
        if isUsable(url) { return }

        // se pide la descarga (iCloud la respeta; otros proveedores la ignoran
        // y materializan con la lectura coordinada del final)
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(timeout)
        // sondeo rápido al principio: los archivos pequeños llegan en ~200 ms
        var delay: UInt64 = 120_000_000        // 0,12 s
        while Date() < deadline {
            if isUsable(url) { return }        // ← sale ANTES de que el estado sea "completado"
            onProgress?(progress(of: url))
            try await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { throw CancellationError() }
            delay = min(delay * 2, 1_000_000_000)   // hasta 1 s entre intentos
        }
        throw CloudError.timedOut(url.lastPathComponent)
    }
}
