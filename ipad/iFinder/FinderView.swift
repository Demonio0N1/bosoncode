import SwiftUI
import UniformTypeIdentifiers

/// Finder para iPad: barra lateral con ubicaciones y vista de columnas
/// (Miller) como en macOS. Navega tus PCs, sus máquinas Docker y el iPad.
struct FinderView: View {
    @StateObject private var store = ServerStore.shared
    @StateObject private var model = FinderModel()
    @StateObject private var local = LocalStore()
    @State private var showFolderPicker = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @AppStorage("finderAppearance") private var appearanceRaw = "auto"
    @AppStorage("finderColumnWidth") private var columnWidth: Double = 280
    @AppStorage("finderOnboarded") private var onboarded = false
    @State private var pickerStart: URL?

    private var colorScheme: ColorScheme? {
        switch appearanceRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            columns
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(colorScheme)
        .fullScreenCover(item: Binding(get: { model.quickLookURL.map(QLItem.init) },
                                       set: { if $0 == nil { model.quickLookURL = nil } })) { item in
            QuickLookView(url: item.url) { model.quickLookURL = nil }
                .ignoresSafeArea()
        }
        .task { model.attach(store: store, local: local) }
        .background(WindowFreeResize())
        .sheet(isPresented: $showFolderPicker) {
            FolderPicker(startAt: pickerStart) { url in
                local.add(url: url)
                model.refreshLocal()
                pickerStart = nil
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView(
                onPick: { root in
                    pickerStart = root.suggestedURL
                    onboarded = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showFolderPicker = true
                    }
                },
                onSkip: { onboarded = true })
                .presentationDetents([.medium, .large])
        }
        .alert("Nueva carpeta", isPresented: $showNewFolder) {
            TextField("Nombre", text: $newFolderName)
            Button("Crear") {
                Task { await model.createFolder(named: newFolderName) }
                newFolderName = ""
            }
            Button("Cancelar", role: .cancel) { newFolderName = "" }
        }
        .alert("Error", isPresented: Binding(get: { model.error != nil },
                                             set: { if !$0 { model.error = nil } })) {
            Button("Entendido", role: .cancel) { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }

    // MARK: - Barra lateral

    private var sidebar: some View {
        List(selection: Binding(get: { model.location },
                                set: { if let l = $0 { Task { await model.open(l) } } })) {
            if !model.favorites.isEmpty {
                Section("Favoritos") {
                    ForEach(model.favorites) { loc in
                        Label(loc.name, systemImage: loc.icon).tag(loc)
                    }
                }
            }
            Section("Ubicaciones") {
                ForEach(model.locations) { loc in
                    Label(loc.name, systemImage: loc.icon).tag(loc)
                }
            }
            Section("Este iPad") {
                ForEach(model.localLocations) { loc in
                    Label(loc.name, systemImage: loc.icon).tag(loc)
                }
                ForEach(LocalRoot.allCases) { root in
                    if !model.localLocations.contains(where: { $0.name.localizedCaseInsensitiveContains(root.title) }) {
                        Button {
                            pickerStart = root.suggestedURL
                            showFolderPicker = true
                        } label: {
                            Label(root.title, systemImage: root.icon)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    pickerStart = nil
                    showFolderPicker = true
                } label: {
                    Label("Añadir carpeta…", systemImage: "plus.circle")
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("iFinder")
    }

    // MARK: - Columnas

    private var columns: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.columns.isEmpty {
                ContentUnavailableView("Elige una ubicación",
                                       systemImage: "sidebar.left",
                                       description: Text("Tus computadoras y sus máquinas aparecen en la barra lateral."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(Array(model.columns.enumerated()), id: \.element.id) { index, column in
                                columnView(column, level: index)
                                    .frame(width: columnWidth)
                                    .id(column.id)
                                Divider()
                            }
                            // columna de vista previa, como en Finder
                            PreviewPanel(item: model.selectedItem,
                                         previewURL: model.previewURL,
                                         loading: model.preparing,
                                         onOpen: { Task { await model.quickLook() } },
                                         onSave: { Task { await model.share(model.selectedItem) } })
                                .frame(width: max(260, columnWidth))
                                .id("preview")
                        }
                    }
                    .onChange(of: model.columns.count) { _, _ in
                        if let last = model.columns.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .trailing) }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) { shortcuts }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button { Task { await model.goUp() } } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.columns.count < 2)

            Text(model.currentPath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()

            if model.loading { ProgressView().controlSize(.small) }

            Button { showNewFolder = true } label: {
                Image(systemName: "folder.badge.plus")
            }
            .disabled(model.location == nil)

            Button { Task { await model.reload() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.location == nil)

            // ancho de columnas: se ajusta a cualquier tamaño de ventana
            Menu {
                Picker("Ancho de columna", selection: $columnWidth) {
                    Text("Estrecha").tag(220.0)
                    Text("Normal").tag(280.0)
                    Text("Ancha").tag(360.0)
                    Text("Muy ancha").tag(440.0)
                }
                Divider()
                Picker("Apariencia", selection: $appearanceRaw) {
                    Label("Automático", systemImage: "circle.lefthalf.filled").tag("auto")
                    Label("Claro", systemImage: "sun.max.fill").tag("light")
                    Label("Oscuro", systemImage: "moon.fill").tag("dark")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func columnView(_ column: FinderColumn, level: Int) -> some View {
        List {
            ForEach(groupedItems(column.items), id: \.0) { group, items in
                Section(group) {
                    ForEach(items) { item in
                        row(item, level: level, selected: column.selection == item.path)
                    }
                }
            }
        }
        .listStyle(.plain)
        .dropDestination(for: FinderTransfer.self) { transfers, _ in
            Task { await model.receive(transfers, into: column.path) }
            return true
        }
    }

    private func row(_ item: FinderItem, level: Int, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .foregroundStyle(item.iconColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                if !item.dir {
                    Text("\(item.sizeLabel) · \(item.dateLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if item.dir {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)          // sin las líneas del iPad
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
        .onTapGesture(count: 2) {
            if item.dir {
                Task { await model.select(item, at: level) }
            } else {
                Task { await model.quickLook(item) }
            }
        }
        .onTapGesture { Task { await model.select(item, at: level) } }
        .draggable(model.transfer(for: item)) {
            Label(item.name, systemImage: item.icon)
        }
        .contextMenu {
            Button {
                Task { await model.quickLook(item) }
            } label: { Label("Abrir", systemImage: "eye") }
            Button {
                Task { await model.share(item) }
            } label: { Label("Guardar en el iPad", systemImage: "square.and.arrow.down") }
            Button(role: .destructive) {
                Task { await model.delete(item) }
            } label: { Label("Eliminar", systemImage: "trash") }
        }
    }

    /// Atajos de Finder: espacio = vista rápida, ⌘↓ = abrir
    private var shortcuts: some View {
        Group {
            Button("") { Task { await model.quickLook() } }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { Task { await model.quickLook() } }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button("") { Task { await model.goUp() } }
                .keyboardShortcut(.upArrow, modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func groupedItems(_ items: [FinderItem]) -> [(String, [FinderItem])] {
        let order = ["Carpetas", "Desarrollo", "Imágenes", "Documentos PDF", "Comprimidos", "Otros"]
        let groups = Dictionary(grouping: items, by: \.group)
        return order.compactMap { key in
            guard let list = groups[key], !list.isEmpty else { return nil }
            return (key, list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }
}
