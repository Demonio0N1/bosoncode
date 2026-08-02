import SwiftUI
import UniformTypeIdentifiers

// MARK: - Menú contextual compartido

/// Menú de clic derecho (trackpad) o pulsación larga, con las acciones reales
/// del Finder.
struct FileContextMenu: ViewModifier {
    @ObservedObject var model: BrowserViewModel
    let item: FileItem
    let level: Int

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { Task { await model.openDoubleClick(item, at: level) } } label: {
                Label("Abrir", systemImage: "arrow.up.forward.app")
            }
            Button { Task { await model.openInDefaultApp(item) } } label: {
                Label("Abrir en otra app…", systemImage: "arrow.up.forward.square")
            }
            Button { model.quickLook(item) } label: {
                Label("Vista rápida (espacio)", systemImage: "eye")
            }
            if CodeHighlighter.isCode(item.url), !item.isDirectory {
                Button { model.editing = item } label: {
                    Label("Editar", systemImage: "pencil.and.outline")
                }
            }
            // Word, Excel y PowerPoint: se delega en Atajos, que sí puede
            // lanzarlos sin pasar por el menú de compartir.
            if case .office = DocumentKind.of(item.url) {
                Button { Task { await model.revealInFiles(item) } } label: {
                    Label("Abrir con Archivos → Word", systemImage: "folder.badge.gearshape")
                }
                Button { Task { await model.openWithShortcut(item) } } label: {
                    Label("Abrir en Office (Atajos)", systemImage: "wand.and.stars")
                }
            }
            // Acciones propias de una imagen. Solo aparecen si lo es: un menú
            // que ofrece "Editar imagen" sobre un PDF enseña a desconfiar de él.
            if item.isImage {
                Button { model.drawingOn = item } label: {
                    Label("Editar imagen (dibujar)", systemImage: "scribble.variable")
                }
                Button { Task { await model.useAsWallpaper(item) } } label: {
                    Label("Usar como fondo de ZeroSpin", systemImage: "photo.on.rectangle")
                }
            }
            // Notebooks y scripts: ejecutar significa mandarlo al equipo, que
            // es donde vive el intérprete.
            if !item.isDirectory,
               ["ipynb", "py", "jl", "sh", "r"].contains(item.url.pathExtension.lowercased()) {
                Button { model.runTarget = item } label: {
                    Label("Ejecutar en BosonCode…", systemImage: "play.circle")
                }
            }
            // solo para elementos que gestiona un File Provider
            if item.isUbiquitous, !item.isDirectory {
                Divider()
                if item.isRemoteOnly {
                    Button { Task { await model.downloadNow(item) } } label: {
                        Label("Descargar ahora", systemImage: "arrow.down.circle")
                    }
                } else {
                    Button { Task { await model.freeUpSpace(item) } } label: {
                        Label("Liberar espacio", systemImage: "icloud.slash")
                    }
                }
            }
            Divider()
            Button { model.copySelection() } label: {
                Label("Copiar", systemImage: "doc.on.doc")
            }
            Button { model.cutSelection() } label: {
                Label("Cortar", systemImage: "scissors")
            }
            Button { Task { await model.paste() } } label: {
                Label("Pegar", systemImage: "doc.on.clipboard")
            }
            .disabled(!model.canPaste)
            Button { Task { await model.duplicateSelection() } } label: {
                Label("Duplicar", systemImage: "plus.square.on.square")
            }
            Divider()
            Button { model.beginRename(item) } label: {
                Label("Renombrar", systemImage: "pencil")
            }
            Button { Task { await model.compressSelection() } } label: {
                Label("Comprimir", systemImage: "doc.zipper")
            }
            Button { model.inspecting = item } label: {
                Label("Obtener información", systemImage: "info.circle")
            }
            Divider()
            Button(role: .destructive) { Task { await model.deleteSelection() } } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }
}

extension View {
    func fileContextMenu(_ model: BrowserViewModel, item: FileItem, level: Int) -> some View {
        modifier(FileContextMenu(model: model, item: item, level: level))
            // doble toque con tres dedos = menú de opciones del sistema,
            // sin ocupar el doble clic (que abre el archivo)
            .onThreeFingerDoubleTap {
                guard !item.isDirectory else { return }
                Task { await model.chooseAppFor(item) }
            }
    }

    /// Arrastrar hacia fuera + soltar dentro (si es carpeta).
    func fileDragAndDrop(_ model: BrowserViewModel,
                         item: FileItem,
                         level: Int) -> some View {
        self
            .draggable(item) {
                Label(item.name, systemImage: item.icon)
                    .padding(6)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard item.isDirectory else { return false }
                Task { await model.receive(urls, into: item.url, move: false) }
                return true
            }
    }
}

// MARK: - Vista de iconos

