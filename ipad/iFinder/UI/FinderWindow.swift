import SwiftUI
import UniformTypeIdentifiers

/// Ventana principal: barra lateral colapsable + área de contenido con las
/// tres vistas + inspector de información, como el Finder de macOS.
struct FinderWindow: View {
    @StateObject private var model = BrowserViewModel()
    @StateObject private var local = LocalStore()
    @StateObject private var servers = ServerStore.shared
    @ObservedObject private var previewState = PreviewStateManager.shared

    @AppStorage("finderAppearance") private var appearanceRaw = "auto"
    @AppStorage("finderColumnWidth") private var columnWidth: Double = 260
    @AppStorage("finderOnboarded") private var onboarded = false
    @AppStorage("finderShowInspector") private var showInspector = true

    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var showFolderPicker = false
    @State private var pickerStart: URL?
    @State private var selectedSidebar: String?
    /// Foco del teclado en el área de archivos (lo necesitan las flechas)
    @FocusState private var contentFocused: Bool
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
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
        .newFileAlert(model)
        // Los menús de la barra superior operan sobre la ventana con foco:
        // esta línea es lo que se lo dice. Con dos ventanas abiertas, cada
        // una publica la suya y "Nueva carpeta" cae en la carpeta correcta.
        .focusedSceneValue(\.finder, FinderActions(
            model: model,
            newWindow: { openWindow(id: FinderScene.id) },
            closeWindow: { closeThisWindow() }
        ))
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
        .task { await openDefault() }
        // las vistas (doble toque, menú contextual) piden la previa por aquí
        .onChange(of: model.previewRequest) { _, item in
            guard let item else { return }
            model.previewRequest = nil
            openPreview(item)
        }
    }

    // MARK: - Barra lateral

    private var sidebar: some View {
        List(selection: $selectedSidebar) {
            Section {
                ForEach(local.folders) { folder in
                    Button {
                        if let url = local.url(for: folder) { Task { await openLocal(url) } }
                    } label: {
                        SidebarRow(title: folder.name, systemImage: "folder.fill",
                                   tint: Color(red: 0.35, green: 0.62, blue: 0.95))
                    }
                    .buttonStyle(.plain)
                    .macSidebarRowInsets()
                    .contextMenu {
                        Button(role: .destructive) { local.remove(folder) } label: {
                            Label("Quitar de la barra lateral", systemImage: "minus.circle")
                        }
                    }
                }
                Button {
                    Task { await openLocal(documentsURL) }
                } label: {
                    SidebarRow(title: "Archivos de iFinder", systemImage: "iphone")
                }
                .buttonStyle(.plain)
                .macSidebarRowInsets()
            } header: {
                Text("Favoritos").macSidebarSectionHeader()
            }

            Section {
                ForEach(LocalRoot.allCases) { root in
                    Button {
                        pickerStart = root.suggestedURL
                        showFolderPicker = true
                    } label: {
                        SidebarRow(title: root.title, systemImage: root.icon, dimmed: true)
                    }
                    .buttonStyle(.plain)
                    .macSidebarRowInsets()
                }
                Button {
                    pickerStart = nil
                    showFolderPicker = true
                } label: {
                    SidebarRow(title: "Añadir carpeta…", systemImage: "plus.circle", tint: .cyan)
                }
                .buttonStyle(.plain)
                .macSidebarRowInsets()
            } header: {
                Text("Ubicaciones").macSidebarSectionHeader()
            }

            if !servers.servers.isEmpty {
                Section {
                    ForEach(servers.servers) { server in
                        SidebarRow(title: server.name,
                                   systemImage: server.dockerMachineName.isEmpty
                                       ? "desktopcomputer" : "shippingbox.fill",
                                   dimmed: true)
                            .macSidebarRowInsets()
                    }
                } header: {
                    Text("Computadoras").macSidebarSectionHeader()
                }
            }
        }
        .macSidebarStyle()
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
            // el panel aparece solo con algo seleccionado: al deseleccionar
            // desaparece por completo y el contenido recupera el ancho
            if showInspector,
               horizontalSizeClass == .regular,
               let selected = model.inspecting ?? model.selectedItems.first {
                Divider()
                InspectorPanel(model: model, item: selected,
                               onPreview: { openPreview($0) })
                    .frame(width: 260)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .navigationTitle(model.currentURL?.lastPathComponent ?? "iFinder")
        .navigationBarTitleDisplayMode(.inline)
        // Buscador nativo en la barra de navegación, como el del Finder.
        // El filtrado vive en el ViewModel (con caché), no en la vista.
        .searchable(text: $model.searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Buscar en \(model.currentURL?.lastPathComponent ?? "esta carpeta")")
        // El área de archivos debe poder recibir foco para que le lleguen las
        // teclas; sin `.focusable()` las flechas no salen de la barra lateral.
        .focusable()
        .focused($contentFocused)
        .onAppear { contentFocused = true }
        // al tocar cualquier sitio del contenido, el teclado vuelve aquí
        .onTapGesture { contentFocused = true }
        .modifier(ArrowKeyNavigation(model: model, enabled: model.renaming == nil))
        // Barra espaciadora = Quick Look, como en macOS. Se ignora cuando hay
        // un campo de texto activo (renombrar) para no tragarse los espacios.
        .onKeyPress(.space) {
            // no robar el espacio a un campo de texto (renombrar)
            guard model.renaming == nil else { return .ignored }
            // si la previa está abierta, la barra espaciadora la CIERRA,
            // aunque no haya nada seleccionado (igual que en macOS)
            // si ya hay una previa abierta, el espacio la cierra (como macOS)
            if let open = previewState.openURLs.first {
                dismissWindow(id: PreviewScene.id, value: open)
                previewState.closed(open)
                return .handled
            }
            guard let item = model.selectedItems.first, !item.isDirectory else { return .ignored }
            openPreview(item)
            return .handled
        }
    }

    /// Abre (o reutiliza) la ventana de vista previa con el archivo elegido.
    private func openPreview(_ item: FileItem) {
        // el archivo viaja como valor: la ventana nueva es independiente
        openWindow(id: PreviewScene.id, value: item.url)
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

            if let name = model.openingExternally {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("Abriendo \(name)…").font(.caption2).foregroundStyle(.secondary)
                }
            } else if let name = model.downloadingName {
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
    /// Atajos que NO están en la barra de menús.
    ///
    /// Todo lo que aparece en un menú se declara allí y solo allí: dos vistas
    /// reclamando la misma combinación es ambiguo y SwiftUI resuelve el
    /// empate de forma imprevisible.
    private var shortcuts: some View {
        Group {
            Button("") {
                if let item = model.selectedItems.first, !item.isDirectory { openPreview(item) }
            }
            .keyboardShortcut(.downArrow, modifiers: .command)   // ⌘↓ abrir, como macOS
            Button("") { if let item = model.selectedItems.first { model.beginRename(item) } }
                .keyboardShortcut(.return, modifiers: [])        // Intro renombra
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    /// Cierra esta ventana (⌘W). En iPadOS una ventana es una escena, así que
    /// se destruye su sesión; `dismissWindow` solo sirve para escenas con
    /// valor, como la de vista previa.
    private func closeThisWindow() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        UIApplication.shared.requestSceneSessionDestruction(scene.session,
                                                           options: nil,
                                                           errorHandler: nil)
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
    let item: FileItem
    var onPreview: ((FileItem) -> Void)? = nil
    @State private var folderSize: Int64?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Group {
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
                }
            }
            .padding(16)
        }
        .task(id: item.id) {
            folderSize = nil
            guard item.isDirectory else { return }
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
