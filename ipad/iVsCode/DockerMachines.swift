import SwiftUI
import UniformTypeIdentifiers

struct DockerMachine: Identifiable, Codable, Equatable {
    let name: String
    let os: String
    let status: String
    let url: String
    let port: Int

    var id: String { name }
    var running: Bool { status == "running" }

    var osLabel: String {
        ["ubuntu": "Ubuntu 24.04", "debian": "Debian 12",
         "fedora": "Fedora 41", "arch": "Arch Linux"][os] ?? os
    }
}

/// Cliente del gestor de máquinas que corre serve.sh en cada PC (puerto 9500).
struct ManagerClient {
    let baseURL: URL
    let password: String

    private func request(_ method: String, _ path: String,
                         body: [String: String]? = nil,
                         timeout: TimeInterval = 30) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue(password, forHTTPHeaderField: "X-Password")
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw NSError(domain: "manager", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "error \(http.statusCode)"])
        }
        return data
    }

    func machines() async throws -> [DockerMachine] {
        struct Response: Codable { let machines: [DockerMachine] }
        let data = try await request("GET", "machines")
        return try JSONDecoder().decode(Response.self, from: data).machines
    }

    func create(name: String, os: String) async throws {
        // la primera máquina de cada OS descarga la imagen base: puede tardar
        _ = try await request("POST", "machines", body: ["name": name, "os": os], timeout: 300)
    }

    func start(_ name: String) async throws { _ = try await request("POST", "machines/\(name)/start") }
    func stop(_ name: String) async throws { _ = try await request("POST", "machines/\(name)/stop") }

    /// Elimina el contenedor; con removeVolume también borra su disco (/root).
    func delete(_ name: String, removeVolume: Bool = false) async throws {
        var comps = URLComponents(url: baseURL.appendingPathComponent("machines/\(name)"),
                                  resolvingAgainstBaseURL: false)!
        if removeVolume { comps.queryItems = [URLQueryItem(name: "volume", value: "1")] }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 60
        req.setValue(password, forHTTPHeaderField: "X-Password")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw NSError(domain: "manager", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "error \(http.statusCode)"])
        }
    }

    /// Portapapeles de archivos entre sesiones del mismo PC.
    /// op = "copy" (con path) o "paste" (con dest opcional); machine = "" para el host.
    /// Devuelve (archivos, carpeta destino real).
    func clipboard(op: String, path: String? = nil, dest: String? = nil,
                   machine: String) async throws -> ([String], String) {
        struct Result: Codable { let files: [String]; let dest: String? }
        var body = ["op": op, "machine": machine]
        if let path { body["path"] = path }
        if let dest { body["dest"] = dest }
        let data = try await request("POST", "clipboard", body: body, timeout: 120)
        let r = try? JSONDecoder().decode(Result.self, from: data)
        return (r?.files ?? [], r?.dest ?? "")
    }

    /// Sube un archivo (arrastrado desde Archivos/Fotos) al host o a una máquina.
    func upload(data: Data, filename: String, machine: String, dest: String = "") async throws -> String {
        struct Result: Codable { let file: String?; let dest: String? }
        var req = URLRequest(url: baseURL.appendingPathComponent("upload"))
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue(password, forHTTPHeaderField: "X-Password")
        req.setValue(filename, forHTTPHeaderField: "X-Filename")
        req.setValue(machine, forHTTPHeaderField: "X-Machine")
        req.setValue(dest, forHTTPHeaderField: "X-Dest")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (respData, response) = try await URLSession.shared.upload(for: req, from: data)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: respData))?["error"]
            throw NSError(domain: "manager", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "error \(http.statusCode)"])
        }
        let r = try? JSONDecoder().decode(Result.self, from: respData)
        return r?.dest ?? ""
    }

    /// Descarga un archivo (para arrastrarlo a Archivos o guardarlo).
    func download(path: String, machine: String) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent("download"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "machine", value: machine),
                            URLQueryItem(name: "path", value: path)]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 300
        req.setValue(password, forHTTPHeaderField: "X-Password")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw NSError(domain: "manager", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "error \(http.statusCode)"])
        }
        return data
    }

    /// Lista un directorio del host (machine: "") o de una máquina Docker.
    func fsList(machine: String, path: String) async throws -> (String, [FSEntry]) {
        struct Result: Codable { let path: String; let entries: [FSEntry] }
        var comps = URLComponents(url: baseURL.appendingPathComponent("fs/list"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "machine", value: machine),
                            URLQueryItem(name: "path", value: path)]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 30
        req.setValue(password, forHTTPHeaderField: "X-Password")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw NSError(domain: "manager", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: msg ?? "error \(http.statusCode)"])
        }
        let r = try JSONDecoder().decode(Result.self, from: data)
        return (r.path, r.entries)
    }
}

struct FSEntry: Codable, Identifiable {
    let name: String
    let dir: Bool
    var id: String { name }
}

