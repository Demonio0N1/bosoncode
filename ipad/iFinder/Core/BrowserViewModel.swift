import SwiftUI
import Combine

enum ViewMode: String, CaseIterable, Identifiable {
    case icons, list, columns
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        }
    }
    var label: String {
        switch self {
        case .icons: return "Iconos"
        case .list: return "Lista"
        case .columns: return "Columnas"
        }
    }
}

/// Estado de una carpeta abierta (una columna en la vista de columnas).
struct DirectoryLevel: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var items: [FileItem] = []
    var selection: Set<String> = []
    static func == (a: DirectoryLevel, b: DirectoryLevel) -> Bool { a.id == b.id }
}

/// ViewModel de la ventana.
///
/// Es la **única** fuente de verdad de la interfaz y el único que habla con
/// `FileService`. Mantiene la vista sincronizada con el disco de dos maneras:
/// (1) recarga tras cada operación propia y (2) un observador del sistema
/// (`DispatchSource`) que avisa cuando *otro proceso* toca la carpeta abierta.
@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var levels: [DirectoryLevel] = []
    @Published var viewMode: ViewMode = .columns
    @Published var showHidden = false
    @Published var sortKey: SortKey = .name
    @Published var busy = false
    @Published var error: String?
    @Published var renaming: FileItem?
    @Published var renameText = ""
    @Published var inspecting: FileItem?
    @Published var quickLookURL: URL?
    /// Nombre del archivo que se está bajando de la nube (para el aviso)
    @Published var downloadingName: String?
    /// Texto del buscador de la barra de navegación
    @Published var searchText = ""
    /// Columnas que la rejilla de iconos tiene ahora mismo en pantalla; lo
    /// publica la propia vista y lo usan las flechas arriba/abajo.
    @Published var gridColumnCount = 1
    /// Alerta de "archivo nuevo" y el nombre que se escribe en ella
    @Published var creatingFile = false
    @Published var newFileName = ""
    /// Nombre que debe quedar seleccionado tras la próxima recarga
    private var pendingSelection: String?

    enum SortKey: String, CaseIterable, Identifiable {
        case name, size, date, kind
        var id: String { rawValue }
        var label: String {
            switch self {
            case .name: return "Nombre"
            case .size: return "Tamaño"
            case .date: return "Fecha"
            case .kind: return "Tipo"
            }
        }
    }

    /// Portapapeles al estilo Finder: copiar o cortar y pegar después.
    private(set) var clipboard: [URL] = []
    private(set) var clipboardIsCut = false

    private var watcher: DispatchSourceFileSystemObject?
    private var watchedDescriptor: Int32 = -1

    // MARK: - Estado derivado

    var current: DirectoryLevel? { levels.last }
    var currentURL: URL? { levels.last?.url }

    var selectedItems: [FileItem] {
        guard let level = levels.last else { return [] }
        return level.items.filter { level.selection.contains($0.id) }
    }

    var canPaste: Bool { !clipboard.isEmpty }

    // MARK: - Navegación

    func open(_ url: URL) async {
        levels = []
        await push(url)
    }

    func push(_ url: URL) async {
        await load(url, appending: true)
    }

    /// Al elegir una carpeta en un nivel, se cierran los niveles a su derecha.
    func select(_ item: FileItem, at level: Int, additive: Bool = false) async {
        guard levels.indices.contains(level) else { return }
        if additive {
            if levels[level].selection.contains(item.id) {
                levels[level].selection.remove(item.id)
            } else {
                levels[level].selection.insert(item.id)
            }
        } else {
            levels[level].selection = [item.id]
        }
        if levels.count > level + 1 { levels.removeSubrange((level + 1)...) }
        if item.isDirectory { await push(item.url) }
        inspecting = item
    }

    // MARK: - Búsqueda

    /// Caché del último filtrado. Evita recorrer la carpeta entera en cada
    /// recomposición de SwiftUI, que ocurre muchas veces por pulsación.
    private var searchCache: (query: String, level: UUID, count: Int, result: [FileItem])?

    /// Archivos que la vista debe pintar en ese nivel: todos, o los que
    /// coincidan con el buscador.
    func visibleItems(at index: Int) -> [FileItem] {
        guard let level = levels[safe: index] else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return level.items }

        // la clave incluye el número de archivos: si la carpeta cambia en
        // disco, el filtro se recalcula solo
        if let cache = searchCache, cache.query == query,
           cache.level == level.id, cache.count == level.items.count {
            return cache.result
        }
        // sin distinguir mayúsculas ni tildes, como la búsqueda del Finder
        let result = level.items.filter {
            $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        searchCache = (query, level.id, level.items.count, result)
        return result
    }

    // MARK: - Navegación con las flechas del teclado

    enum MoveDirection { case up, down, left, right }

    /// Mueve la selección con las flechas, respetando el filtro del buscador.
    ///
    /// - Parameter columns: columnas visibles (1 en lista y en la vista de
    ///   columnas; las de la rejilla en la vista de iconos), para que arriba y
    ///   abajo salten una fila completa en lugar de un archivo.
    func moveSelection(_ direction: MoveDirection, columns: Int = 1) async {
        guard let index = levels.indices.last else { return }
        let items = visibleItems(at: index)
        guard !items.isEmpty else { return }

        let current = items.firstIndex { levels[index].selection.contains($0.id) }

        // en vistas de una sola columna, izquierda y derecha navegan carpetas
        if columns <= 1 {
            switch direction {
            case .left:
                await goUp()
                return
            case .right:
                if let i = current, items[i].isDirectory { await select(items[i], at: index) }
                return
            default: break
            }
        }

        let step: Int
        switch direction {
        case .up: step = -columns
        case .down: step = columns
        case .left: step = -1
        case .right: step = 1
        }
        // sin nada seleccionado, la primera flecha entra por el principio
        let target = min(max((current ?? -1) + step, 0), items.count - 1)
        await select(items[target], at: index)
    }

    /// Enter: abre lo seleccionado (carpeta → entrar, archivo → app externa).
    func openSelection() async {
        guard let item = selectedItems.first else { return }
        if item.isDirectory {
            await open(item.url)
        } else {
            await openInDefaultApp(item)
        }
    }

    func goUp() async {
        guard levels.count > 1 else {
            if let parent = currentURL?.deletingLastPathComponent(),
               parent.path != currentURL?.path {
                await open(parent)
            }
            return
        }
        levels.removeLast()
        levels[levels.count - 1].selection = []
    }

    func reload() async {
        guard let url = currentURL else { return }
        await load(url, appending: false)
    }

    /// Las carpetas del sandbox se listan directo; las de proveedores externos
    /// (OneDrive, Drive, SMB por Tailscale) pasan por el manejador con
    /// coordinación y plazo máximo.
    private func isExternal(_ url: URL) -> Bool {
        !url.path.hasPrefix(FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask)[0].path)
    }

    private func load(_ url: URL, appending: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let items = isExternal(url)
                ? try await CloudFileHandler.shared.list(url, showHidden: showHidden)
                : try await FileService.shared.list(url, showHidden: showHidden)
            let sorted = sort(items)
            if appending {
                levels.append(DirectoryLevel(url: url, items: sorted))
            } else if !levels.isEmpty {
                levels[levels.count - 1].items = sorted
            }
            // si acabamos de crear algo, queda seleccionado al recargar
            if let name = pendingSelection, let index = levels.indices.last,
               let created = levels[index].items.first(where: { $0.name == name }) {
                levels[index].selection = [created.id]
                inspecting = created
                pendingSelection = nil
            }
            watch(url)
        } catch {
            self.error = "No pude abrir \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func sort(_ items: [FileItem]) -> [FileItem] {
        items.sorted { a, b in
            // las carpetas primero, como en el Finder
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch sortKey {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .size: return a.size > b.size
            case .date: return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
            case .kind: return a.kindLabel.localizedStandardCompare(b.kindLabel) == .orderedAscending
            }
        }
    }

    func applySort(_ key: SortKey) {
        sortKey = key
        for index in levels.indices { levels[index].items = sort(levels[index].items) }
    }

    // MARK: - Sincronización con el disco

    /// Observa la carpeta abierta: si otro proceso (o el propio iPad) crea,
    /// borra o renombra algo, la vista se refresca sola.
    private func watch(_ url: URL) {
        watcher?.cancel()
        if watchedDescriptor >= 0 { close(watchedDescriptor) }
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        watchedDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in await self?.reload() }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watchedDescriptor, fd >= 0 { close(fd) }
            self?.watchedDescriptor = -1
        }
        source.resume()
        watcher = source
    }

    deinit {
        watcher?.cancel()
    }

    // MARK: - Operaciones (todas asíncronas)

    func newFolder() async {
        guard let url = currentURL else { return }
        await run { try await FileService.shared.createFolder(in: url, named: "carpeta sin título") }
    }

    // MARK: - Archivo nuevo en blanco

    /// Muestra la alerta para escribir el nombre.
    func beginNewFile() {
        newFileName = ""
        creatingFile = true
    }

    /// Crea el archivo vacío y deja la vista lista para trabajar con él.
    ///
    /// No hace falta recargar a mano: `run` llama a `reload()` en cuanto la
    /// operación termina, así que el archivo aparece en la rejilla al
    /// instante. (El observador de `DispatchSource` también lo detectaría,
    /// pero con retardo; recargar aquí lo hace inmediato.)
    func createFile() async {
        guard let directory = currentURL else { return }
        let name = newFileName
        creatingFile = false

        await run {
            let created = try await FileService.shared.createFile(in: directory, named: name)
            // se selecciona lo recién creado, como hace el Finder
            await MainActor.run { self.pendingSelection = created.lastPathComponent }
        }
    }

    func copySelection() {
        clipboard = selectedItems.map(\.url)
        clipboardIsCut = false
    }

    func cutSelection() {
        clipboard = selectedItems.map(\.url)
        clipboardIsCut = true
    }

    func paste() async {
        guard let url = currentURL, !clipboard.isEmpty else { return }
        let sources = clipboard
        let cut = clipboardIsCut
        await run {
            if cut {
                try await FileService.shared.move(sources, to: url)
            } else {
                try await FileService.shared.copy(sources, to: url)
            }
        }
        if cut { clipboard = [] }
    }

    func duplicateSelection() async {
        let urls = selectedItems.map(\.url)
        await run { try await FileService.shared.duplicate(urls) }
    }

    func deleteSelection() async {
        let urls = selectedItems.map(\.url)
        await run { try await FileService.shared.delete(urls) }
    }

    func compressSelection() async {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        await run { _ = try await FileService.shared.compress(urls) }
    }

    func beginRename(_ item: FileItem) {
        renaming = item
        renameText = item.name
    }

    func commitRename() async {
        guard let item = renaming else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty, name != item.name else { return }
        await run { _ = try await FileService.shared.rename(item.url, to: name) }
    }

    /// Recibe elementos arrastrados desde otra app o desde otra carpeta.
    func receive(_ urls: [URL], into directory: URL, move: Bool) async {
        await run {
            if move {
                try await FileService.shared.move(urls, to: directory)
            } else {
                try await FileService.shared.copy(urls, to: directory)
            }
        }
    }

    /// Señal para que la vista abra la ventana de previsualización.
    @Published var previewRequest: FileItem?
    /// Archivo que se abrirá en otra app (doble clic, como en macOS)
    @Published var openingExternally: String?

    /// Abre el archivo. Si vive en la nube, lo descarga antes mostrando
    /// el progreso, en vez de abrir un fichero vacío.
    func quickLook(_ item: FileItem? = nil) {
        guard let item = item ?? selectedItems.first, !item.isDirectory else { return }
        guard item.isRemoteOnly || item.isDownloading else {
            previewRequest = item
            return
        }
        Task {
            downloadingName = item.name
            defer { downloadingName = nil }
            do {
                try await CloudFileHandler.shared.materialize(item.url)
                previewRequest = item
                await reload()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Doble clic: entrega el archivo a la app que lo abre.
    func openInDefaultApp(_ item: FileItem) async {
        await handOff(item) { _, copy in SystemOpen.shared.openInApp(copy) }
    }

    /// Doble toque con tres dedos: menú completo de opciones del sistema.
    func chooseAppFor(_ item: FileItem) async {
        await handOff(item) { _, copy in SystemOpen.shared.presentOptions(copy) }
    }

    /// Prepara el archivo y se lo cede a otra app.
    ///
    /// El destino es otro proceso, que no hereda nuestros permisos: por eso
    /// siempre se le entrega una copia en el contenedor propio, además de la
    /// ruta original (que sí sirve para la cesión vía app Archivos).
    private func handOff(_ item: FileItem,
                         _ deliver: (URL, URL) -> Void) async {
        guard !item.isDirectory else { return }
        openingExternally = item.name
        defer { openingExternally = nil }
        do {
            if !ICloudAvailability.isUsable(item.url) {
                try await CloudFileHandler.shared.materialize(item.url)
            }
            let data = try await CloudFileHandler.shared.read(item.url)
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(item.name)
            try data.write(to: copy, options: .atomic)
            deliver(item.url, copy)
        } catch {
            self.error = "No se pudo abrir \(item.name): \(error.localizedDescription)"
        }
    }

    /// Envoltura común: marca ocupado, captura errores y recarga al terminar.
    private func run(_ work: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
