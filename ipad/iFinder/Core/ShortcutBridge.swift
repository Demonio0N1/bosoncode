import SwiftUI

/// Puente hacia la app Atajos para abrir documentos en su app de Office.
///
/// ## Por qué hace falta un rodeo
///
/// iPadOS no deja a una app de terceros lanzar un archivo en otra app sin
/// enseñar el menú de compartir. Atajos sí puede, porque es del sistema. La
/// idea es delegarle ese último paso.
///
/// ## Por qué no basta con pasarle la ruta
///
/// `shortcuts://run-shortcut` solo admite **texto** como entrada, y aunque
/// admitiera una ruta no serviría: Atajos también está aislado y no puede leer
/// dentro del contenedor de ZeroSpin. Un `/var/mobile/Containers/…` es, para
/// él, una cadena sin sentido.
///
/// Lo que sí funciona es apoyarse en algo que ya es cierto de esta app: su
/// carpeta **aparece en Archivos** (`UIFileSharingEnabled` +
/// `LSSupportsOpeningDocumentsInPlace`). Así que el archivo se deja ahí y por
/// la URL solo viaja su NOMBRE. El atajo lo recoge de esa carpeta —a la que el
/// usuario le da permiso una sola vez— y lo abre.
///
/// El reparto queda: ZeroSpin pone el archivo a la vista y dice cuál es; Atajos
/// hace lo que nosotros no podemos.
enum ShortcutBridge {
    /// Nombre por defecto del atajo. El usuario puede cambiarlo si ya tiene
    /// otro suyo: lo único que importa es que coincida con el de Atajos.
    static let defaultName = "Abrir en Office"

    /// Subcarpeta de intercambio, dentro de lo que se ve desde Archivos.
    static var inbox: URL {
        SystemLocation.documentsFolder.appendingPathComponent("Atajos", isDirectory: true)
    }

    static var isShortcutsInstalled: Bool {
        guard let url = URL(string: "shortcuts://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Deja el archivo a la vista de Atajos y lanza el atajo con su nombre.
    @MainActor
    static func open(_ url: URL, shortcut: String) async throws {
        guard isShortcutsInstalled else { throw ShortcutError.noShortcutsApp }

        // Copia y no referencia: el original puede estar en una nube sin
        // descargar, o en una carpeta cuyo permiso Atajos no tiene.
        let data = try await CloudFileHandler.shared.read(url)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let staged = inbox.appendingPathComponent(url.lastPathComponent)
        try data.write(to: staged, options: .atomic)

        var comps = URLComponents()
        comps.scheme = "shortcuts"
        comps.host = "run-shortcut"
        comps.queryItems = [
            URLQueryItem(name: "name", value: shortcut),
            URLQueryItem(name: "input", value: "text"),
            // solo el nombre: la carpeta la conoce el atajo
            URLQueryItem(name: "text", value: url.lastPathComponent),
        ]
        guard let target = comps.url else { throw ShortcutError.badName(shortcut) }
        await UIApplication.shared.open(target)
    }

    /// Receta del atajo, para enseñarla dentro de la app.
    ///
    /// Se explica en vez de generarlo porque **no hay API para crear atajos**:
    /// un `.shortcut` es un archivo firmado y solo la propia app Atajos puede
    /// producirlo. Lo que sí se puede es dejar el trabajo hecho por este lado y
    /// pedir cuatro pasos una única vez.
    static let recipe = """
    En la app Atajos, crea uno llamado exactamente «\(defaultName)» con estos \
    cuatro pasos:

    1. Recibir Texto de Atajos rápidos  (es el nombre del archivo)
    2. Obtener archivo  →  carpeta: En mi iPad › ZeroSpin › Atajos
       y en «Ruta» pon el Texto que llega del paso 1
    3. Abrir en…  (o Abrir archivo)
    4. Guarda el atajo

    La primera vez Atajos pedirá permiso para esa carpeta; se concede una sola \
    vez y ya queda.
    """
}

enum ShortcutError: LocalizedError {
    case noShortcutsApp
    case badName(String)

    var errorDescription: String? {
        switch self {
        case .noShortcutsApp:
            return "La app Atajos no está disponible en este iPad."
        case .badName(let name):
            return "«\(name)» no es un nombre de atajo que se pueda enviar."
        }
    }
}


/// Lleva el archivo a la app Archivos y la abre ahí.
///
/// Archivos SÍ lanza un .docx en Word sin diálogos, y ninguna app de terceros
/// puede: no es cuestión de usar el componente adecuado, sino de permisos que
/// el sistema no cede. `UIDocumentBrowserViewController` —que parece la puerta—
/// no lo es; su propia documentación dice que sirve para "abrirlos **en tu**
/// aplicación", y su único callback de selección devuelve la URL a quien lo
/// presenta. No lanza nada externo.
///
/// Lo que sí se puede es dejar el archivo donde Archivos lo ve —la carpeta de
/// ZeroSpin ya aparece ahí— y abrir Archivos en ese punto. De ahí, un toque y
/// Word. No es automático, pero es el comportamiento nativo de verdad, sin
/// menús intermedios ni imitaciones.
enum RevealInFiles {
    static var isAvailable: Bool {
        guard let url = URL(string: "shareddocuments:///") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    @MainActor
    static func reveal(_ url: URL) async throws {
        let data = try await CloudFileHandler.shared.read(url)
        let folder = SystemLocation.documentsFolder
        let staged = folder.appendingPathComponent(url.lastPathComponent)
        // si ya está en la carpeta visible, no se duplica
        if staged.standardizedFileURL != url.standardizedFileURL {
            try data.write(to: staged, options: .atomic)
        }
        // `shareddocuments://` abre Archivos en una ruta concreta
        guard let target = URL(string: "shareddocuments://" + staged.path) else {
            throw ShortcutError.badName(staged.lastPathComponent)
        }
        await UIApplication.shared.open(target)
    }
}