/// Explorador nativo para elegir qué archivo/carpeta copiar entre sesiones (⌃⌥C).
struct FilePickerView: View {
    let server: Server
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var path = "~"
    @State private var entries: [FSEntry] = []
    @State private var loading = true
    @State private var errorMsg: String?

    private var client: ManagerClient? {
        guard let url = server.managerURL,
              let pw = Keychain.password(for: server.id) else { return nil }
        return ManagerClient(baseURL: url, password: pw)
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading && entries.isEmpty {
                    ProgressView()
                } else if let errorMsg {
                    VStack(spacing: 10) {
                        Text(errorMsg).font(.footnote).foregroundStyle(.secondary)
                        Button("Reintentar") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                } else {
                    List {
                        if path != "/" {
                            Button {
                                path = (path as NSString).deletingLastPathComponent
                                if path.isEmpty { path = "/" }
                                Task { await load() }
                            } label: {
                                Label("..", systemImage: "arrow.up.doc.on.clipboard")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(entries) { entry in
                            let fullPath = path == "/" ? "/\(entry.name)" : "\(path)/\(entry.name)"
                            Button {
                                let full = path == "/" ? "/\(entry.name)" : "\(path)/\(entry.name)"
                                if entry.dir {
                                    path = full
                                    Task { await load() }
                                } else {
                                    onPick(full)
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: entry.dir ? "folder.fill" : "doc")
                                        .foregroundStyle(entry.dir ? .cyan : .secondary)
                                    Text(entry.name)
                                    Spacer()
                                    if entry.dir {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                            // arrastrar el archivo fuera de la app (Archivos,
                            // Correo, Fotos…): se descarga bajo demanda
                            .if(!entry.dir) { view in
                                view.onDrag {
                                    dragProvider(name: entry.name, path: fullPath)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(path == "~" ? "Archivos de \(server.name)" : (path as NSString).lastPathComponent)
            .safeAreaInset(edge: .bottom) {
                Text("Toca un archivo para copiarlo · mantén pulsado y arrástralo a Archivos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copiar esta carpeta") {
                        onPick(path)
                        dismiss()
                    }
                    .disabled(path == "~" || path == "/")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    /// Promesa de archivo: iPadOS pide el contenido solo cuando sueltas.
    private func dragProvider(name: String, path: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier,
                                            fileOptions: [],
                                            visibility: .all) { completion in
            Task {
                do {
                    guard let client else {
                        throw NSError(domain: "manager", code: 0,
                                      userInfo: [NSLocalizedDescriptionKey: "sin gestor"])
                    }
                    let data = try await client.download(path: path,
                                                         machine: server.dockerMachineName)
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(name)
                    try data.write(to: tmp)
                    completion(tmp, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    private func load() async {
        guard let client else {
            errorMsg = "Este servidor no tiene gestor (¿contraseña guardada?)"
            loading = false
            return
        }
        loading = true
        do {
            let (resolved, list) = try await client.fsList(machine: server.dockerMachineName, path: path)
            path = resolved
            entries = list
            errorMsg = nil
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }
}

extension Server {
    /// Si este servidor es una máquina Docker (URL …/m-<nombre>/), su nombre.
    var dockerMachineName: String {
        guard let range = urlString.range(of: "/m-") else { return "" }
        return String(urlString[range.upperBound...].prefix { $0 != "/" })
    }
}

extension Server {
    /// Por convención, el gestor de máquinas vive en el puerto 9500 del mismo host.
    var managerURL: URL? {
        guard var comps = URLComponents(string: urlString), comps.scheme == "https" else { return nil }
        comps.port = 9500
        comps.path = ""
        comps.query = nil       // ?folder=… se colaba y rompía las peticiones
        comps.fragment = nil
        return comps.url
    }
}

struct DockerMachinesView: View {
    let server: Server
    @ObservedObject var store: ServerStore
    var onConnect: (Server) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var machines: [DockerMachine] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var busy: Set<String> = []
    @State private var deleteTarget: DockerMachine?
    @State private var showCreate = false
    @State private var newName = ""
    @State private var newOS = "ubuntu"
    @State private var creating = false

    private var client: ManagerClient? {
        guard let url = server.managerURL,
              let pw = Keychain.password(for: server.id) else { return nil }
        return ManagerClient(baseURL: url, password: pw)
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading && machines.isEmpty {
                    ProgressView("Consultando máquinas…")
                } else if let errorMsg, machines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(errorMsg)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Reintentar") { Task { await refresh() } }
                            .buttonStyle(.bordered)
                    }
                    .padding(30)
                } else {
                    list
                }
            }
            .navigationTitle("Máquinas · \(server.name)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Label("Nueva", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreate) { createSheet }
            .alert("No se pudo completar la acción",
                   isPresented: Binding(get: { errorMsg != nil && !machines.isEmpty },
                                        set: { if !$0 { errorMsg = nil } })) {
                Button("Entendido", role: .cancel) { errorMsg = nil }
            } message: {
                Text(errorMsg ?? "")
            }
            .confirmationDialog(
                "¿Eliminar la máquina?",
                isPresented: Binding(get: { deleteTarget != nil },
                                     set: { if !$0 { deleteTarget = nil } }),
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { m in
                Button("Eliminar todo (máquina + disco)", role: .destructive) {
                    Task {
                        await action(m.name) { try await client?.delete(m.name, removeVolume: true) }
                        removeSavedCard(for: m)
                    }
                }
                Button("Eliminar máquina, conservar disco") {
                    Task {
                        await action(m.name) { try await client?.delete(m.name, removeVolume: false) }
                        removeSavedCard(for: m)
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: { m in
                Text("\"\(m.name)\" (\(m.osLabel)). El disco guarda todo lo que hay en /root — programas instalados y archivos. Si lo conservas, una máquina nueva con el mismo nombre lo heredará.")
            }
            .task { await refresh() }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(machines) { m in
                    machineRow(m)
                }
            } footer: {
                Text("Cada máquina es un contenedor Docker en \(server.name) con su propio VS Code. Su disco persiste aunque la detengas.")
            }
        }
        .refreshable { await refresh() }
    }

    private func machineRow(_ m: DockerMachine) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(m.running ? .cyan : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).font(.headline)
                HStack(spacing: 6) {
                    Text(m.osLabel)
                    Circle().frame(width: 6, height: 6)
                        .foregroundStyle(m.running ? .green : .orange)
                    Text(m.running ? "encendida" : "detenida")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if busy.contains(m.name) {
                ProgressView()
            } else if m.running {
                Button("Abrir") { connect(m) }
                    .buttonStyle(.borderedProminent)
                Button {
                    Task { await action(m.name) { try await client?.stop(m.name) } }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            } else {
                Button("Iniciar") {
                    Task { await action(m.name) { try await client?.start(m.name) } }
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteTarget = m
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteTarget = m
            } label: {
                Label("Eliminar…", systemImage: "trash")
            }
        }
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("mi-maquina", text: $newName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Picker("Sistema operativo", selection: $newOS) {
                        Text("Ubuntu 24.04").tag("ubuntu")
                        Text("Debian 12").tag("debian")
                        Text("Fedora 41").tag("fedora")
                        Text("Arch Linux").tag("arch")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Sistema operativo")
                } footer: {
                    Text("La primera máquina de cada OS descarga su imagen base (unos segundos con buena conexión). El VS Code lo pone el host: la creación es casi instantánea después.")
                }
            }
            .navigationTitle("Nueva máquina")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if creating {
                        ProgressView()
                    } else {
                        Button("Crear") {
                            Task { await createMachine() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showCreate = false }
                        .disabled(creating)
                }
            }
            .interactiveDismissDisabled(creating)
        }
    }

    private func refresh() async {
        guard let client else {
            errorMsg = "Este PC no tiene gestor de máquinas (requiere serve.sh con Docker y contraseña guardada)."
            loading = false
            return
        }
        loading = true
        do {
            machines = try await client.machines()
            errorMsg = nil
        } catch {
            errorMsg = "No pude hablar con el gestor: \(error.localizedDescription)"
        }
        loading = false
    }

    private func action(_ name: String, _ op: () async throws -> Void) async {
        busy.insert(name)
        do {
            try await op()
        } catch {
            errorMsg = error.localizedDescription
        }
        busy.remove(name)
        await refresh()
    }

    private func createMachine() async {
        guard let client else { return }
        creating = true
        do {
            try await client.create(name: newName.trimmingCharacters(in: .whitespaces), os: newOS)
            showCreate = false
            newName = ""
        } catch {
            errorMsg = error.localizedDescription
        }
        creating = false
        await refresh()
    }

    /// Al eliminar la máquina, borra también su tarjeta guardada en el launcher.
    private func removeSavedCard(for m: DockerMachine) {
        let displayName = "\(m.name) · \(server.name)"
        for saved in store.servers where saved.urlString == m.url || saved.name == displayName {
            store.delete(saved)
        }
    }

    private func connect(_ m: DockerMachine) {
        // reutiliza el servidor si ya existe (por URL o por nombre) y actualiza
        // su URL si el backend cambió el esquema; la clave se hereda del PC
        let displayName = "\(m.name) · \(server.name)"
        var target = store.servers.first { $0.urlString == m.url }
            ?? store.servers.first { $0.name == displayName }
            ?? Server(name: displayName, urlString: m.url)
        target.urlString = m.url
        let password = Keychain.password(for: target.id)
            ?? Keychain.password(for: server.id) ?? ""
        store.upsert(target, password: password)
        dismiss()
        onConnect(target)
    }
}

extension View {
    /// Aplica un modificador solo si se cumple la condición.
    @ViewBuilder func `if`<T: View>(_ condition: Bool,
                                    transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
