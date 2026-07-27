import SwiftUI
import UniformTypeIdentifiers

// MARK: - Menú contextual compartido

/// Menú de clic derecho (trackpad) o pulsación larga, con las acciones reales
/// del Finder.
struct FileContextMenu: ViewModifier {
    @ObservedObject var model: BrowserViewModel
    let item: FileItem

    func body(content: Content) -> some View {
        content.contextMenu {
            Button { Task { await model.openInDefaultApp(item) } } label: {
                Label("Abrir con…", systemImage: "arrow.up.forward.app")
            }
            Button { model.quickLook(item) } label: {
                Label("Vista rápida (espacio)", systemImage: "eye")
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
    func fileContextMenu(_ model: BrowserViewModel, item: FileItem) -> some View {
        modifier(FileContextMenu(model: model, item: item))
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

    var body: some View {
        ScrollView {
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
                    .onTapGesture(count: 2) { open(item) }
                    .onTapGesture { Task { await model.select(item, at: level) } }
                    .fileContextMenu(model, item: item)
                    .fileDragAndDrop(model, item: item, level: level)
                }
            }
            .padding(16)
        }
    }

    private var items: [FileItem] { model.levels[safe: level]?.items ?? [] }
    private func selected(_ item: FileItem) -> Bool {
        model.levels[safe: level]?.selection.contains(item.id) ?? false
    }
    /// Doble clic: carpeta → entrar; archivo → abrir en su app (como macOS)
    private func open(_ item: FileItem) {
        if item.isDirectory { Task { await model.select(item, at: level) } }
        else { Task { await model.openInDefaultApp(item) } }
    }
}

// MARK: - Vista de lista con columnas de datos

struct DetailListView: View {
    @ObservedObject var model: BrowserViewModel
    let level: Int
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            columnTitle("Nombre", .name).frame(maxWidth: .infinity, alignment: .leading)
            columnTitle("Fecha", .date).frame(width: 170, alignment: .leading)
            columnTitle("Tamaño", .size).frame(width: 90, alignment: .trailing)
            columnTitle("Tipo", .kind).frame(width: 130, alignment: .leading)
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
                Text(title)
                if model.sortKey == key {
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: FileItem) -> some View {
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
            Text(item.dateLabel).frame(width: 170, alignment: .leading)
            Text(item.sizeLabel).frame(width: 90, alignment: .trailing)
            Text(item.kindLabel).lineLimit(1).frame(width: 130, alignment: .leading)
        }
        .font(.callout)
        .foregroundStyle(selected(item) ? .white : .primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(background(item))
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .onHover { hovered = $0 ? item.id : nil }
        .onTapGesture(count: 2) { open(item) }
        .onTapGesture { Task { await model.select(item, at: level) } }
        .fileContextMenu(model, item: item)
        .fileDragAndDrop(model, item: item, level: level)
    }

    private func background(_ item: FileItem) -> some View {
        Group {
            if selected(item) { Color.accentColor }
            else if hovered == item.id { Color.primary.opacity(0.06) }
            else { Color.clear }
        }
    }

    private var items: [FileItem] { model.levels[safe: level]?.items ?? [] }
    private func selected(_ item: FileItem) -> Bool {
        model.levels[safe: level]?.selection.contains(item.id) ?? false
    }
    private func open(_ item: FileItem) {
        if item.isDirectory { Task { await model.select(item, at: level) } }
        else { Task { await model.openInDefaultApp(item) } }
    }
}

// MARK: - Vista de columnas (Miller)

struct ColumnsBrowserView: View {
    @ObservedObject var model: BrowserViewModel
    let columnWidth: CGFloat
    @State private var hovered: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(model.levels.enumerated()), id: \.element.id) { index, level in
                        column(level, index: index)
                            .frame(width: columnWidth)
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
        }
    }

    private func column(_ level: DirectoryLevel, index: Int) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(grouped(level.items), id: \.0) { group, items in
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
        .onTapGesture(count: 2) {
            if !item.isDirectory { Task { await model.openInDefaultApp(item) } }
        }
        .onTapGesture { Task { await model.select(item, at: level) } }
        .fileContextMenu(model, item: item)
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
