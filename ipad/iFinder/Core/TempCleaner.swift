import Foundation

/// Limpieza de las copias temporales.
///
/// Quick Look y la apertura en otras apps trabajan sobre copias en
/// `temporaryDirectory`, porque el proceso destino no hereda nuestros permisos.
/// Esas copias no se borraban nunca: con archivos grandes, el contenedor crecía
/// sin control hasta que iOS decidía vaciarlo, que puede tardar días.
enum TempCleaner {
    /// Borra las copias de sesiones anteriores. Se llama al arrancar, cuando
    /// con seguridad ninguna está abierta.
    static func purgeOldCopies() {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory
        guard let files = try? fm.contentsOfDirectory(
            at: temp, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        let cutoff = Date().addingTimeInterval(-3600)   // margen de una hora
        for file in files where file.lastPathComponent.hasPrefix("preview-") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified > cutoff { continue }
            try? fm.removeItem(at: file)
        }
    }
}
