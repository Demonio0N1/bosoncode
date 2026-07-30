import Foundation

/// Papelera de ZeroSpin.
///
/// Antes, borrar llamaba a `removeItem` y el archivo desaparecía para siempre.
/// Ahora se mueve a una carpeta propia dentro del contenedor de la app y se
/// guarda de dónde venía, para poder devolverlo a su sitio.
///
/// Una limitación que conviene conocer: iPadOS **no expone la papelera del
/// sistema** ni la de los proveedores externos. Un archivo de OneDrive borrado
/// desde aquí va a esta papelera, no a la de OneDrive. Por eso el menú lo llama
/// "Mover a la papelera de ZeroSpin" y no promete más de lo que hace.
actor Trash {
    static let shared = Trash()

    private let fm = FileManager.default

    /// Dentro de Documents para que el usuario pueda vaciarla también desde la
    /// app Archivos si algo va mal.
    private var root: URL {
        let url = SystemLocation.documentsFolder.appendingPathComponent(".Papelera", isDirectory: true)
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    /// Qué había en cada elemento borrado, para poder restaurarlo.
    struct Entry: Codable, Identifiable, Sendable {
        let id: String            // nombre dentro de la papelera
        let originalPath: String
        let name: String
        let deletedAt: Date
        let isDirectory: Bool

        var originalFolder: String {
            (originalPath as NSString).deletingLastPathComponent
        }
    }

    // MARK: - Operaciones

    /// Mueve a la papelera. Devuelve cuántos elementos entraron.
    @discardableResult
    func move(_ urls: [URL]) throws -> Int {
        var entries = try index()
        var moved = 0
        for url in urls {
            // nombre único: dos "notas.txt" de carpetas distintas conviven
            let stored = "\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)"
            let target = root.appendingPathComponent(stored)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            do {
                try fm.moveItem(at: url, to: target)
            } catch {
                // Entre volúmenes distintos (un proveedor externo y el
                // contenedor de la app) mover falla: se copia y se borra.
                try fm.copyItem(at: url, to: target)
                try fm.removeItem(at: url)
            }
            entries.append(Entry(id: stored, originalPath: url.path,
                                 name: url.lastPathComponent, deletedAt: Date(),
                                 isDirectory: isDir.boolValue))
            moved += 1
        }
        try save(entries)
        return moved
    }

    func contents() throws -> [Entry] {
        try index().sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Devuelve el elemento a su carpeta original.
    func restore(_ entry: Entry) throws {
        let source = root.appendingPathComponent(entry.id)
        var destination = URL(fileURLWithPath: entry.originalPath)

        // Si la carpeta de origen ya no existe, se deja en Documents en lugar
        // de fallar: perder el archivo por no poder recrear la ruta sería peor.
        let folder = destination.deletingLastPathComponent()
        if !fm.fileExists(atPath: folder.path) {
            destination = SystemLocation.documentsFolder
                .appendingPathComponent(entry.name)
        }
        if fm.fileExists(atPath: destination.path) {
            destination = unique(destination)
        }
        try fm.moveItem(at: source, to: destination)
        try save(try index().filter { $0.id != entry.id })
    }

    /// Borra definitivamente un elemento de la papelera.
    func purge(_ entry: Entry) throws {
        try? fm.removeItem(at: root.appendingPathComponent(entry.id))
        try save(try index().filter { $0.id != entry.id })
    }

    /// Vacía la papelera entera.
    func empty() throws {
        for entry in try index() {
            try? fm.removeItem(at: root.appendingPathComponent(entry.id))
        }
        try save([])
    }

    var isEmpty: Bool {
        ((try? index()) ?? []).isEmpty
    }

    // MARK: - Índice

    private func index() throws -> [Entry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: indexURL, options: .atomic)
    }

    private func unique(_ url: URL) -> URL {
        var candidate = url
        var index = 2
        while fm.fileExists(atPath: candidate.path) {
            let ext = url.pathExtension
            var base = url.deletingPathExtension()
            base = base.deletingLastPathComponent()
                .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) \(index)")
            candidate = ext.isEmpty ? base : base.appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }
}
