import Foundation
import UniformTypeIdentifiers

enum FileServiceError: LocalizedError {
    case invalidName
    case cannotCreate(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Ese nombre no es válido. Escribe un nombre con su extensión, por ejemplo main.py"
        case .cannotCreate(let name):
            return "No se pudo crear \(name). Puede que la carpeta sea de solo lectura."
        }
    }
}

/// Capa de acceso a disco.
///
/// Es un `actor`: **todo** el trabajo de FileManager ocurre fuera del hilo
/// principal y serializado, así una copia de 4 GB no congela la interfaz ni
/// compite con otra operación sobre las mismas rutas. Las vistas solo hablan
/// con el ViewModel, que llama aquí con `await`.
actor FileService {
    static let shared = FileService()

    private let fm = FileManager.default
    private let keys: [URLResourceKey] = [
        .nameKey, .localizedNameKey, .isDirectoryKey, .fileSizeKey, .totalFileSizeKey, .creationDateKey,
        .contentModificationDateKey, .contentTypeKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey,
    ]

    // MARK: - Lectura

    /// Listado normal (rápido) para carpetas del propio sandbox.
    func list(_ directory: URL, showHidden: Bool) throws -> [FileItem] {
        let urls = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles])
        return urls.map { url in
            FileItem(url: url, values: try? url.resourceValues(forKeys: Set(keys)))
        }
    }

    // MARK: - Operaciones

    func createFolder(in directory: URL, named name: String) throws -> URL {
        let target = uniqueURL(directory.appendingPathComponent(name))
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    /// Crea un archivo vacío (0 bytes) con la extensión que se pida.
    ///
    /// El nombre llega escrito a mano, así que se sanea antes de tocar el
    /// disco: `/` es separador de rutas y `:` sigue siendo ilegal en el
    /// Finder, de modo que "a/b.py" debe crear un archivo, no una carpeta.
    /// Si ya existe uno igual, se numera como haría el Finder.
    func createFile(in directory: URL, named name: String) throws -> URL {
        let clean = Self.sanitized(name)
        guard !clean.isEmpty else { throw FileServiceError.invalidName }

        let target = uniqueURL(directory.appendingPathComponent(clean))
        guard fm.createFile(atPath: target.path, contents: Data(), attributes: nil) else {
            throw FileServiceError.cannotCreate(target.lastPathComponent)
        }
        return target
    }

    /// Deja el nombre en algo que el sistema de archivos acepta.
    nonisolated static func sanitized(_ name: String) -> String {
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for illegal in ["/", ":", "\0"] {
            clean = clean.replacingOccurrences(of: illegal, with: "-")
        }
        // "." y ".." no son nombres válidos
        return (clean == "." || clean == "..") ? "" : clean
    }

    func rename(_ url: URL, to newName: String) throws -> URL {
        let target = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard target != url else { return url }
        try fm.moveItem(at: url, to: uniqueURL(target))
        return target
    }

    func move(_ urls: [URL], to directory: URL) throws {
        for url in urls {
            let target = uniqueURL(directory.appendingPathComponent(url.lastPathComponent))
            if url.deletingLastPathComponent() == directory { continue }
            try fm.moveItem(at: url, to: target)
        }
    }

    func copy(_ urls: [URL], to directory: URL) throws {
        for url in urls {
            let target = uniqueURL(directory.appendingPathComponent(url.lastPathComponent))
            try fm.copyItem(at: url, to: target)
        }
    }

    func duplicate(_ urls: [URL]) throws {
        for url in urls {
            let ext = url.pathExtension
            let base = url.deletingPathExtension().lastPathComponent + " copia"
            var target = url.deletingLastPathComponent().appendingPathComponent(base)
            if !ext.isEmpty { target = target.appendingPathExtension(ext) }
            try fm.copyItem(at: url, to: uniqueURL(target))
        }
    }

    func delete(_ urls: [URL]) throws {
        for url in urls { try fm.removeItem(at: url) }
    }

    /// Comprime en ZIP usando el coordinador del sistema (sin dependencias).
    func compress(_ urls: [URL]) throws -> URL {
        guard let first = urls.first else { throw CocoaError(.fileNoSuchFile) }
        let directory = first.deletingLastPathComponent()
        // varios elementos: se agrupan antes en una carpeta temporal
        let source: URL
        var temporary: URL?
        if urls.count == 1 {
            source = first
        } else {
            let box = fm.temporaryDirectory.appendingPathComponent("Archivo \(UUID().uuidString)")
            try fm.createDirectory(at: box, withIntermediateDirectories: true)
            for url in urls {
                try fm.copyItem(at: url, to: box.appendingPathComponent(url.lastPathComponent))
            }
            source = box
            temporary = box
        }
        defer { if let temporary { try? fm.removeItem(at: temporary) } }

        var result: URL?
        var coordError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source,
                                       options: [.forUploading],
                                       error: &coordError) { zipped in
            let name = (urls.count == 1 ? first.deletingPathExtension().lastPathComponent
                                        : "Archivo")
            let target = uniqueURL(directory.appendingPathComponent(name + ".zip"))
            do {
                try fm.copyItem(at: zipped, to: target)
                result = target
            } catch { copyError = error }
        }
        if let coordError { throw coordError }
        if let copyError { throw copyError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return result
    }

    /// Tamaño real de una carpeta (recursivo). Caro: por eso vive en el actor.
    func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.fileSizeKey],
                                             options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Escribe datos entrantes (arrastre desde otra app) en una carpeta.
    func write(_ data: Data, named name: String, into directory: URL) throws -> URL {
        let target = uniqueURL(directory.appendingPathComponent(name))
        try data.write(to: target, options: .atomic)
        return target
    }

    // MARK: - Utilidades

    /// "informe.pdf" → "informe 2.pdf" si ya existe (como el Finder).
    private func uniqueURL(_ url: URL) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let base = url.deletingPathExtension()
        var index = 2
        while true {
            var candidate = URL(fileURLWithPath: "\(base.path) \(index)")
            if !ext.isEmpty { candidate = candidate.appendingPathExtension(ext) }
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }
}
