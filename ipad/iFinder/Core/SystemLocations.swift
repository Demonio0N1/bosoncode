import Foundation

/// Ubicaciones del sistema que la barra lateral ofrece de entrada.
///
/// Conviene ser honesto con lo que iPadOS deja alcanzar sin permiso:
///
/// * **En mi iPad** — la carpeta Documents de la app. Es la que Archivos
///   muestra bajo "En mi iPad › iFinder" gracias a `UIFileSharingEnabled` y
///   `LSSupportsOpeningDocumentsInPlace`. Siempre disponible, sin selector.
/// * **Descargas** — una carpeta propia dentro de Documents. La "Descargas"
///   del sistema vive en iCloud Drive y **no** tiene ruta accesible desde el
///   sandbox; para esa hace falta el selector una vez.
/// * **iCloud Drive** — el contenedor de iCloud existe solo si la app declara
///   la capacidad correspondiente. Este proyecto no la tiene, así que aquí
///   devuelve `nil` y la fila pide permiso la primera vez.
///
/// Devolver `nil` no es un fallo: es la señal de "esta necesita el selector".
/// Una vez concedida, se guarda como montaje y las siguientes veces navega
/// directo, que es justo lo que faltaba.
enum SystemLocation: String, CaseIterable, Identifiable {
    case onMyIPad, iCloudDrive, downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onMyIPad: return "En mi iPad"
        case .iCloudDrive: return "iCloud Drive"
        case .downloads: return "Descargas"
        }
    }

    var icon: String {
        switch self {
        case .onMyIPad: return "ipad"
        case .iCloudDrive: return "icloud.fill"
        case .downloads: return "arrow.down.circle.fill"
        }
    }

    /// Ruta nativa navegable sin pedir nada, o `nil` si hace falta permiso.
    var url: URL? {
        switch self {
        case .onMyIPad: return Self.documentsFolder
        case .downloads: return Self.downloadsFolder
        case .iCloudDrive: return Self.iCloudDocuments
        }
    }

    // MARK: - Rutas nativas

    /// Documents de la app: el "En mi iPad" que el usuario ve en Archivos.
    static var documentsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Carpeta de descargas propia. Se crea la primera vez.
    static var downloadsFolder: URL? {
        let url = documentsFolder.appendingPathComponent("Descargas", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Contenedor de iCloud de la app, si la capacidad está activada.
    ///
    /// Se resuelve **una sola vez**: `url(forUbiquityContainerIdentifier:)`
    /// consulta al demonio de iCloud y no debe repetirse en cada dibujado.
    static let iCloudDocuments: URL? = {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil)
        else { return nil }
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }()
}
