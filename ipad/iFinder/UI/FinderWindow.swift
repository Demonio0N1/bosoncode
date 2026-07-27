import SwiftUI
import UniformTypeIdentifiers

/// Ventana principal: barra lateral colapsable + área de contenido con las
/// tres vistas + inspector de información, como el Finder de macOS.
struct FinderWindow: View {
    @StateObject private var model = BrowserViewModel()
    @StateObject private var local = LocalStore()
    @StateObject private var servers = ServerStore.shared
    @StateObject private var preview = PreviewSession()

    @AppStorage("finderAppearance") private var appearanceRaw = "auto"
    @AppStorage("finderColumnWidth") private var columnWidth: Double = 260
    @AppStorage("finderOnboarded") private var onboarded = false
    @AppStorage("finderShowInspector") private var showInspector = true

    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var showFolderPicker = false
    @State private var pickerStart: URL?
    @State private var selectedSidebar: String?
    @Environment(\.openWindow) private var openWindow
    /// En ventanas estrechas la interfaz se simplifica (Split View pequeño)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var scheme: ColorScheme? {
        switch appearanceRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            sidebar
        } detail: {
            content
        }
        .navigationSplitViewStyle(.balanced)
        // la ventana se adapta a cualquier tamaño de Stage Manager / Split View
        .frame(minWidth: 320, minHeight: 400)
        .preferredColorScheme(scheme)
        .background(WindowFreeResize())
        .background(shortcuts)
        // selector nativo de SwiftUI: acepta carpetas y archivos sueltos
        .fileImporter(isPresented: $showFolderPicker,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if local.add(url: url) {
                    Task { await openLocal(url) }
                } else {
                    model.error = "No pude guardar el permiso de esa carpeta. Elige la ubicación desde la barra lateral del selector."
                }
            case .failure(let error):
                model.error = error.localizedDescription
            }
            pickerStart = nil
        }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView(onPick: { root in
                onboarded = true
                pickerStart = root.suggestedURL
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showFolderPicker = true }
            }, onSkip: { onboarded = true })
            .presentationDetents([.medium, .large])
        }
        .alert("Renombrar", isPresented: Binding(get: { model.renaming != nil },
                                                 set: { if !$0 { model.renaming = nil } })) {
            TextField("Nombre", text: $model.renameText)
            Button("Renombrar") { Task { await model.commitRename() } }
            Button("Cancelar", role: .cancel) { model.renaming = nil }
        }
        .alert("Error", isPresented: Binding(get: { model.error != nil },
                                             set: { if !$0 { model.error = nil } })) {
            Button("Entendido", role: .cancel) { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
        // Vista previa en hoja modal con el ciclo completo de permisos:
        // begin() abre el ámbito, la hoja lo usa, onDismiss lo cierra.
        .sheet(item: Binding(get: { preview.previewURL.map(QLItem.init) },
                             set: { if $0 == nil { preview.end() } }),
               onDismiss: { preview.end() }) { ql in
            QuickLookPreview(url: ql.url) { preview.end() }
                .ignoresSafeArea()
        }
        .alert("No se puede previsualizar",
               isPresented: Binding(get: { preview.error != nil },
                                    set: { if !$0 { preview.error = nil } })) {
            Button("Entendido", role: .cancel) { preview.error = nil }
        } message: {
            Text(preview.error ?? "")
        }
        .task { await openDefault() }
        // las vistas (doble toque, menú contextual) piden la previa por aquí
        .onChange(of: model.previewRequest) { _, item in
            guard let item else { return }
            model.previewRequest = nil
            Task { await preview.begin(item) }   // hoja modal, ámbito controlado
        }
    }

    // MARK: - Barra lateral

    private var sidebar: some View {
        List(selection: $selectedSidebar) {
            Section("Favoritos") {
                ForEach(local.folders) { folder in
                    Button {
                        if let url = local.url(for: folder) { Task { await openLocal(url) } }
                    } label: {
                        Label(folder.name, systemImage: "folder.fill")
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { local.remove(folder) } label: {
                            Label("Quitar de la barra lateral", systemImage: "minus.circle")
                        }
                    }
                }
                Button {
                    Task { await openLocal(documentsURL) }
                } label: {
                    Label("Archivos de iFinder", systemImage: "iphone")
                }
                .buttonStyle(.plain)
            }

            Section("Ubicaciones del iPad") {
                ForEach(LocalRoot.allCases) { root in
                    Button {
                        pickerStart = root.suggestedURL
                        showFolderPicker = true
                    } label: {
                        Label(root.title, systemImage: root.icon)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    pickerStart = nil
                    showFolderPicker = true
                } label: {
                    Label("Añadir carpeta…", systemImage: "plus.circle").foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }

            if !servers.servers.isEmpty {
                Section("Computadoras") {
                    ForEach(servers.servers) { server in
                        Label(server.name,
                              systemImage: server.dockerMachineName.isEmpty
                                  ? "desktopcomputer" : "shippingbox.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("iFinder")
    }

    // MARK: - Contenido

    private var content: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                Group {
                    switch (horizontalSizeClass == .compact ? .list : model.viewMode) {
                    case .icons:
                        if let level = model.levels.indices.last { IconsView(model: model, level: level) }
                    case .list:
                        if let level = model.levels.indices.last { DetailListView(model: model, level: level) }
                    case .columns:
                        ColumnsBrowserView(model: model, columnWidth: columnWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusBar
            }
            if showInspector, horizontalSizeClass == .regular {
                Divider()
                InspectorPanel(model: model, onPreview: { openPreview($0) })
                    .frame(width: 260)
            }
        }
        .navigationTitle(model.currentURL?.lastPathComponent ?? "iFinder")
        .navigationBarTitleDisplayMode(.inline)
        // Barra espaciadora = Quick Look, como en macOS. Se ignora cuando hay
        // un campo de texto activo (renombrar) para no tragarse los espacios.
        .onKeyPress(.space) {
            guard model.renaming == nil,
                  let item = model.selectedItems.first,
                  !item.isDirectory else { return .ignored }
            openPreview(item)
            return .handled
        }
    }

    /// Abre la vista previa en una ventana propia de iPadOS.
    private func openPreview(_ item: FileItem) {
        // si vive en la nube se descarga antes: la otra escena solo recibe la URL
        if item.isRemoteOnly || item.isDownloading {
            Task {
                model.downloadingName = item.name
                defer { model.downloadingName = nil }
                try? await CloudFileHandler.shared.materialize(item.url)
                openWindow(id: PreviewScene.id, value: item.url)
            }
        } else {
            openWindow(id: PreviewScene.id, value: item.url)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Button { Task { await model.goUp() } } label: { Image(systemName: "chevron.left") }
                .disabled(model.levels.isEmpty)
            Button { Task { await model.reload() } } label: { Image(systemName: "arrow.clockwise") }

            Picker("Vista", selection: $model.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Image(systemName: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Spacer(minLength: 8)

            if let name = model.downloadingName {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("Bajando \(name)…").font(.caption2).foregroundStyle(.secondary)
                }
            } else if model.busy {
                ProgressView().controlSize(.small)
            }

            Button { Task { await model.newFolder() } } label: {
                Image(systemName: "folder.badge.plus")
            }
            Button { showInspector.toggle() } label: {
                Image(systemName: showInspector ? "sidebar.trailing" : "sidebar.right")
            }
            Menu {
                Picker("Ordenar por", selection: Binding(get: { model.sortKey },
                                                        set: { model.applySort($0) })) {
                    ForEach(BrowserViewModel.SortKey.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Mostrar ocultos", isOn: Binding(get: { model.showHidden },
                                                        set: { model.showHidden = $0
                                                               Task { await model.reload() } }))
                Divider()
                Picker("Ancho de columna", selection: $columnWidth) {
                    Text("Estrecha").tag(200.0)
                    Text("Normal").tag(260.0)
                    Text("Ancha").tag(340.0)
                }
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

    private var statusBar: some View {
        HStack {
            Text(model.currentURL?.path ?? "")
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            let count = model.current?.items.count ?? 0
            Text("\(count) elementos · \(model.selectedItems.count) seleccionados")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
    }

    /// Atajos de Mac: ⌘C, ⌘X, ⌘V, ⌘D, ⌘⌫, ⌘N, ⌘I, espacio, ⌘↑
    private var shortcuts: some View {
        Group {
            Button("") { model.copySelection() }.keyboardShortcut("c", modifiers: .command)
            Button("") { model.cutSelection() }.keyboardShortcut("x", modifiers: .command)
            Button("") { Task { await model.paste() } }.keyboardShortcut("v", modifiers: .command)
            Button("") { Task { await model.duplicateSelection() } }.keyboardShortcut("d", modifiers: .command)
            Button("") { Task { await model.deleteSelection() } }.keyboardShortcut(.delete, modifiers: .command)
            Button("") { Task { await model.newFolder() } }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("") { model.inspecting = model.selectedItems.first }.keyboardShortcut("i", modifiers: .command)
            Button("") {
                if let item = model.selectedItems.first, !item.isDirectory { openPreview(item) }
            }
            .keyboardShortcut(.space, modifiers: [])
            Button("") {
                if let item = model.selectedItems.first, !item.isDirectory { openPreview(item) }
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            Button("") { Task { await model.goUp() } }.keyboardShortcut(.upArrow, modifiers: .command)
            Button("") { if let item = model.selectedItems.first { model.beginRename(item) } }
                .keyboardShortcut(.return, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    // MARK: - Apertura

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Con UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace, la carpeta
    /// de documentos aparece en Archivos › En mi iPad › iFinder. Debe existir y
    /// no estar vacía para que el sistema la muestre.
    private func seedDocumentsFolder() {
        let fm = FileManager.default
        let readme = documentsURL.appendingPathComponent("Léeme.txt")
        guard !fm.fileExists(atPath: readme.path),
              (try? fm.contentsOfDirectory(atPath: documentsURL.path))?.isEmpty != false else { return }
        let texto = """
        Esta carpeta es la de iFinder y aparece en Archivos › En mi iPad › iFinder.

        Lo que dejes aquí se ve desde ambas apps, y desde iFinder puedes
        arrastrarlo a tus computadoras o a cualquier otra app del iPad.
        """
        try? texto.write(to: readme, atomically: true, encoding: .utf8)
    }

    private func openDefault() async {
        seedDocumentsFolder()
        if let first = local.folders.first, let url = local.url(for: first) {
            await openLocal(url)
        } else {
            await openLocal(documentsURL)
        }
    }

    private func openLocal(_ url: URL) async {
        await model.open(url)
    }
}

/// Panel derecho de información (⌘I), con vista previa y datos del archivo.
struct InspectorPanel: View {
    @ObservedObject var model: BrowserViewModel
    var onPreview: ((FileItem) -> Void)? = nil
    @State private var folderSize: Int64?

    private var item: FileItem? { model.inspecting ?? model.selectedItems.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let item {
                    preview(item)
                    Text(item.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    VStack(spacing: 6) {
                        info("Tipo", item.kindLabel)
                        info("Tamaño", item.isDirectory
                             ? (folderSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "calculando…")
                             : item.sizeLabel)
                        info("Modificado", item.dateLabel)
                        info("Ubicación", item.url.deletingLastPathComponent().lastPathComponent)
                    }
                    if !item.isDirectory {
                        Button { onPreview?(item) } label: {
                            Label("Abrir (espacio)", systemImage: "eye").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    ShareLink(item: item.url) {
                        Label("Compartir", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Image(systemName: "info.circle")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 40)
                    Text("Sin selección").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .task(id: item?.id) {
            folderSize = nil
            guard let item, item.isDirectory else { return }
            folderSize = await FileService.shared.directorySize(item.url)
        }
    }

    @ViewBuilder
    private func preview(_ item: FileItem) -> some View {
        // miniatura real generada por el sistema (primera página del PDF,
        // fotograma del vídeo…), igual que en la app Archivos
        ThumbnailView(item: item, size: CGSize(width: 190, height: 190))
            .padding(.top, 8)
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}
