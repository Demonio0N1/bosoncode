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
    @discardableResult
    func add(url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: .minimalBookmark,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil) else { return false }
        let provider = CloudProvider.detect(url)
        let folder = Folder(id: UUID(),
                            name: provider.suggestedName(for: url),
                            bookmark: bookmark,
                            provider: provider)
        folders.removeAll { $0.name == folder.name }
        folders.append(folder)
        persist()
        // el permiso vale desde ya, sin reiniciar
        _ = self.url(for: folder)
        return true
    }

    /// Renombrar el montaje: la única forma de distinguir dos cuentas del
    /// mismo servicio, porque el sistema no expone a cuál pertenece la ruta.
    func rename(_ folder: Folder, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = folders.firstIndex(where: { $0.id == folder.id })
        else { return }
        folders[index].name = clean
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
