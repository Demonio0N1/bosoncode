import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case auto, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .auto: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .auto: return "Automático"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    var icon: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

struct ContentView: View {
    @StateObject private var store = ServerStore.shared
    @State private var showLauncher = true
    @State private var loadError: String?
    @State private var reloadToken = UUID()
    @State private var downloadToast: String?
    @State private var toastToken = UUID()
    @State private var editorDropTargeted = false
    @State private var showFilePicker = false
    @State private var showTerminal = false
    @State private var connecting = true
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.auto.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openWindow) private var openWindow

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    var body: some View {
        ZStack {
            (systemScheme == .dark ? Color.black : Color(white: 0.96))
                .ignoresSafeArea()

            if let server = store.active, let url = server.url {
                CodeWebView(
                    url: url,
                    dataStoreID: server.id,
                    server: server,
                    interfaceStyle: appearance.interfaceStyle,
                    password: Keychain.password(for: server.id),
                    onOpenSettings: { withAnimation { showLauncher = true } },
                    onLoadError: { loadError = $0 },
                    onPasswordEntered: { pw in
                        Keychain.setPassword(pw, for: server.id)
                    },
                    onDownload: { filename in
                        showToast("Guardado en Archivos › iVsCode › Descargas: \(filename)")
                    },
                    onFileCopy: {
                        // el WebView ya disparó Copy Path; la ruta llega vía
                        // ClipboardBridge a UIPasteboard
                        let path = (UIPasteboard.general.string ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if path.hasPrefix("/"), !path.contains("\n") {
                            Task { await fileCopy(path: path, server: server) }
                        } else {
                            showToast("Selecciona el archivo en el explorador y pulsa ⌃⌥C de nuevo")
                        }
                    },
                    onFilePaste: {
                        Task { await filePaste(server: server) }
                    },
                    onTerminalToggle: {
                        // ⌃⌥T abre la terminal como ventana independiente de
                        // iPadOS (no el panel dentro de la app)
                        TerminalScene.open(serverID: server.id)
                    },
                    onLoading: { stillOnLogin in
                        withAnimation { connecting = stillOnLogin }
                    }
                )
                // incluir la URL en la identidad: si una tarjeta se repara
                // (URL nueva), el WebView se recrea sí o sí
                .id("\(server.id.uuidString)-\(server.urlString)-\(reloadToken.uuidString)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // el teclado en pantalla no debe encoger el editor: VS Code
                // gestiona su propio desplazamiento
                .ignoresSafeArea(.all)
                // arrastrar archivos del iPad al editor: se suben a la carpeta
                // de trabajo de la sesión
                .onDrop(of: ["public.data"], isTargeted: $editorDropTargeted) { providers in
                    uploadDropped(providers, to: server)
                }
                .overlay(alignment: .center) {
                    if editorDropTargeted {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 4, dash: [12]))
                            .background(Color.cyan.opacity(0.07))
                            .overlay(
                                Label("Soltar para subir a \(server.name)",
                                      systemImage: "arrow.down.doc.fill")
                                    .font(.title3.bold())
                                    .foregroundStyle(.cyan))
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }

                if !showLauncher {
                    // botón flotante: toque = lista de PCs; mantener pulsado =
                    // copiar/pegar archivos entre sesiones
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Menu {
                                Button {
                                    TerminalScene.open(serverID: server.id)
                                } label: {
                                    Label("Terminal en ventana propia (⌃⌥T)",
                                          systemImage: "macwindow.on.rectangle")
                                }
                                Button {
                                    withAnimation { showTerminal.toggle() }
                                } label: {
                                    Label(showTerminal ? "Cerrar panel dentro de la app"
                                                       : "Terminal dentro de la app",
                                          systemImage: "terminal")
                                }
                                Button {
                                    showFilePicker = true
                                } label: {
                                    Label("Explorar archivos (copiar o arrastrar fuera)",
                                          systemImage: "folder")
                                }
                                Button {
                                    Task { await filePaste(server: server) }
                                } label: {
                                    Label("Pegar aquí (⌃⌥V)",
                                          systemImage: "doc.on.clipboard")
                                }
                            } label: {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 42, height: 42)
                                    .background(.black.opacity(0.45), in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.15)))
                            } primaryAction: {
                                withAnimation { showLauncher = true }
                            }
                            .padding(.trailing, 12)
                            .padding(.bottom, 12)
                        }
                    }
                }
            }

            if showTerminal, let server = store.active {
                // en Slide Over (ancho compacto) la terminal ocupa todo:
                // la app se convierte en una terminal pura sobre otras apps
                FloatingTerminal(server: server,
                                 fullscreen: horizontalSizeClass == .compact) {
                    withAnimation { showTerminal = false }
                }
                .id("term-\(server.id.uuidString)")
                // al abrir "Mis PCs" solo se OCULTA: si se desmontara, moriría
                // la sesión del shell y se perdería el scrollback
                .opacity(showLauncher ? 0 : 1)
                .allowsHitTesting(!showLauncher)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if connecting, !showLauncher, loadError == nil, let server = store.active {
                connectingOverlay(server.name)
            }

            if let error = loadError, !showLauncher {
                errorOverlay(error)
            }

            if let toast = downloadToast {
                VStack {
                    Label(toast, systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.green.opacity(0.85), in: Capsule())
                        .padding(.top, 18)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if showLauncher {
                LauncherView(
                    store: store,
                    canClose: store.active != nil,
                    onConnect: { server in
                        let sameServer = store.activeID == server.id
                        store.activeID = server.id
                        // tocar el MISMO servidor tras un error también debe
                        // recargar (antes se quedaba con el overlay de error)
                        if !sameServer || loadError != nil {
                            loadError = nil
                            connecting = true      // pantalla "Conectando…"
                            reloadToken = UUID()
                        }
                        withAnimation { showLauncher = false }
                    }
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showFilePicker) {
            if let server = store.active {
                FilePickerView(server: server) { path in
                    Task { await fileCopy(path: path, server: server) }
                }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }

    /// Pantalla nativa mientras el auto-login trabaja: la página de login de
    /// code-server queda oculta y esto es lo único visible.
    private func connectingOverlay(_ name: String) -> some View {
        ZStack {
            LinearGradient(
                colors: systemScheme == .dark
                    ? [Color(red: 0.04, green: 0.05, blue: 0.10),
                       Color(red: 0.08, green: 0.10, blue: 0.20)]
                    : [Color(red: 0.93, green: 0.94, blue: 0.97),
                       Color(red: 0.85, green: 0.88, blue: 0.95)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                ProgressView()
                Text("Conectando a \(name)…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.opacity)
        .task(id: reloadToken) {
            // red de seguridad: si en 10s no llegó el workbench (p. ej.
            // contraseña incorrecta), se muestra lo que haya
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            // si la tarea se canceló (la vista se retiró), NO tocar el estado:
            // si no, la pantalla "Conectando…" desaparecía antes de tiempo
            guard !Task.isCancelled else { return }
            withAnimation { connecting = false }
        }
    }

    private func showToast(_ message: String) {
        // token de generación: un toast nuevo no debe ser borrado por el
        // temporizador del anterior
        let token = UUID()
        toastToken = token
        withAnimation { downloadToast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard toastToken == token else { return }
            withAnimation { downloadToast = nil }
        }
    }

    /// Sube al servidor los archivos arrastrados desde Archivos/Fotos.
    private func uploadDropped(_ providers: [NSItemProvider], to server: Server) -> Bool {
        guard let client = manager(for: server) else {
            showToast("Este servidor no admite subir archivos")
            return false
        }
        let machine = server.dockerMachineName
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, _ in
                guard let data else { return }
                let name = provider.suggestedName ?? "archivo"
                Task {
                    do {
                        let dest = try await client.upload(data: data, filename: name,
                                                           machine: machine, dest: "@cwd")
                        await MainActor.run { showToast("Subido: \(name) → \(dest)") }
                    } catch {
                        await MainActor.run {
                            showToast("Error subiendo \(name): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        return true
    }

    private func manager(for server: Server) -> ManagerClient? {
        guard let mgrURL = server.managerURL,
              let pw = ServerStore.shared.hostPassword(for: server) else { return nil }
        return ManagerClient(baseURL: mgrURL, password: pw)
    }

    /// ⌃⌥C: el usuario eligió una ruta en el explorador nativo → se copia al
    /// portapapeles de archivos del PC (docker cp si la sesión es una máquina)
    private func fileCopy(path: String, server: Server) async {
        guard let client = manager(for: server) else {
            showToast("Este servidor no soporta copiar archivos entre sesiones")
            return
        }
        do {
            let (files, _) = try await client.clipboard(op: "copy", path: path,
                                                        machine: server.dockerMachineName)
            showToast("Copiado: \(files.joined(separator: ", ")) — usa ⌃⌥V en otra sesión")
        } catch {
            showToast("Error: \(error.localizedDescription)")
        }
    }

    /// ⌃⌥V: pega en la carpeta seleccionada de la sesión (el WebView ya capturó
    /// la selección al portapapeles); sin selección válida, en la de inicio
    private func filePaste(server: Server) async {
        guard let client = manager(for: server) else {
            showToast("Este servidor no soporta pegar archivos entre sesiones")
            return
        }
        let dest = (UIPasteboard.general.string ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let (files, target) = try await client.clipboard(
                op: "paste",
                dest: dest.hasPrefix("/") && !dest.contains("\n") ? dest : nil,
                machine: server.dockerMachineName
            )
            showToast("Pegado en \(target): \(files.joined(separator: ", "))")
        } catch {
            showToast("Error: \(error.localizedDescription)")
        }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Sin conexión con \(store.active?.name ?? "el backend")")
                .font(.title3.bold())
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Reintentar") {
                    loadError = nil
                    reloadToken = UUID()
                }
                .buttonStyle(.borderedProminent)
                Button("Mis PCs") { withAnimation { showLauncher = true } }
                    .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