struct IconsView: View {
    @ObservedObject var model: BrowserViewModel
    let level: Int
    @State private var hovered: String?

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 18)]
    private let itemMin: CGFloat = 96
    private let spacing: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                grid(viewportHeight: geo.size.height)
                    // las flechas arriba/abajo necesitan saber cuántas
                    // columnas hay para saltar una fila entera
                    .onChange(of: geo.size.width, initial: true) { _, width in
                        // solo si cambia: publicar en cada pasada de layout
                        // provoca recomposiciones en cadena
                        let count = max(1, Int((width - 32 + spacing) / (itemMin + spacing)))
                        if model.gridColumnCount != count { model.gridColumnCount = count }
                    }
                    .onChange(of: model.levels.last?.selection) { _, _ in
                        if let id = model.selectedItems.first?.id {
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
            }
        }
    }

    private func grid(viewportHeight: CGFloat) -> some View {
        ScrollView {
            // el fondo va detrás de la rejilla y con la altura del visor: así
            // el clic derecho funciona también donde no hay iconos
            ZStack(alignment: .top) {
                FolderBackground(model: model, minHeight: viewportHeight)
                LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { item in
                    VStack(spacing: 6) {
                        ThumbnailView(item: item, size: CGSize(width: 52, height: 52))
                        Text(item.name)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(selected(item) ? Color.accentColor : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(selected(item) ? .white : .primary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(hovered == item.id ? Color.primary.opacity(0.06) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .hoverEffect(.highlight)                    // puntero del Magic Keyboard
                    .onHover { hovered = $0 ? item.id : nil }
                    .id(item.id)
                    .fileTapGestures(model, item: item, level: level)
                    .fileContextMenu(model, item: item, level: level)
                    .fileDragAndDrop(model, item: item, level: level)
                }
                }
                .padding(16)
            }
        }
    }

    private var items: [FileItem] { model.visibleItems(at: level) }
    private func selected(_ item: FileItem) -> Bool {
        model.levels[safe: level]?.selection.contains(item.id) ?? false
    }
}

// MARK: - Vista de lista con columnas de datos

struct DetailListView: View {
    @ObservedObject var model: BrowserViewModel
    let level: Int
    @State private var hovered: String?

    /// Qué columnas caben en el ancho que hay.
    ///
    /// Fecha, Tamaño y Tipo tienen ancho FIJO y suman unos 420 pt; el nombre es
    /// el único flexible, así que era él quien absorbía todo el encogimiento y
    /// acababa en "…" mientras las otras tres seguían enteras — justo al revés
    /// de lo que sirve para reconocer un archivo. Ahora se van retirando de
    /// derecha a izquierda, como hace el Finder al estrechar una ventana, y el
    /// nombre no se sacrifica nunca.
    private struct VisibleColumns {
        let date: Bool, size: Bool, kind: Bool

        /// Ancho que se le reserva al nombre ANTES de conceder ninguna otra
        /// columna. Un nombre real —"Servicios_Suplementarios_2026.pdf"—
        /// necesita este espacio para leerse entero; por debajo, las demás
        /// columnas quitan más de lo que aportan.
        static let nameBudget: CGFloat = 300

        /// Las columnas se conceden por orden y solo si sobra sitio DESPUÉS de
        /// pagar el nombre, así que nunca aparece Tamaño sin Fecha ni queda un
        /// hueco raro en medio.
        init(width: CGFloat) {
            var free = width - 28 - Self.nameBudget   // 28 = margen horizontal
            date = free >= 182                        // 170 + 12 de separación
            if date { free -= 182 }
            size = date && free >= 102                // 90 + 12
            if size { free -= 102 }
            kind = size && free >= 142                // 130 + 12
        }
    }

    var body: some View {
        GeometryReader { outer in
          let columns = VisibleColumns(width: outer.size.width)
          VStack(spacing: 0) {
            header(columns)
            Divider()
            GeometryReader { geo in
              ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .top) {
                        FolderBackground(model: model, minHeight: geo.size.height)
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
                                row(item, columns).id(item.id)
                            }
                        }
                    }
                }
                // que la fila elegida con las flechas siempre quede a la vista
                .onChange(of: model.levels.last?.selection) { _, _ in
                    if let id = model.selectedItems.first?.id {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
              }
            }
          }
        }
    }

    private func header(_ columns: VisibleColumns) -> some View {
        HStack(spacing: 12) {
            columnTitle("Nombre", .name).frame(maxWidth: .infinity, alignment: .leading)
            if columns.date {
                columnTitle("Fecha", .date).frame(width: 170, alignment: .leading)
            }
            if columns.size {
                columnTitle("Tamaño", .size).frame(width: 90, alignment: .trailing)
            }
            if columns.kind {
                columnTitle("Tipo", .kind).frame(width: 130, alignment: .leading)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func columnTitle(_ title: String, _ key: BrowserViewModel.SortKey) -> some View {
        Button {
            model.applySort(key)
        } label: {
            HStack(spacing: 3) {
                // sin esto, "Nombre" se partía en dos líneas ("Nom / bre")
                Text(title).lineLimit(1).fixedSize()
                if model.sortKey == key {
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: FileItem, _ columns: VisibleColumns) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ThumbnailView(item: item, size: CGSize(width: 22, height: 22))
                Text(item.name).lineLimit(1)
                if let badge = item.cloudBadge {
                    Image(systemName: badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if columns.date {
                Text(item.dateLabel).lineLimit(1).frame(width: 170, alignment: .leading)
            }
            if columns.size {
                Text(item.sizeLabel).lineLimit(1).frame(width: 90, alignment: .trailing)
            }
            if columns.kind {
                Text(item.kindLabel).lineLimit(1).frame(width: 130, alignment: .leading)
            }
        }
        .font(.callout)
        .foregroundStyle(selected(item) ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(background(item))
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .onHover { hovered = $0 ? item.id : nil }
        .fileTapGestures(model, item: item, level: level)
        .fileContextMenu(model, item: item, level: level)
        .fileDragAndDrop(model, item: item, level: level)
    }

    private func background(_ item: FileItem) -> some View {
        Group {
            if selected(item) { Color.accentColor }
            else if hovered == item.id { Color.primary.opacity(0.06) }
            else { Color.clear }
        }
    }

    private var items: [FileItem] { model.visibleItems(at: level) }
    private func selected(_ item: FileItem) -> Bool {
        model.levels[safe: level]?.selection.contains(item.id) ?? false
    }
}

// MARK: - Vista de columnas (Miller)

struct ColumnsBrowserView: View {
    @ObservedObject var model: BrowserViewModel
    let columnWidth: CGFloat
    @State private var hovered: String?

    var body: some View {
        GeometryReader { geo in
          ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(model.levels.enumerated()), id: \.element.id) { index, level in
                        column(level, index: index)
                            .frame(width: width(in: geo.size.width))
                            .id(level.id)
                        Divider()
                    }
                }
            }
            .onChange(of: model.levels.count) { _, _ in
                if let last = model.levels.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .trailing) }
                }
            }
            // al estrechar la ventana, la columna activa debe seguir a la vista
            .onChange(of: geo.size.width) { _, _ in
                if let last = model.levels.last { proxy.scrollTo(last.id, anchor: .trailing) }
            }
          }
        }
    }

    /// Ancho real de cada columna.
    ///
    /// El ancho elegido por el usuario manda, pero nunca puede pasarse del de
    /// la ventana: una columna de 340 pt en una ventana de 320 quedaría cortada
    /// y no se vería entera por mucho que se deslizara. Ajustándola, en
    /// estrecho se ve una columna completa y se pasa de una a otra de lado.
    private func width(in available: CGFloat) -> CGFloat {
        guard available > 1 else { return columnWidth }
        return min(columnWidth, available)
    }

    private func column(_ level: DirectoryLevel, index: Int) -> some View {
        ScrollView {
            ZStack(alignment: .top) {
                // solo la última columna acepta el menú de carpeta: es la
                // que representa "la carpeta actual"
                if index == model.levels.count - 1 {
                    FolderBackground(model: model, minHeight: 600)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(grouped(model.visibleItems(at: index)), id: \.0) { group, items in
                    Text(group)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(items) { item in
                        row(item, level: index, selected: level.selection.contains(item.id))
                    }
                }
                }
                .padding(.bottom, 12)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await model.receive(urls, into: level.url, move: false) }
            return true
        }
    }

    private func row(_ item: FileItem, level: Int, selected: Bool) -> some View {
        HStack(spacing: 8) {
            ThumbnailView(item: item, size: CGSize(width: 22, height: 22))
            Text(item.name).lineLimit(1)
            if let badge = item.cloudBadge {
                Image(systemName: badge)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer(minLength: 4)
            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.6))
            }
        }
        .font(.callout)
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor
                             : (hovered == item.id ? Color.primary.opacity(0.06) : .clear),
                    in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .onHover { hovered = $0 ? item.id : nil }
        .fileTapGestures(model, item: item, level: level)
        .fileContextMenu(model, item: item, level: level)
        .fileDragAndDrop(model, item: item, level: level)
    }

    private func grouped(_ items: [FileItem]) -> [(String, [FileItem])] {
        let order = ["Carpetas", "Desarrollo", "Imágenes", "Multimedia",
                     "Documentos PDF", "Comprimidos", "Otros"]
        let groups = Dictionary(grouping: items, by: \.group)
        return order.compactMap { key in
            guard let list = groups[key], !list.isEmpty else { return nil }
            return (key, list)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
