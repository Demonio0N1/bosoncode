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
    /// Ancho de la barra lateral, recordado entre sesiones
    @AppStorage("finderSidebarWidth") private var sidebarWidth: Double = 220
    /// Ancho del inspector, ajustable arrastrando su separador
    @AppStorage("finderInspectorWidth") private var inspectorWidth: Double = 260
    @AppStorage("finderOnboarded") private var onboarded = false
    @AppStorage("finderShowInspector") private var showInspector = true

    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var showFolderPicker = false
    @State private var pickerStart: URL?
    /// Panel lateral visible en ventana estrecha (ahí no es una columna fija)
    @State private var showCompactSidebar = false
    /// Secciones plegadas de la barra lateral, por título
    @State private var collapsedSections: Set<String> = []
    /// Foco del teclado en el área de archivos (lo necesitan las flechas)
    @FocusState private var contentFocused: Bool
    /// Montaje que se está renombrando y ayuda para montar una nube
    @State private var renamingMount: LocalStore.Folder?
    @State private var mountName = ""
    @State private var showMountHelp = false
    @State private var showTrash = false
    /// Ubicación del sistema que espera permiso (si el selector viene de ahí)
    @State private var pendingLocation: SystemLocation?
    /// Carpeta recién elegida, a la espera de que el usuario la nombre
    /// Montaje recién creado al que se refiere el diálogo de nombre.
    @State private var pendingMount: LocalStore.Folder?
    @State private var pendingName = ""
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
        Group {
            if horizontalSizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .newFileAlert(model)
        // Renombrar el montaje: dos cuentas del mismo servicio solo se
        // distinguen por el nombre que les ponga el usuario.
        .alert("Nombre en la barra lateral",
               isPresented: Binding(get: { renamingMount != nil },
                                    set: { if !$0 { renamingMount = nil } })) {
            TextField("Ej.: OneDrive – Yachay Tech", text: $mountName)
            Button("Guardar") {
                if let mount = renamingMount { local.rename(mount, to: mountName) }
                renamingMount = nil
            }
            Button("Cancelar", role: .cancel) { renamingMount = nil }
        }
        // Guía para montar: el selector no puede abrirse ya dentro de Drive,
        // así que se explica el camino antes de mostrarlo.
        .alert("Montar una nube", isPresented: $showMountHelp) {
            Button("Abrir selector") {
                pickerStart = nil
                showFolderPicker = true
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("""
            Necesitas la app del servicio instalada y con la sesión iniciada \
            (Google Drive, OneDrive…).

            En el selector: toca el servicio en la barra lateral, ENTRA en él y \
            elige una carpeta de dentro. La raíz del servicio no se puede \
            seleccionar — es una limitación de iPadOS, no de la app.

            Si el servicio no aparece, actívalo en Explorar › ••• › Editar.
            """)
        }
        // Los menús de la barra superior operan sobre la ventana con foco:
        // esta línea es lo que se lo dice. Con dos ventanas abiertas, cada
        // una publica la suya y "Nueva carpeta" cae en la carpeta correcta.
        .focusedSceneValue(\.finder, FinderActions(
            model: model,
            newWindow: { openWindow(id: FinderScene.id) },
            closeWindow: { closeThisWindow() }
        ))
        .focusedSceneValue(\.windowClose,
                           WindowCloseAction(id: "finder") { closeThisWindow() })
        // la ventana se adapta a cualquier tamaño de Stage Manager / Split View
        .frame(minWidth: 320, minHeight: 400)
        .preferredColorScheme(scheme)
        .background(WindowFreeResize())
        .background(shortcuts)
        // selector nativo de SwiftUI: acepta carpetas y archivos sueltos
        // Único punto de la app que abre el selector.
        // Se aceptan carpetas Y archivos a propósito. Limitándolo a carpetas,
        // iPadOS ATENÚA todo lo demás, y en la raíz de OneDrive o Drive casi
        // todo son archivos: la pantalla parecía bloqueada. Si el usuario
        // elige un archivo se le dice qué hacer, en vez de no dejarle tocar.
        .fileImporter(isPresented: $showFolderPicker,
                      allowedContentTypes: [.folder, .item],
                      allowsMultipleSelection: false) { result in
            let location = pendingLocation
            pendingLocation = nil
            pickerStart = nil

            // TODO lo que se presente aquí va con retardo. Una alerta lanzada
            // mientras el selector aún se está cerrando la descarta iPadOS EN
            // SILENCIO: ni alerta de nombre, ni mensaje de error, nada — que
            // es justo lo que se veía al pulsar "Open".
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard isDirectory(url) else {
                    present { model.error = "Eso es un archivo. Entra en la carpeta que quieras montar y elígela con «Abrir»." }
                    return
                }
                // Se guarda YA, sin esperar a ningún diálogo: así la ubicación
                // aparece en la barra lateral aunque la alerta se pierda. El
                // nombre se puede corregir después, y de hecho se ofrece.
                // El nombre del servicio manda sobre la etiqueta de la fila
                // que abrió el selector: entrar por "Unidad externa" y acabar
                // con OneDrive guardado como "Unidad externa" es justo lo que
                // hacía irreconocible el montaje en la barra lateral.
                let detected = CloudProvider.detect(url)
                let suggested = detected.isCloud ? detected.suggestedName(for: url)
                                                 : (url.displayName.isEmpty ? (location?.title ?? "Carpeta")
                                                                            : url.displayName)
                guard let created = local.add(url: url, named: suggested) else {
                    present { model.error = "No pude guardar el permiso de esa carpeta. Vuelve a elegirla desde la barra lateral del selector." }
                    return
                }
                Task { await openLocal(url) }
                // Se pregunta SIEMPRE: la ruta de un proveedor externo suele
                // ser un contenedor anónimo ("File Provider Storage"), así que
                // ni detectándola se acierta con el nombre que el usuario
                // reconocería.
                present {
                    // el nombre REAL con el que quedó: si ya había otra cuenta
                    // del mismo servicio, es "OneDrive 2" y no "OneDrive"
                    pendingName = created.name
                    pendingMount = created
                }
            case .failure(let error):
                present { model.error = error.localizedDescription }
            }
        }
        .alert("Nombre de la ubicación",
               isPresented: Binding(get: { pendingMount != nil },
                                    set: { if !$0 { pendingMount = nil } })) {
            TextField("Ej.: Google Drive", text: $pendingName)
            Button("Guardar") {
                // se renombra ESTE montaje, no "el último de la lista"
                if let mount = pendingMount { local.rename(mount, to: pendingName) }
                pendingMount = nil
            }
            Button("Dejar así", role: .cancel) { pendingMount = nil }
        } message: {
            Text("Ya está añadida. Puedes cambiarle el nombre — así distingues dos cuentas del mismo servicio.")
        }
        // Editar abre una VENTANA propia, no una hoja: una hoja secuestra el
        // explorador y no deja tener dos archivos abiertos a la vez.
        .onChange(of: model.editing) { _, item in
            guard let item else { return }
            model.editing = nil
            openWindow(id: EditorScene.id, value: item.url)
        }
        .sheet(item: Binding(get: { model.drawingOn },
                             set: { model.drawingOn = $0 })) { item in
            ImageEditorView(url: item.url) {
                // la miniatura guardada ya no vale: el archivo cambió
                Task { await model.reload() }
            }
        }
        .sheet(isPresented: $showTrash) { TrashView(model: model) }
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
            // Cuando el fallo es de permiso, decirlo no basta: sin esto la
            // única salida era reiniciar la app. El selector es lo ÚNICO que
            // devuelve el acceso a una carpeta de fuera del contenedor.
            if let target = model.regrantTarget {
                Button("Elegir esta carpeta…") {
                    pickerStart = target
                    model.error = nil
                    model.regrantTarget = nil
                    present { showFolderPicker = true }
                }
                Button("Volver al inicio") {
                    model.error = nil
                    model.regrantTarget = nil
                    Task { await openLocal(documentsURL) }
                }
            }
            Button("Entendido", role: .cancel) {
                model.error = nil
                model.regrantTarget = nil
            }
        } message: {
            Text(model.error ?? "")
        }
        .task { await openDefault() }
        .task { await model.refreshTrashCount() }
        // las vistas (doble toque, menú contextual) piden la previa por aquí
        .onChange(of: model.previewRequest) { _, item in
            guard let item else { return }
            model.previewRequest = nil
            openPreview(item)
        }
    }

    // MARK: - Barra lateral

    /// Ventana normal: la barra lateral es una COLUMNA, no un panel encima.
    ///
    /// Aquí tampoco se usa `NavigationSplitView`. Decide por su cuenta cuándo
    /// enseñar la barra como superposición translúcida sobre el contenido, y en
    /// cuanto la ventana no da para las dos columnas a su ancho ideal lo hace
    /// aunque el estilo sea `.balanced`. El resultado era una barra flotando
    /// encima de los archivos, con el fondo atenuado y todo movido.
    ///
    /// Un HStack no tiene esa duda: la barra ocupa su sitio y el contenido el
    /// suyo. De paso, el asa de redimensionar —que vive al principio de
    /// `content`— queda justo entre las dos, que es donde se espera.
    private var regularLayout: some View {
        HStack(spacing: 0) {
            if visibility != .detailOnly {
                sidebar
                    .frame(width: sidebarWidth)
                    // El fondo redondeado no recorta nada por sí solo: dibuja
                    // DETRÁS. Sin esto, una fila que llega al borde inferior se
                    // pintaba por encima de la esquina curva y se salía del
                    // panel — que es lo que le pasaba a "Papelera".
                    .clipShape(panelShape)
                    .background(sidebarSurface)
                    // Margen IGUAL por los cuatro lados. Antes eran tres:
                    // `.leading` + `.vertical` dejaba el lado derecho a cero, y
                    // el panel quedaba flotando por arriba, abajo e izquierda
                    // pero pegado al contenido por la derecha.
                    .padding(8)
                    // …y los ocho puntos deben contarse desde el borde de la
                    // VENTANA. Sin esto se cuentan desde el área segura, que en
                    // un iPad existe arriba y abajo pero no a los lados: el
                    // hueco de arriba y el de abajo salían siendo 8 más el
                    // margen del sistema, y solo el de la izquierda medía 8.
                    .ignoresSafeArea(.container, edges: .vertical)
                    .transition(.move(edge: .leading))
            }
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { sidebarToggle }
                    }
            }
        }
    }

    /// Ancho del panel en ventana estrecha.
    ///
    /// Nunca puede quedarse con la ventana entera: si tapa todo, deja de leerse
    /// como un panel encima del contenido y parece que la app cambió de
    /// pantalla. Se le deja siempre un margen por el que se ve —y se toca— lo
    /// que hay detrás.
    private func sidebarPanelWidth(in available: CGFloat) -> CGFloat {
        guard available > 1 else { return 270 }
        return min(270, available * 0.82)
    }

    /// Superficie de la barra: panel flotante con esquinas redondeadas.
    ///
    /// En macOS la barra lateral no es un rectángulo pegado al borde: es un
    /// panel despegado de la ventana, con sus cuatro esquinas redondeadas. El
    /// margen exterior es lo que lo hace flotar —sin él, las esquinas de arriba
    /// y abajo quedarían cortadas por el borde y no se vería el efecto—.
    ///
    /// El borde tenue delimita el panel cuando él y el fondo son oscuros, que
    /// es cuando un material translúcido se confunde con lo que hay detrás.
    ///
    /// Radio de la esquina del panel, igualado al de la ventana.
    ///
    /// Va calibrado a ojo porque iPadOS **no publica el suyo**: no hay API que
    /// lo devuelva, ni para la ventana de Stage Manager ni para la pantalla.
    /// Medido sobre una captura, la esquina de la ventana es ~1,35 veces la que
    /// tenía el panel con 16, de donde salen estos 22.
    ///
    /// Es el único número del panel que no se deduce de una regla —el margen,
    /// el área segura y las dos capas de burbuja sí—, así que vive aparte y con
    /// nombre: si hay que moverlo, se mueve aquí y en ningún otro sitio.
    private static let panelCornerRadius: CGFloat = 22

    /// Trazado del panel. Lo comparten el fondo y el recorte del contenido: si
    /// cada uno llevara el suyo, cambiar el radio en un sitio y olvidarlo en el
    /// otro dejaría filas asomando por la esquina.
    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
    }

    private var sidebarSurface: some View {
        panelShape
            .fill(.ultraThinMaterial)
            .overlay(panelShape.strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5))
    }

    /// Muestra u oculta la barra. Sustituye al botón que ponía
    /// `NavigationSplitView`, que se fue con él.
    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.22)) {
                if horizontalSizeClass == .compact {
                    showCompactSidebar.toggle()
                } else {
                    visibility = visibility == .detailOnly ? .all : .detailOnly
                }
            }
        } label: {
            Image(systemName: "sidebar.leading")
        }
    }

    /// Ventana estrecha: la barra lateral entra y sale, no se queda.
    ///
    /// Aquí NO se usa `NavigationSplitView`. Al colapsar en ancho compacto, la
    /// raíz de su pila pasa a ser la barra lateral, y lo único que la aparta
    /// para enseñar el detalle es un `NavigationLink`. Estas filas son botones
    /// —cambian la carpeta abierta sin navegar—, así que la barra se quedaba
    /// ocupando la ventana entera: tocabas una ubicación, el contenido cambiaba
    /// detrás sin que se viera, y la app parecía muerta.
    ///
    /// Convertir las filas en `NavigationLink` no serviría: varias no navegan a
    /// ninguna parte (abren el selector, la papelera, la ayuda de montaje). La
    /// barra pasa a ser un panel que se retira al elegir algo, que es lo que
    /// hacen Archivos y el Finder en una ventana estrecha.
    private var compactLayout: some View {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) { sidebarToggle }
                    }
            }

            if showCompactSidebar {
                // velo: tocar fuera cierra, como cualquier panel de iPadOS
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.22)) { showCompactSidebar = false }
                    }
                    .transition(.opacity)

                // `ultraThin` y no `regular`: la barra se ha visto siempre
                // translúcida, dejando entrever lo que hay detrás, y con el
                // material grueso parecía otra pantalla encima.
                sidebar
                    .frame(width: sidebarPanelWidth(in: geo.size.width))
                    .clipShape(panelShape)
                    .background(sidebarSurface)
                    .padding(8)
                    .ignoresSafeArea(.container, edges: .vertical)
                    .shadow(color: .black.opacity(0.28), radius: 14, x: 3)
                    .transition(.move(edge: .leading))
            }
          }
        }
        // Elegir una ubicación la retira sola: en una ventana estrecha el panel
        // tapa justo lo que acabas de abrir.
        .onChange(of: model.currentURL) { _, _ in
            withAnimation(.easeOut(duration: 0.22)) { showCompactSidebar = false }
        }
    }

    /// Barra lateral: `ScrollView` + `VStack`, no una `List`.
    ///
    /// `List` impone lo que aquí sobra —separadores, recuadro por sección,
    /// márgenes propios— y esconderlo pieza a pieza no basta: siempre queda
    /// alguna línea, como la que asomaba entre secciones. Un VStack no dibuja
    /// nada que no se le pida, así que el problema desaparece de raíz en vez de
    /// taparse.
    ///
    /// Lo que se pierde de `List` no se usaba: la selección la lleva
    /// `isCurrent`, atada a la carpeta abierta, y las filas son botones.
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // Nubes montadas: Drive, OneDrive de cada universidad, Dropbox…
                if !local.mounts.isEmpty {
                    sidebarSection("Nubes") {
                        ForEach(local.mounts) { mountRow($0) }
                    }
                }

                sidebarSection("Favoritos") {
                    ForEach(local.plainFolders) { mountRow($0) }
                    sidebarButton(title: "Archivos de ZeroSpin",
                                  systemImage: "iphone",
                                  isSelected: isCurrent(documentsURL)) {
                        Task { await openLocal(documentsURL) }
                    }
                }

                sidebarSection("Ubicaciones") {
                    ForEach(SystemLocation.allCases) { location in
                        sidebarButton(title: location.title,
                                      systemImage: location.icon,
                                      dimmed: !isReachable(location),
                                      isSelected: isCurrent(location.url)) {
                            open(location)
                        }
                    }
                    sidebarButton(title: "Añadir carpeta…",
                                  systemImage: "plus.circle", tint: .cyan) {
                        pickerStart = nil
                        showFolderPicker = true
                    }
                    sidebarButton(title: "Montar nube…",
                                  systemImage: "externaldrive.badge.plus", tint: .cyan) {
                        showMountHelp = true
                    }
                    sidebarButton(title: model.trashCount > 0
                                      ? "Papelera (\(model.trashCount))" : "Papelera",
                                  systemImage: model.trashCount > 0 ? "trash.fill" : "trash",
                                  tint: .secondary) {
                        showTrash = true
                    }
                }

                if !servers.servers.isEmpty {
                    sidebarSection("Computadoras") {
                        ForEach(servers.servers) { server in
                            SidebarRow(title: server.name,
                                       systemImage: server.dockerMachineName.isEmpty
                                           ? "desktopcomputer" : "shippingbox.fill",
                                       dimmed: true)
                                .padding(.horizontal, 10)
                        }
                    }
                }
            }
            // Hueco para el semáforo. iPadOS dibuja los botones de la ventana
            // FLOTANDO sobre el contenido, en esta misma esquina, y no publica
            // dónde: no hay safe area que consultar. Sin este margen el primer
            // encabezado —"Nubes"— quedaba justo debajo de ellos.
            .padding(.top, 40)
            // La curva de la esquina se come la banda inferior: con poco aire,
            // la última fila quedaba cortada por la mitad al llegar al final.
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    /// Encabezado de sección y sus filas.
    ///
    /// Sustituye a `Section` de `List`, que era quien traía el recuadro y las
    /// líneas. El encabezado vive en su propia vista para poder saber si tiene
    /// el puntero encima y enseñar el chevron solo entonces.
    @ViewBuilder
    private func sidebarSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        let collapsed = collapsedSections.contains(title)
        VStack(alignment: .leading, spacing: 2) {
            SidebarSectionHeader(title: title, collapsed: collapsed) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsed { collapsedSections.remove(title) }
                    else { collapsedSections.insert(title) }
                }
            }
            if !collapsed { content() }
        }
    }

    /// Fila pulsable de la barra.
    ///
    /// El margen exterior de 10 pt es lo que hace que la burbuja flote: la fila
    /// dibuja su fondo redondeado dentro de ese margen, así que nunca llega a
    /// tocar los bordes de la barra.
    private func sidebarButton(title: String,
                               systemImage: String,
                               tint: Color = .accentColor,
                               dimmed: Bool = false,
                               isSelected: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SidebarRow(title: title, systemImage: systemImage,
                       tint: tint, dimmed: dimmed, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    /// Sin este respiro, iPadOS descarta la presentación sin avisar: hay dos
    /// intentos de presentar a la vez y gana el que ya estaba.
    private func present(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: action)
    }

    /// ¿Es una carpeta? Se comprueba con el ámbito abierto: sin él, un
    /// recurso de un proveedor externo responde que no existe.
    private func isDirectory(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
           let isDir = values.isDirectory {
            return isDir
        }
        // algunos proveedores no responden a los valores de recurso: se
        // pregunta al FileManager antes de rendirse
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return url.hasDirectoryPath
    }

    /// Guarda el permiso con el nombre elegido y entra en la carpeta.
    private func save(_ url: URL, as name: String) {
        guard local.add(url: url, named: name) != nil else {
            model.error = "No pude guardar el permiso de esa carpeta. Elige la ubicación desde la barra lateral del selector."
            return
        }
        Task { await openLocal(url) }
    }

    // MARK: - Enrutado de la barra lateral

    /// ¿Es esta la ubicación abierta ahora mismo?
    ///
    /// La burbuja sigue a dónde ESTÁS, no a lo último que tocaste: entrar en
    /// una subcarpeta o volver atrás cambia el resaltado solo, y una fila que
    /// no llevó a ninguna parte no se queda marcada.
    private func isCurrent(_ url: URL?) -> Bool {
        guard let url, let current = model.currentURL else { return false }
        return url.standardizedFileURL == current.standardizedFileURL
    }

    /// ¿Se puede entrar sin pedir permiso? (ruta nativa o ya concedida)
    private func isReachable(_ location: SystemLocation) -> Bool {
        location.url != nil || local.folder(named: location.title) != nil
    }

    /// Las ubicaciones del sistema **navegan**; solo piden el selector la
    /// primera vez, y únicamente si el sandbox no expone su ruta.
    private func open(_ location: SystemLocation) {
        // 1. ruta nativa: entrada directa, sin preguntar nada
        if let url = location.url {
            Task { await openLocal(url) }
            return
        }
        // 2. concedida en una sesión anterior: también directa
        if let folder = local.folder(named: location.title),
           let url = local.url(for: folder) {
            Task { await openLocal(url) }
            return
        }
        // 3. primera vez: se pide permiso y se recuerda para no repetirlo
        pendingLocation = location
        pickerStart = nil
        showFolderPicker = true
    }

    /// Fila de una nube montada o de una carpeta concedida.
    @ViewBuilder
    private func mountRow(_ folder: LocalStore.Folder) -> some View {
        let stale = local.staleFolders.contains(folder.id)
        Button {
            if let url = local.url(for: folder) {
                Task { await openLocal(url) }
            } else {
                // el proveedor invalidó el permiso: hay que volver a concederlo
                pickerStart = nil
                showFolderPicker = true
            }
        } label: {
            SidebarRow(title: folder.name,
                       systemImage: stale ? "exclamationmark.triangle.fill" : folder.kind.icon,
                       tint: stale ? .orange : folder.kind.tint,
                       isSelected: isCurrent(local.resolvedURL(for: folder)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .contextMenu {
            Button { renamingMount = folder; mountName = folder.name } label: {
                Label("Renombrar", systemImage: "pencil")
            }
            Button(role: .destructive) { local.remove(folder) } label: {
                Label("Quitar de la barra lateral", systemImage: "minus.circle")
            }
        }
    }

    // MARK: - Contenido

    private var content: some View {
        HStack(spacing: 0) {
            // Asa de la barra lateral. NavigationSplitView no deja arrastrar su
            // divisor, pero sí respeta el ancho ideal que se le dé: moviendo
            // esta asa se cambia ese valor y la barra sigue al dedo.
            if horizontalSizeClass == .regular, visibility != .detailOnly {
                ResizableDivider(width: $sidebarWidth, range: 150...420, resetTo: 220)
            }
            VStack(spacing: 0) {
                toolbar
                Divider()
                Group {
                    // Se respeta SIEMPRE la vista elegida, también en ventana
                    // estrecha. Antes se forzaba la lista, así que tocar
                    // "columnas" en la barra no hacía nada: el selector seguía
                    // marcándola y la pantalla no cambiaba. Las columnas se
                    // deslizan de lado, que es justo lo que sirve en estrecho.
                    switch model.viewMode {
                    case .icons:
                        if let level = model.levels.indices.last { IconsView(model: model, level: level) }
                    case .list:
                        if let level = model.levels.indices.last { DetailListView(model: model, level: level) }
                    case .columns:
                        ColumnsBrowserView(model: model, columnWidth: columnWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // el fondo va DETRÁS del listado, no del panel lateral ni de
                // las barras: esas son cromo y deben seguir legibles
                .background(WallpaperBackground())
                Divider()
                statusBar
            }
            // el panel aparece solo con algo seleccionado: al deseleccionar
            // desaparece por completo y el contenido recupera el ancho
            if showInspector,
               horizontalSizeClass == .regular,
               let selected = model.inspecting ?? model.selectedItems.first {
                ResizableDivider(width: $inspectorWidth, range: 200...520,
                                 growsLeading: true, resetTo: 260)
                InspectorPanel(model: model, item: selected,
                               onPreview: { openPreview($0) })
                    .frame(width: inspectorWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .navigationTitle(model.currentURL?.lastPathComponent ?? "ZeroSpin")
        .navigationBarTitleDisplayMode(.inline)
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
        .onKeyPress(.space) { toggleQuickLook() ? .handled : .ignored }
    }

    /// Espacio: abre la vista rápida, o la cierra si ya está abierta.
    ///
    /// - Returns: `false` si no había nada que hacer, para que la tecla siga
    ///   su camino (por ejemplo hacia un campo de texto).
    @discardableResult
    private func toggleQuickLook() -> Bool {
        // no robarle el espacio a un campo de texto (renombrar)
        guard model.renaming == nil else { return false }
        // con una previa abierta, el espacio la cierra aunque no haya nada
        // seleccionado, igual que en macOS
        if let open = previewState.openURLs.first {
            dismissWindow(id: PreviewScene.id, value: open)
            previewState.closed(open)
            return true
        }
        guard let item = model.selectedItems.first, !item.isDirectory else { return false }
        openPreview(item)
        return true
    }

    /// Abre (o reutiliza) la ventana de vista previa con el archivo elegido.
    private func openPreview(_ item: FileItem) {
        AppLaunch.markPreviewRequested()
        // el archivo viaja como valor: la ventana nueva es independiente
        openWindow(id: PreviewScene.id, value: item.url)
    }

    /// Aviso de "estoy trabajando" de la barra de herramientas.
    ///
    /// El nombre del archivo va SIEMPRE en una línea y recortado por el medio.
    /// Sin `lineLimit`, un nombre largo como el de un perfil de VPN no cabía en
    /// el hueco que deja la barra y SwiftUI lo partía carácter a carácter: una
    /// columna vertical de letras que además empujaba el resto de los botones.
    ///
    /// El ancho tiene tope propio para que el aviso ceda espacio a los botones
    /// y no al revés — el buscador y los iconos deben seguir alcanzables.
    private func statusLabel(_ verb: String, _ name: String) -> some View {
        HStack(spacing: 5) {
            ProgressView().controlSize(.small)
            Text("\(verb) \(name)…")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 220, alignment: .trailing)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            // Se apaga al llegar al tope de lo concedido: un botón que lleva a
            // una carpeta sin permiso es peor que un botón apagado.
            Button { Task { await model.goUp() } } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoUp)
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
                statusLabel("Abriendo", name)
            } else if let name = model.downloadingName {
                statusLabel("Bajando", name)
            } else if model.busy {
                ProgressView().controlSize(.small)
            }

            SearchField(text: $model.searchText)

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
                Picker("Barra lateral", selection: $sidebarWidth) {
                    Text("Estrecha").tag(170.0)
                    Text("Normal").tag(220.0)
                    Text("Ancha").tag(300.0)
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
            // El espacio también aquí: .onKeyPress solo llega si el área de
            // archivos tiene el foco, y basta tocar la barra lateral para
            // perderlo. Este atajo vive en la ventana y siempre responde.
            Button("") { toggleQuickLook() }
                .keyboardShortcut(.space, modifiers: [])
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
