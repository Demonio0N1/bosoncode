import Foundation

extension URL {
    /// Nombre tal y como lo enseñaría el sistema, no el que hay en disco.
    ///
    /// Hace falta porque muchas rutas del sistema y de los proveedores llevan
    /// nombres internos que no son para leerse: `com~apple~CloudDocs` es
    /// "iCloud Drive", `File Provider Storage` es el nombre real del servicio,
    /// y las carpetas del sistema están traducidas ("Downloads" → "Descargas").
    ///
    /// Tres intentos, de más informado a más tonto:
    ///   1. `.localizedNameKey` — el nombre que el proveedor o el sistema
    ///      declara para esa URL; el único que conoce las traducciones.
    ///   2. `displayName(atPath:)` — respeta la preferencia de ocultar
    ///      extensiones y funciona aunque los valores de recurso fallen.
    ///   3. `lastPathComponent` — siempre existe.
    ///
    /// Los dos primeros tocan disco, así que **no** debe llamarse durante el
    /// dibujado de una lista: se resuelve una vez al listar o al montar.
    var displayName: String {
        if let name = try? resourceValues(forKeys: [.localizedNameKey]).localizedName,
           !name.isEmpty {
            return name
        }
        let byPath = FileManager.default.displayName(atPath: path)
        return byPath.isEmpty ? lastPathComponent : byPath
    }
}
