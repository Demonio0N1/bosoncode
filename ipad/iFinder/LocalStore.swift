import SwiftUI
import UniformTypeIdentifiers

/// Carpetas del iPad a las que el usuario ha dado acceso permanente.
/// iOS aísla las apps, pero una carpeta concedida con el selector queda
/// accesible para siempre mediante un marcador de seguridad.
@MainActor
final class LocalStore: ObservableObject {
    struct Folder: Identifiable, Codable {
        let id: UUID
        var name: String
        let bookmark: Data
        /// Opcional a propósito: los montajes guardados por versiones
        /// anteriores no lo traen, y un campo no opcional haría fallar la
        /// decodificación entera — se perderían todos los permisos.
        var provider: CloudProvider?

        var kind: CloudProvider { provider ?? .folder }
    }

    @Published private(set) var folders: [Folder] = []
    private var openScopes: [UUID: URL] = [:]

    /// Montajes de nube (Drive, OneDrive…) y carpetas normales, por separado:
    /// la barra lateral los muestra en secciones distintas, como Archivos.
    var mounts: [Folder] { folders.filter { $0.kind.isCloud } }
    var plainFolders: [Folder] { folders.filter { !$0.kind.isCloud } }

    init() {
        load()
        restoreAll()
    }

    /// Resuelve **todos** los marcadores al arrancar.
    ///
    /// No es solo para pintar la barra lateral: al resolverlos se registran
    /// las raíces concedidas, y sin ese registro cualquier ruta interior de un
    /// montaje (la que llega en un arrastre o en una vista previa) se
    /// rechazaría por falta de permiso hasta que el usuario pulsara antes en
    /// la nube correspondiente.
    func restoreAll() {
        for folder in folders { _ = url(for: folder) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: "localFolders"),
              let list = try? JSONDecoder().decode([Folder].self, from: data) else { return }
        folders = list
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: "localFolders")
        }
    }

    /// Guarda el permiso de una carpeta concedida en el selector.
    /// OJO: hay que abrir el ámbito de seguridad ANTES de crear el marcador;
    /// si no, se guarda un permiso inválido y la carpeta no vuelve a abrirse.
    /// Busca un montaje por su nombre (para saber si una ubicación del
    /// sistema ya fue concedida antes).
    func folder(named name: String) -> Folder? {
        folders.first { $0.name == name }
    }

    /// Guarda una carpeta con un nombre elegido por el usuario.
    ///
    /// Devuelve el montaje creado para que quien llame pueda renombrarlo luego
    /// sin adivinar cuál es. Antes se hacía con `folders.last`, que acierta por
    /// casualidad: cualquier cambio en el orden lo rompía en silencio.
    @discardableResult
    func add(url: URL, named name: String) -> Folder? {
        guard add(url: url), let created = folders.last else { return nil }
        rename(created, to: name)
        return folders.first { $0.id == created.id }
    }

    @discardableResult
    func add(url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { return false }
        let provider = CloudProvider.detect(url)
        // Se identifica el montaje por su RUTA, no por su nombre.
        //
        // Antes se descartaba cualquier montaje que se llamara igual, y dos
        // cuentas del mismo servicio suelen llamarse igual: montar el OneDrive
        // del segundo campus borraba el del primero sin decir nada. Además el
        // permiso del que se iba quedaba abierto para siempre.
        for old in folders where self.url(for: old)?.standardizedFileURL == url.standardizedFileURL {
            stopAccess(old.id)
            folders.removeAll { $0.id == old.id }
        }
        let folder = Folder(id: UUID(),
                            name: uniqueName(provider.suggestedName(for: url)),
                            bookmark: bookmark,
                            provider: provider)
        folders.append(folder)
        persist()
        // el permiso vale desde ya, sin reiniciar
        _ = self.url(for: folder)
        return true
    }

    /// "OneDrive", "OneDrive 2"… Dos cuentas del mismo servicio con la carpeta
    /// raíz igual llegan aquí con el mismo nombre, y en la barra lateral serían
    /// indistinguibles. Numerarlas deja al usuario renombrarlas después.
    ///
    /// `excluding` es el propio montaje cuando se está renombrando: sin él, un
    /// montaje se consideraría en conflicto consigo mismo y "OneDrive" se
    /// convertiría en "OneDrive 2" al confirmar su propio nombre.
    private func uniqueName(_ name: String, excluding id: UUID? = nil) -> String {
        func taken(_ candidate: String) -> Bool {
            folders.contains { $0.name == candidate && $0.id != id }
        }
        guard taken(name) else { return name }
        var index = 2
        while taken("\(name) \(index)") { index += 1 }
        return "\(name) \(index)"
    }

    /// Renombrar el montaje: la única forma de distinguir dos cuentas del
    /// mismo servicio, porque el sistema no expone a cuál pertenece la ruta.
    func rename(_ folder: Folder, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = folders.firstIndex(where: { $0.id == folder.id })
        else { return }
        // También aquí se numera. Este es el camino por el que pasa el nombre
        // sugerido al montar, así que sin esto la segunda cuenta de OneDrive
        // volvía a llamarse igual que la primera y el arreglo de `add` no
        // servía de nada: dos filas idénticas en la barra lateral.
        folders[index].name = uniqueName(clean, excluding: folder.id)
        persist()
    }

    func remove(_ folder: Folder) {
        stopAccess(folder.id)
        folders.removeAll { $0.id == folder.id }
        persist()
    }

    /// Marcadores que caducaron (el proveedor movió la carpeta o cerró sesión)
    @Published private(set) var staleFolders: Set<UUID> = []

    /// Resuelve el marcador y abre el acceso protegido (hay que cerrarlo luego).
    ///
    /// Los proveedores de terceros invalidan sus marcadores al reconectar la
    /// cuenta: hay que detectarlo, renovarlo si se puede y, si no, avisar para
    /// que el usuario vuelva a conceder la carpeta.
    func url(for folder: Folder) -> URL? {
        if let open = openScopes[folder.id] { return open }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            staleFolders.insert(folder.id)
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else {
            staleFolders.insert(folder.id)
            return nil
        }
        if stale, let renewed = try? url.bookmarkData(options: .minimalBookmark,
                                                      includingResourceValuesForKeys: nil,
                                                      relativeTo: nil),
           let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = Folder(id: folder.id, name: folder.name,
                                    bookmark: renewed, provider: folder.provider)
            persist()
        }
        staleFolders.remove(folder.id)
        openScopes[folder.id] = url
        CloudFileHandler.registerRoot(url)   // sus subcarpetas heredan el permiso
        return url
    }

    func stopAccess(_ id: UUID) {
        openScopes[id]?.stopAccessingSecurityScopedResource()
        openScopes[id] = nil
    }

    deinit {
        for (_, url) in openScopes { url.stopAccessingSecurityScopedResource() }
    }
}

/// Selector nativo de carpetas del iPad (iCloud Drive, En mi iPad, unidades
/// externas, servidores SMB montados…). Lo que elijas queda accesible.
struct FolderPicker: UIViewControllerRepresentable {
    var startAt: URL? = nil
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder],
                                                    asCopy: false)
        picker.allowsMultipleSelection = false
        if let startAt { picker.directoryURL = startAt }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
