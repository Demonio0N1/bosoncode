import SwiftUI
import Combine
import QuickLook

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
    /// Vista elegida, recordada entre sesiones.
    ///
    /// Antes volvía a columnas en cada arranque. Es una preferencia, no un
    /// estado pasajero: quien trabaja en iconos no quiere reelegirlo cada vez
    /// que abre la app, igual que el Finder recuerda la suya.
    @Published var viewMode: ViewMode = ViewMode(rawValue:
        UserDefaults.standard.string(forKey: "finderViewMode") ?? "") ?? .columns {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "finderViewMode") }
    }
    @Published var showHidden = false
    @Published var sortKey: SortKey = .name
    /// Operaciones en curso. Es un contador y no un booleano porque dos
    /// tareas solapadas se pisaban: la primera en terminar apagaba el
    /// indicador aunque la otra siguiera.
    @Published private(set) var busy = false
    private var busyCount = 0 {
        didSet { busy = busyCount > 0 }
    }
    /// Red de seguridad: si algo no vuelve nunca —un proveedor que no
    /// responde—, el indicador no se queda girando para siempre.
    private var busyWatchdog: Task<Void, Never>?

    private func beginWork() {
        busyCount += 1
        busyWatchdog?.cancel()
        busyWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.busyCount = 0 }
        }
    }

    private func endWork() {
        busyCount = max(0, busyCount - 1)
        if busyCount == 0 { busyWatchdog?.cancel(); busyWatchdog = nil }
    }
    @Published var error: String?
    /// Carpeta que falló por permiso: la alerta ofrece volver a concederla.
    @Published var regrantTarget: URL?
    @Published var renaming: FileItem?
    @Published var renameText = ""
    @Published var inspecting: FileItem?
    /// El usuario pidió ver la información: hay que enseñarla aunque el panel
    /// estuviera oculto o la ventana sea estrecha.
    @Published var infoRequest: FileItem?

    /// "Obtener información" del menú.
    ///
    /// Abre SIEMPRE la ficha, en cualquier tamaño de ventana.
    ///
    /// Antes intentaba ser listo: encender el panel lateral si cabía y recurrir
    /// a la hoja solo si no. El problema es que cuando el panel ya estaba a la
    /// vista mostrando ese mismo archivo, no había nada que cambiar — y desde
    /// fuera eso es indistinguible de un botón roto.
    ///
    /// Una opción de menú debe hacer algo observable siempre que se toca. Se
    /// prefiere una conducta predecible, aunque a veces sea redundante con el
    /// panel, a una que depende de un estado que no se ve.
    func showInfo(_ item: FileItem) {
        inspecting = item
        infoRequest = item
    }
    /// Archivo que debe abrirse en una VENTANA de edición propia.
    ///
    /// El modelo no abre ventanas —no tiene acceso a `openWindow`, que es del
    /// entorno de la vista—: publica la intención y la ventana la abre quien sí
    /// puede. Es el mismo reparto que ya usa la vista previa.
    @Published var editing: FileItem?
    /// Imagen abierta en el editor de dibujo
    @Published var drawingOn: FileItem?
    /// Receta del atajo, cuando hay que explicarla
    @Published var shortcutHelp: String?
    /// Nombre del atajo que abre documentos de Office
    @AppStorage("officeShortcutName") var officeShortcut = ShortcutBridge.defaultName

    /// Deja el documento donde Archivos lo ve y abre Archivos ahí.
    ///
    /// Es el camino más corto al comportamiento que se busca: Archivos sí abre
    /// un .docx en Word directamente, porque tiene permisos que ninguna app de
    /// terceros recibe. Desde aquí se llega en dos toques en vez de uno, pero es
    /// el de verdad y no una imitación.
    func revealInFiles(_ item: FileItem) async {
        downloadingName = item.name
        defer { downloadingName = nil }
        do {
            try await RevealInFiles.reveal(item.url)
        } catch {
            self.error = Self.cloudFailure(item, error)
        }
    }

    /// Manda el documento a Atajos para que lo abra en Word, Excel o
    /// PowerPoint — el único camino que evita el menú de compartir.
    func openWithShortcut(_ item: FileItem) async {
        downloadingName = item.name          // puede estar en la nube
        defer { downloadingName = nil }
        do {
            try await ShortcutBridge.open(item.url, shortcut: officeShortcut)
        } catch {
            // El fallo más probable no es este error, sino que el atajo no
            // exista todavía: Atajos abre y avisa él. Por eso se ofrece la
            // receta en lugar de un mensaje seco.
            shortcutHelp = "\(error.localizedDescription)\n\n\(ShortcutBridge.recipe)"
        }
    }

    /// Deja la imagen como fondo de la ventana de archivos.
    func useAsWallpaper(_ item: FileItem) async {
        downloadingName = item.name        // puede estar en la nube
        defer { downloadingName = nil }
        do {
            try await Wallpaper.shared.set(from: item.url)
        } catch {
            self.error = Self.cloudFailure(item, error)
        }
    }
    /// Nombre del archivo que se está enviando al equipo
    @Published var sendingToBoson: String?

    /// Archivo a la espera de que se elija dónde ejecutarlo
    @Published var runTarget: FileItem?

    /// Sube el archivo al equipo elegido y lo abre en BosonCode.
    func runInBosonCode(_ item: FileItem, on server: Server?) async {
        sendingToBoson = item.name
        defer { sendingToBoson = nil }
        do {
            _ = try await RunInBosonCode.run(item.url, on: server)
        } catch {
            self.error = error.localizedDescription
        }
    }
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

    /// Lo seleccionado, esté en el nivel que esté.
    ///
    /// Antes miraba solo `levels.last`, y eso fallaba justo con las CARPETAS:
    /// seleccionar una entra dentro, lo que añade un nivel nuevo y vacío. La
    /// selección se quedaba en el nivel anterior mientras esto leía el último,
    /// así que devolvía una lista vacía — y renombrar, eliminar, copiar o
    /// comprimir una carpeta no hacían nada.
    var selectedItems: [FileItem] {
        for level in levels.reversed() where !level.selection.isEmpty {
            return level.items.filter { level.selection.contains($0.id) }
        }
        return []
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

    /// ⌘O: abre lo seleccionado con la misma regla que el doble clic.
    func openSelection() async {
        guard let item = selectedItems.first, let level = levels.indices.last else { return }
        await openDoubleClick(item, at: level)
    }

    /// ¿Queda algún nivel al que subir?
    ///
    /// Dentro de lo ya abierto, siempre. Por encima de la raíz que concedió el
    /// usuario, no: ahí el sistema deniega el permiso y la app se quedaba en
    /// una carpeta que no podía listar, sin forma evidente de volver — que es
    /// lo que pasaba pulsando "atrás" varias veces seguidas.
    var canGoUp: Bool {
        if levels.count > 1 { return true }
        guard let current = currentURL else { return false }
        let parent = current.deletingLastPathComponent()
        guard parent.path != current.path else { return false }
        return Self.isGranted(parent)
    }

    /// ¿Tenemos permiso para listar esta ruta?
    ///
    /// Vale el contenedor propio de la app —siempre accesible— y cualquier
    /// descendiente de una raíz que el usuario haya concedido con el selector.
    static func isGranted(_ url: URL) -> Bool {
        let documents = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask)[0]
        if url.path == documents.path || url.path.hasPrefix(documents.path + "/") {
            return true
        }
        return CloudFileHandler.root(containing: url) != nil
    }

    func goUp() async {
        guard levels.count > 1 else {
            guard canGoUp, let parent = currentURL?.deletingLastPathComponent() else { return }
            await open(parent)
            return
        }
        levels.removeLast()
        levels[levels.count - 1].selection = []
    }

    /// Refresca TODAS las columnas abiertas, no solo la última.
    ///
    /// Aquí estaba el "no funciona" de duplicar, comprimir y renombrar: sí
    /// funcionaban —el archivo aparecía en el disco— pero el resultado cae
    /// junto al elemento, o sea en su carpeta PADRE, y esta recarga solo miraba
    /// la carpeta abierta. Al operar sobre una carpeta desde dentro de ella,
    /// que es lo natural en la vista de columnas, el cambio ocurría en una
    /// columna que nadie volvía a leer. Parecía que el botón no hacía nada.
    func reload() async {
        guard !levels.isEmpty else { return }
        for index in levels.indices {
            let url = levels[index].url
            let items = await listing(of: url)
            guard let items, levels.indices.contains(index) else { continue }
            levels[index].items = sort(items)
            // lo que ya no existe deja de estar seleccionado
            let vivos = Set(levels[index].items.map(\.id))
            levels[index].selection.formIntersection(vivos)
        }
        if let index = levels.indices.last, let name = pendingSelection,
           let creado = levels[index].items.first(where: { $0.name == name }) {
            levels[index].selection = [creado.id]
            inspecting = creado
            pendingSelection = nil
        }
        if let url = currentURL { watch(url) }
    }

    /// Lista una carpeta por el camino que le corresponda, o nil si falla.
    private func listing(of url: URL) async -> [FileItem]? {
        do {
            return isExternal(url)
                ? try await CloudFileHandler.shared.list(url, showHidden: showHidden)
                : try await FileService.shared.list(url, showHidden: showHidden)
        } catch {
            return nil        // una columna que ya no se puede leer se deja como está
        }
    }

    /// Las carpetas del sandbox se listan directo; las de proveedores externos
    /// (OneDrive, Drive, SMB por Tailscale) pasan por el manejador con
    /// coordinación y plazo máximo.
    private func isExternal(_ url: URL) -> Bool {
        !url.path.hasPrefix(FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask)[0].path)
    }

    private func load(_ url: URL, appending: Bool) async {
        beginWork()
        defer { endWork() }
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
            // Sin permiso no basta con decirlo: hay que ofrecer la salida. Se
            // guarda la carpeta para que la alerta pueda proponer elegirla de
            // nuevo en el selector, que es lo único que devuelve el acceso.
            if !Self.isGranted(url) { self.regrantTarget = url }
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
        watcher?.cancel()          // su manejador cierra su propio descriptor
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
        // OJO: se captura ESTE descriptor por valor. Leerlo de la propiedad
        // era un fallo real: cancel() es asíncrono, así que para cuando el
        // manejador corría, watchedDescriptor ya apuntaba al descriptor NUEVO
        // y lo cerraba. Resultado: el observador quedaba mirando un descriptor
        // cerrado —la carpeta dejaba de refrescarse sola— y ese número podía
        // reutilizarse para otro archivo, que quedaba cerrado por sorpresa.
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    deinit {
        watcher?.cancel()
    }

    // MARK: - Operaciones (todas asíncronas)

    func newFolder() async {
        guard let url = currentURL else { return }
        await run {
            let created = try await FileService.shared.createFolder(in: url,
                                                                    named: "carpeta sin título")
            // como al crear un archivo: queda seleccionada y lista para
            // renombrar con Intro
            await MainActor.run { self.pendingSelection = created.lastPathComponent }
        }
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

    /// Pega en la carpeta abierta. Lo usan los atajos de teclado.
    ///
    /// Delega en la versión con destino: dos copias de la misma lógica acaban
    /// separándose, y este es el tipo de código en el que eso no se nota hasta
    /// que una de las dos deja de hacer lo que la otra sí.
    func paste() async {
        await paste(into: nil)
    }

    func duplicateSelection() async {
        let urls = selectedItems.map(\.url)
        await run { try await FileService.shared.duplicate(urls) }
    }

    // MARK: - Operaciones sobre un objetivo explícito
    //
    // El menú contextual las usa con lo que tiene delante. Las versiones
    // "…Selection" siguen existiendo para los atajos de teclado, que sí actúan
    // sobre la selección, y delegan aquí.

    func delete(_ items: [FileItem]) async {
        let urls = items.map(\.url)
        guard !urls.isEmpty else { return }
        await run { _ = try await Trash.shared.move(urls) }
        trashCount = await (try? Trash.shared.contents().count) ?? 0
    }

    func copy(_ items: [FileItem]) {
        clipboard = items.map(\.url)
        clipboardIsCut = false
    }

    func cut(_ items: [FileItem]) {
        clipboard = items.map(\.url)
        clipboardIsCut = true
    }

    func duplicate(_ items: [FileItem]) async {
        guard !items.isEmpty else { return }
        await run { try await FileService.shared.duplicate(items.map(\.url)) }
    }

    func compress(_ items: [FileItem]) async {
        guard !items.isEmpty else { return }
        await run { _ = try await FileService.shared.compress(items.map(\.url)) }
    }

    /// Pega en la carpeta indicada; sin indicar ninguna, en la abierta.
    ///
    /// Pegar desde el menú de una CARPETA debe meter las cosas ahí dentro, que
    /// es lo que uno espera al pulsar sobre ella — no en la carpeta que estabas
    /// mirando.
    func paste(into folder: URL?) async {
        guard let destination = folder ?? currentURL, !clipboard.isEmpty else { return }
        let sources = clipboard
        let cut = clipboardIsCut
        await run {
            if cut {
                try await FileService.shared.move(sources, to: destination)
            } else {
                try await FileService.shared.copy(sources, to: destination)
            }
        }
        if cut { clipboard = [] }
    }

    /// Mueve lo seleccionado a la papelera de ZeroSpin (no borra de golpe).
    func deleteSelection() async {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        await run { _ = try await Trash.shared.move(urls) }
        trashCount = await (try? Trash.shared.contents().count) ?? 0
    }

    /// Borrado definitivo, saltándose la papelera. Va en el menú aparte y con
    /// confirmación: es la única acción de la app sin vuelta atrás.
    func deleteForever() async {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        await run { try await FileService.shared.delete(urls) }
    }

    /// Cuántos elementos hay en la papelera (para la barra lateral).
    @Published var trashCount = 0

    func refreshTrashCount() async {
        trashCount = (try? await Trash.shared.contents().count) ?? 0
    }

    func compressSelection() async {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        await run { _ = try await FileService.shared.compress(urls) }
    }

    /// Archivo que se está renombrando, aparte de `renaming`.
    ///
    /// `renaming` gobierna si la alerta está en pantalla, y SwiftUI lo pone a
    /// nil al cerrarla. Eso ocurre ANTES de que corra la tarea del botón, así
    /// que confirmar encontraba nil y salía sin renombrar nada: la alerta se
    /// cerraba y no pasaba nada. Este otro no lo toca la presentación.
    @Published private var renameTarget: FileItem?

    func beginRename(_ item: FileItem) {
        renaming = item
        renameTarget = item
        // El nombre REAL, con su extensión, y no el de pantalla.
        //
        // `item.name` es el nombre localizado, del que el sistema quita la
        // extensión de los tipos que conoce: renombrar "Léeme.txt" partía de
        // "Léeme" y, al confirmar, el archivo se quedaba sin .txt.
        renameText = item.url.lastPathComponent
    }

    func commitRename() async {
        guard let item = renameTarget else { return }
        renameTarget = nil
        renaming = nil
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        // se compara con el nombre real, que es de donde partió el campo
        guard !name.isEmpty, name != item.url.lastPathComponent else { return }
        await run { _ = try await FileService.shared.rename(item.url, to: name) }
    }

    /// Cancelar debe olvidar el objetivo; si no, quedaría vivo para la próxima.
    func cancelRename() {
        renameTarget = nil
        renaming = nil
    }

    /// Recibe elementos arrastrados desde otra app o desde otra carpeta.
    func receive(_ urls: [URL], into directory: URL, move: Bool) async {
        await run {
            // Un arrastre desde el editor remoto no trae un archivo: trae una
            // URL vscode-remote://, que FileManager no sabe abrir ("URL type
            // vscode-remote isn't supported"). Hay que traerse el contenido
            // por la API del equipo antes de tocar el disco.
            var local: [URL] = []
            for url in urls {
                if url.isFileURL {
                    local.append(url)
                } else {
                    local.append(try await RemoteDrop.materialize(url))
                }
            }
            guard !local.isEmpty else { return }
            // lo traído de fuera se copia siempre: "mover" borraría el
            // temporal, no el archivo del equipo
            let onlyRemote = local.allSatisfy { $0.path.hasPrefix(FileManager.default.temporaryDirectory.path) }
            if move && !onlyRemote {
                try await FileService.shared.move(local, to: directory)
            } else {
                try await FileService.shared.copy(local, to: directory)
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
                self.error = Self.cloudFailure(item, error)
            }
        }
    }

    // MARK: - Contenido bajo demanda (Drive, OneDrive, iCloud)

    /// Baja el archivo al iPad sin abrirlo.
    func downloadNow(_ item: FileItem) async {
        downloadingName = item.name
        defer { downloadingName = nil }
        do {
            try await CloudFileHandler.shared.materialize(item.url)
            await reload()
        } catch {
            self.error = Self.cloudFailure(item, error)
        }
    }

    /// Lo devuelve a la nube y recupera el espacio.
    func freeUpSpace(_ item: FileItem) async {
        await run { try await CloudFileHandler.shared.evict(item.url) }
    }

    /// Doble clic: abre, y **sin enseñar ningún menú**.
    ///
    /// iPadOS no permite lanzar un archivo en "su app por defecto" sin pasar
    /// por la lista de apps (no existe esa asociación en el sistema). Para que
    /// el doble clic sea limpio se usa el visor propio, que abre al instante y
    /// entiende casi todo: texto, código, PDF, imágenes, vídeo, audio, Office,
    /// iWork y ZIP. Solo cuando ni siquiera él puede con el archivo se recurre
    /// a entregárselo a otra app, que sí implica elegirla.
    ///
    /// Ceder el archivo a Word o Excel sigue estando a un gesto: menú
    /// contextual → "Abrir en otra app…".
    func openDoubleClick(_ item: FileItem, at level: Int) async {
        if item.isDirectory {
            await select(item, at: level)
            return
        }
        // Primero lo que ZeroSpin sabe enseñar por su cuenta. Quick Look dice
        // que NO puede con un .ipynb —no conoce el tipo— y sin esta comprobación
        // el doble clic caía en la lista de apps en vez de abrir el visor.
        switch DocumentKind.of(item.url) {
        case .notebook, .code:
            // Los dos van a una ventana propia, y allí cada uno abre con lo
            // suyo: el notebook renderizado —celdas, Markdown y salidas— y el
            // script en el editor. Repartirlo en la ventana y no aquí evita que
            // este enrutado tenga que conocer los visores.
            editing = item
        case .office:
            await openOffice(item)
        case .other:
            if QLPreviewController.canPreview(item.url as NSURL) {
                quickLook(item)
            } else {
                await openInDefaultApp(item)
            }
        }
    }

    /// Word, Excel y PowerPoint: se abren aquí dentro, sin preguntar nada.
    ///
    /// Lo deseable sería lanzarlos directamente en su app, como hace Archivos.
    /// No se puede, y conviene que quede escrito para no volver a intentarlo:
    ///
    ///  · `NSWorkspace` es de macOS; en iPadOS no existe.
    ///  · `UIApplication.open` con una URL `file://` devuelve `false`. iPadOS
    ///    no guarda asociaciones tipo → app como macOS, así que no hay ninguna
    ///    "app por defecto" que consultar.
    ///  · `UIDocumentInteractionController` es lo único que entrega el archivo
    ///    a otra app, y su forma de hacerlo ES el menú de apps. No hay variante
    ///    silenciosa ni manera de saber qué apps lo aceptarían para saltárselo.
    ///  · Archivos lo consigue porque es `UIDocumentBrowserViewController`, un
    ///    componente del sistema con permisos que una app de terceros no tiene
    ///    para archivos cualesquiera.
    ///
    /// Entre un diálogo que nadie pidió y abrir de una vez, se abre de una vez.
    /// La vista previa lleva un botón para pasar a Word cuando haga falta
    /// editar de verdad, así que la ruta sigue estando a un toque.
    private func openOffice(_ item: FileItem) async {
        previewRequest = item
    }

    /// Entrega el archivo a otra app (Word, Excel…). Muestra la lista de apps
    /// compatibles porque el sistema no expone ninguna otra vía.
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
                // El nombre REAL del archivo, con su extensión.
                //
                // Aquí estaba el fallo: `item.name` es el nombre de PANTALLA
                // —`localizedName`—, y el sistema oculta la extensión en él.
                // La copia salía como "Doc2" en vez de "Doc2.docx", y sin
                // extensión no hay tipo que deducir: ninguna app declaraba poder
                // abrirla, así que "Abrir con…" salía vacío y la hoja de
                // compartir decía "File" en lugar de "Documento de Word".
                .appendingPathComponent(item.url.lastPathComponent)
            try data.write(to: copy, options: .atomic)
            deliver(item.url, copy)
        } catch {
            self.error = Self.cloudFailure(item, error)
        }
    }

    /// Traduce el fallo al abrir un archivo que vive en la nube.
    ///
    /// El sistema devuelve aquí cosas como "Your device couldn't connect to the
    /// server", que no dice ni qué archivo, ni de qué servicio, ni qué hacer.
    /// El dato que falta y que lo explica todo es que el archivo **no está en
    /// el iPad**: solo figura en el listado, y traerlo depende del proveedor.
    static func cloudFailure(_ item: FileItem, _ error: Error) -> String {
        let service = CloudProvider.detect(item.url)
        let origin = service == .folder ? "la nube" : service.title
        guard item.isRemoteOnly || item.isDownloading else {
            // el archivo sí estaba en el iPad: el fallo es otra cosa
            return "No se pudo abrir \(item.name): \(error.localizedDescription)"
        }
        return """
        No pude traer «\(item.name)» desde \(origin).

        El archivo está en la nube, no en el iPad, y \(origin) no lo entregó. \
        Comprueba la conexión, o ábrelo una vez desde la app Archivos para \
        forzar su descarga y vuelve aquí.

        (\(error.localizedDescription))
        """
    }

    /// Envoltura común: marca ocupado, captura errores y recarga al terminar.
    private func run(_ work: @escaping () async throws -> Void) async {
        beginWork()
        defer { endWork() }
        do {
            try await work()
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
