import SwiftUI

// MARK: - Puente entre los menús y la ventana activa

/// Lo que los menús necesitan de la ventana que tiene el foco.
///
/// El problema de fondo: `.commands` se declara en el `App`, **fuera** de
/// cualquier escena, así que no puede alcanzar el `@StateObject` de una
/// ventana concreta — y con varias ventanas abiertas, "la carpeta actual" es
/// distinta en cada una. La solución de SwiftUI es el foco: cada ventana
/// publica su estado con `.focusedSceneValue`, y los menús lo leen con
/// `@FocusedValue`. Cuando el usuario cambia de ventana, los menús pasan a
/// operar sobre la nueva sin que nadie sincronice nada.
///
/// Se pasan también dos cierres porque abrir y cerrar ventanas depende del
/// entorno de la escena (`openWindow`), que solo existe dentro de la vista.
struct FinderActions: Equatable {
    let model: BrowserViewModel
    let newWindow: () -> Void
    let closeWindow: () -> Void

    /// Identidad: dos acciones son la misma si vienen de la misma ventana.
    static func == (a: FinderActions, b: FinderActions) -> Bool { a.model === b.model }
}

private struct FinderActionsKey: FocusedValueKey {
    typealias Value = FinderActions
}

/// Cómo se cierra la ventana que tiene el foco, sea del tipo que sea.
///
/// Hace falta porque ⌘W lo reclama el menú, que vive en la app y no en una
/// escena. Con solo `FinderActions`, en una ventana de vista previa ese valor
/// era nulo, la entrada quedaba desactivada… y **se tragaba la pulsación**:
/// el atajo de la propia ventana no llegaba a ejecutarse. Publicando la acción
/// desde ambas, ⌘W cierra siempre la ventana correcta.
struct WindowCloseAction {
    let id: String
    let close: () -> Void
}

private struct WindowCloseKey: FocusedValueKey {
    typealias Value = WindowCloseAction
}

extension FocusedValues {
    var finder: FinderActions? {
        get { self[FinderActionsKey.self] }
        set { self[FinderActionsKey.self] = newValue }
    }

    var windowClose: WindowCloseAction? {
        get { self[WindowCloseKey.self] }
        set { self[WindowCloseKey.self] = newValue }
    }
}

// MARK: - Menús de la barra superior

/// Barra de menús al estilo del Finder.
///
/// `CommandMenu` crea un menú nuevo; `CommandGroup` se engancha a uno que el
/// sistema ya pone (Archivo, Edición, Ver, Ventana, Ayuda) para añadir o
/// reemplazar entradas en el sitio correcto.
struct FinderCommands: Commands {
    /// Nulo si ninguna ventana del explorador tiene el foco: entonces las
    /// entradas se ven en gris, como debe ser.
    @FocusedValue(\.finder) private var finder
    @FocusedValue(\.windowClose) private var windowClose

    private var model: BrowserViewModel? { finder?.model }
    private var hasSelection: Bool { !(model?.selectedItems.isEmpty ?? true) }

    var body: some Commands {
        // MARK: Archivo
        CommandGroup(replacing: .newItem) {
            Button("Nueva ventana") { finder?.newWindow() }
                .keyboardShortcut("n", modifiers: .command)

            Button("Nueva carpeta") { run { await $0.newFolder() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model?.currentURL == nil)

            Button("Nuevo archivo…") { model?.beginNewFile() }
                .keyboardShortcut("n", modifiers: [.command, .control])
                .disabled(model?.currentURL == nil)

            Divider()

            Button("Abrir") { run { await $0.openSelection() } }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!hasSelection)

            Button("Vista rápida") {
                if let item = model?.selectedItems.first { model?.quickLook(item) }
            }
            .keyboardShortcut("y", modifiers: .command)
            .disabled(!hasSelection)
        }

        CommandGroup(replacing: .saveItem) {
            // cierra la ventana enfocada: explorador, vista previa, la que sea
            Button("Cerrar ventana") {
                if let windowClose { windowClose.close() } else { finder?.closeWindow() }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(windowClose == nil && finder == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("Obtener información") { model?.inspecting = model?.selectedItems.first }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!hasSelection)

            Button("Comprimir") { run { await $0.compressSelection() } }
                .disabled(!hasSelection)

            Button("Descomprimir") {
                if let items = model?.selectedItems { run { await $0.decompress(items) } }
            }
            .disabled(!(model?.selectedItems.contains { BrowserViewModel.isArchive($0.url) } ?? false))

            Divider()

            Button("Mover a la papelera") { run { await $0.deleteSelection() } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!hasSelection)
        }

        // MARK: Edición
        CommandGroup(replacing: .pasteboard) {
            Button("Copiar") { model?.copySelection() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(!hasSelection)

            Button("Cortar") { model?.cutSelection() }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(!hasSelection)

            Button("Pegar") { run { await $0.paste() } }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!(model?.canPaste ?? false))

            Button("Duplicar") { run { await $0.duplicateSelection() } }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!hasSelection)

            Divider()

            Button("Renombrar") {
                if let item = model?.selectedItems.first { model?.beginRename(item) }
            }
            .disabled(!hasSelection)
        }

        // MARK: Ver
        CommandMenu("Ver") {
            Picker("Modo", selection: Binding(
                get: { model?.viewMode ?? .columns },
                set: { model?.viewMode = $0 }
            )) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button(model?.showHidden == true ? "Ocultar archivos ocultos"
                                             : "Mostrar archivos ocultos") {
                model?.showHidden.toggle()
                run { await $0.reload() }
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Button("Actualizar") { run { await $0.reload() } }
                .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Subir un nivel") { run { await $0.goUp() } }
                .keyboardShortcut(.upArrow, modifiers: .command)
        }

        // MARK: Ayuda
        CommandGroup(replacing: .help) {
            Button("Atajos de ZeroSpin") { model?.error = Self.shortcutSheet }
        }
    }

    /// Los menús son síncronos y el ViewModel es asíncrono y de hilo
    /// principal: este puente evita repetir `Task { @MainActor in … }`.
    private func run(_ work: @escaping (BrowserViewModel) async -> Void) {
        guard let model else { return }
        Task { @MainActor in await work(model) }
    }

    private static let shortcutSheet = """
    ⌘N ventana nueva · ⇧⌘N carpeta · ⌃⌘N archivo
    ⌘O abrir · espacio vista rápida · ⌘I información
    ⌘C copiar · ⌘X cortar · ⌘V pegar · ⌘D duplicar
    ⌘⌫ eliminar · Intro renombrar · ⇧⌘. archivos ocultos
    Flechas para moverse · ⌘↑ subir de carpeta
    """
}
