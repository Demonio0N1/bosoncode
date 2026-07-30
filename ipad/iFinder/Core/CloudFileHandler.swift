import Foundation

/// Estado de materialización de un elemento de un proveedor externo
/// (iCloud, OneDrive, Google Drive, SMB por Tailscale…).
enum MaterializationState: Sendable {
    case local            // está en disco: se puede abrir ya
    case remote           // vive en la nube: hay que descargarlo
    case downloading(Double?)   // en curso (progreso 0-1 si el proveedor lo informa)
    case unknown
}

enum CloudError: LocalizedError {
    case timedOut(String)
    case accessDenied(String)
    case staleBookmark

    var errorDescription: String? {
        switch self {
        case .timedOut(let what):
            return "El proveedor no respondió a tiempo (\(what)). Puede estar sin conexión."
        case .accessDenied(let path):
            return "Sin permiso para acceder a \(path). Vuelve a añadir la carpeta."
        case .staleBookmark:
            return "El permiso guardado caducó. Selecciona la carpeta de nuevo."
        }
    }
}

/// Envoltura segura para leer de proveedores externos.
///
/// Tres problemas que resuelve y que no existen con archivos locales:
///  1. **Ámbito de seguridad**: cada URL de un proveedor necesita abrirse y
///     cerrarse; si se olvida el cierre, el sistema acaba revocando el acceso.
///  2. **Coordinación**: los proveedores materializan el archivo *al leerlo*.
///     Sin `NSFileCoordinator` se lee un fichero de 0 bytes o un marcador.
///  3. **Latencia**: OneDrive o un SMB por Tailscale pueden tardar segundos o
///     no responder. Toda llamada lleva un plazo máximo y nunca bloquea la UI.
actor CloudFileHandler {
    static let shared = CloudFileHandler()

    /// Raíces concedidas por el usuario, con su ámbito abierto. Un descendiente
    /// no puede abrir ámbito propio: hereda el de su raíz, así que hay que
    /// mantenerla registrada mientras se navega dentro.
    private nonisolated(unsafe) static var scopedRoots: [URL] = []

    nonisolated static func registerRoot(_ url: URL) {
        if !scopedRoots.contains(url) { scopedRoots.append(url) }
    }

    /// Raíz que contiene esta ruta (si alguna).
    nonisolated static func root(containing url: URL) -> URL? {
        scopedRoots.first { url.path == $0.path || url.path.hasPrefix($0.path + "/") }
    }

    private static let listKeys: [URLResourceKey] = [
        .nameKey, .localizedNameKey, .isDirectoryKey, .fileSizeKey, .totalFileSizeKey, .creationDateKey, .contentModificationDateKey,
        .contentTypeKey, .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
    ]

    // MARK: - Acceso con ámbito de seguridad

    /// Ejecuta trabajo con el ámbito abierto y garantiza el cierre.
    /// Devuelve el valor del bloque; nunca deja el ámbito abierto por error.
    private nonisolated static func withAccess<T>(_ url: URL, _ work: () throws -> T) throws -> T {
        // Se abre el ámbito de la propia URL y, si es un descendiente, también
        // el de su raíz concedida (de la que hereda el permiso).
        let scoped = url.startAccessingSecurityScopedResource()
        let rootURL = root(containing: url)
        let rootScoped = (rootURL != nil && rootURL != url)
            ? rootURL!.startAccessingSecurityScopedResource() : false
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            if rootScoped, let rootURL { rootURL.stopAccessingSecurityScopedResource() }
        }
        return try work()
    }

    // MARK: - Estado de descarga

    /// ¿El archivo está en disco o solo en la nube?
    nonisolated static func state(of url: URL) -> MaterializationState {
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
        ]) else { return .unknown }

        // Los proveedores de terceros (OneDrive, Drive, SMB) reutilizan las
        // mismas claves "ubiquitous" que iCloud desde iOS 11.
        guard values.isUbiquitousItem == true else { return .local }
        if values.ubiquitousItemIsDownloading == true { return .downloading(nil) }
        switch values.ubiquitousItemDownloadingStatus {
        case .current, .downloaded: return .local
        case .notDownloaded: return .remote
        default: return .unknown
        }
    }

    /// Fuerza la descarga y espera a que el archivo esté disponible.
    ///
    /// `startDownloadingUbiquitousItem` funciona con iCloud; con proveedores de
    /// terceros suele fallar, y ahí la vía que sí funciona es una **lectura
    /// coordinada**, que obliga al proveedor a materializar el fichero.
    /// Deja el archivo listo para usarse.
    ///
    /// No espera a que iCloud declare la sincronización "completa": basta con
    /// que los datos se puedan leer, cosa que ocurre bastante antes. Ese
    /// desfase es el que hacía que la app pareciera colgada descargando.
    func materialize(_ url: URL, timeout: TimeInterval = 60) async throws {
        if ICloudAvailability.isUsable(url) { return }

        try Self.withAccess(url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        do {
            try await ICloudAvailability.waitUntilUsable(url, timeout: timeout)
        } catch {
            // proveedores que ignoran startDownloading: la lectura coordinada
            // los obliga a materializar
            _ = try await coordinatedRead(url, timeout: 20)
        }
    }

    /// Devuelve el archivo a la nube y recupera el espacio en el iPad.
    ///
    /// Es la operación inversa de `materialize`: el archivo sigue en el
    /// listado, pero vuelve a ser un marcador de posición. Solo tiene sentido
    /// en elementos gestionados por un File Provider.
    func evict(_ url: URL) throws {
        try Self.withAccess(url) {
            try FileManager.default.evictUbiquitousItem(at: url)
        }
    }

    // MARK: - Lecturas coordinadas con plazo

    /// Lista un directorio de un proveedor externo sin colgar la interfaz.
    func list(_ directory: URL, showHidden: Bool, timeout: TimeInterval = 25) async throws -> [FileItem] {
        try await Self.withDeadline(timeout, what: directory.lastPathComponent) {
            try Self.withAccess(directory) {
                var result: [FileItem] = []
                var coordError: NSError?
                var inner: Error?
                NSFileCoordinator().coordinate(readingItemAt: directory,
                                       options: [.withoutChanges],
                                       error: &coordError) { coordinated in
                    do {
                        let urls = try FileManager.default.contentsOfDirectory(
                            at: coordinated,
                            includingPropertiesForKeys: Self.listKeys,
                            options: showHidden ? [] : [.skipsHiddenFiles])
                        // CLAVE: el coordinador entrega una URL sustituta y sus
                        // hijos NO heredan el permiso. Cada elemento se ancla a
                        // la carpeta original (la que sí tiene ámbito abierto),
                        // o al entrar en una subcarpeta el sistema deniega.
                        result = urls.map { child in
                            let stable = directory.appendingPathComponent(child.lastPathComponent)
                            return FileItem(url: stable,
                                            values: try? child.resourceValues(forKeys: Set(Self.listKeys)))
                        }
                    } catch { inner = error }
                }
                if let coordError { throw coordError }
                if let inner { throw inner }
                return result
            }
        }
    }

    /// Lee el contenido completo, materializando antes si hace falta.
    func read(_ url: URL, timeout: TimeInterval = 120) async throws -> Data {
        try await materialize(url, timeout: timeout)
        return try await coordinatedRead(url, timeout: timeout)
    }

    private func coordinatedRead(_ url: URL, timeout: TimeInterval) async throws -> Data {
        try await Self.withDeadline(timeout, what: url.lastPathComponent) {
            try Self.withAccess(url) {
                var data = Data()
                var coordError: NSError?
                var inner: Error?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { readable in
                    do { data = try Data(contentsOf: readable) } catch { inner = error }
                }
                if let coordError { throw coordError }
                if let inner { throw inner }
                return data
            }
        }
    }

    /// Escritura coordinada (el proveedor sincroniza el cambio a la nube).
    func write(_ data: Data, to url: URL, timeout: TimeInterval = 120) async throws {
        try await Self.withDeadline(timeout, what: url.lastPathComponent) {
            try Self.withAccess(url.deletingLastPathComponent()) {
                var coordError: NSError?
                var inner: Error?
                NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing],
                                       error: &coordError) { target in
                    do { try data.write(to: target, options: .atomic) } catch { inner = error }
                }
                if let coordError { throw coordError }
                if let inner { throw inner }
            }
        }
    }

    // MARK: - Plazo máximo

    /// Corre el trabajo contra un reloj: si el proveedor no responde, se
    /// aborta con un error legible en vez de dejar la app colgada.
    private nonisolated static func withDeadline<T: Sendable>(_ seconds: TimeInterval,
                                           what: String,
                                           _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await Task.detached(priority: .userInitiated) { try work() }.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CloudError.timedOut(what)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw CloudError.timedOut(what)
            }
            return first
        }
    }
}
