import SwiftUI
import UniformTypeIdentifiers

/// Una columna del explorador (una carpeta abierta).
struct FinderColumn: Identifiable {
    let id = UUID()
    let path: String
    var items: [FinderItem]
    var selection: String?
}

/// Elemento transferible: permite arrastrar archivos fuera de la app (a
/// Archivos, Correo…) y también entre columnas. El contenido se descarga
/// solo cuando el destino lo pide.
struct FinderTransfer: Codable, Transferable {
    let serverID: UUID
    let machine: String
    let path: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        // representación de archivo: al soltar en Archivos llega el archivo real
        FileRepresentation(exportedContentType: .data) { transfer in
            let url = try await FinderTransferLoader.file(for: transfer)
            return SentTransferredFile(url)
        }
        // y como dato propio para mover entre columnas sin descargar
        CodableRepresentation(contentType: .ivscodeItem)
    }
}

extension UTType {
    static let ivscodeItem = UTType(exportedAs: "com.garyguaman.ivscode.item")
}

enum FinderTransferLoader {
    static func file(for transfer: FinderTransfer) async throws -> URL {
        guard let server = ServerStore.shared.servers.first(where: { $0.id == transfer.serverID }),
              let mgr = server.managerURL,
              let pw = Keychain.password(for: server.id) else {
            throw NSError(domain: "finder", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "servidor no disponible"])
        }
        let client = ManagerClient(baseURL: mgr, password: pw)
        let data = try await client.download(path: transfer.path, machine: transfer.machine)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(transfer.name)
        try data.write(to: url)
        return url
    }
}

@MainActor
final class FinderModel: ObservableObject {
    @Published var favorites: [FinderLocation] = []
    @Published var locations: [FinderLocation] = []
    @Published var localLocations: [FinderLocation] = []
    @Published var columns: [FinderColumn] = []
    @Published var location: FinderLocation?
    @Published var loading = false
    @Published var error: String?

    private var store: ServerStore?
    private var localStore: LocalStore?

    var title: String { location?.name ?? "iFinder" }
    var currentPath: String { columns.last?.path ?? "" }

    func attach(store: ServerStore, local: LocalStore) {
        self.store = store
        self.localStore = local
        rebuildLocations()
    }

    /// Vuelve a componer la lista tras conceder o quitar una carpeta.
    func refreshLocal() { rebuildLocations() }

    private func rebuildLocations() {
        guard let store else { return }
        locations = store.servers.map { server in
            FinderLocation(
                name: server.name,
                icon: server.dockerMachineName.isEmpty ? "desktopcomputer" : "shippingbox.fill",
                kind: .remote(serverID: server.id, machine: server.dockerMachineName),
                path: server.dockerMachineName.isEmpty ? "~" : "/root")
        }
        if let first = store.servers.first(where: { $0.dockerMachineName.isEmpty }) {
            favorites = ["Desktop", "Documents", "Downloads"].map { folder in
                FinderLocation(name: folder,
                               icon: folder == "Downloads" ? "arrow.down.circle" : "folder",
                               kind: .remote(serverID: first.id, machine: ""),
                               path: "~/\(folder)")
            }
        }
        var locals = [
            FinderLocation(name: "Archivos de iFinder", icon: "iphone",
                           kind: .local, path: localDocumentsPath)
        ]
        // carpetas del iPad concedidas por el usuario (iCloud, En mi iPad,
        // unidades externas…): iOS solo permite verlas con su permiso
        for folder in localStore?.folders ?? [] {
            if let url = localStore?.url(for: folder) {
                locals.append(FinderLocation(name: folder.name, icon: "folder.badge.person.crop",
                                             kind: .local, path: url.path))
            }
        }
        localLocations = locals
    }

    private var localDocumentsPath: String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
    }

    // MARK: - Navegación

    func open(_ loc: FinderLocation) async {
        location = loc
        columns = []
        await push(path: loc.path)
    }

    func reload() async {
        guard let last = columns.last else { return }
        let path = last.path
        columns.removeLast()
        await push(path: path)
    }

    func goUp() async {
        guard columns.count > 1 else { return }
        columns.removeLast()
        columns[columns.count - 1].selection = nil
    }

    func select(_ item: FinderItem, at level: Int) async {
        guard level < columns.count else { return }
        columns[level].selection = item.path
        // cerrar columnas a la derecha
        if columns.count > level + 1 {
            columns.removeSubrange((level + 1)...)
        }
        if item.dir {
            await push(path: item.path)
        }
    }

    private func push(path: String) async {
        guard let loc = location else { return }
        loading = true
        defer { loading = false }
        do {
            let items: [FinderItem]
            let resolved: String
            switch loc.kind {
            case .local:
                (resolved, items) = try localList(path)
            case let .remote(serverID, machine):
                guard let client = client(for: serverID) else {
                    throw NSError(domain: "finder", code: 0,
                                  userInfo: [NSLocalizedDescriptionKey: "servidor sin gestor o sin contraseña"])
                }
                let (p, entries) = try await client.fsList(machine: machine, path: path)
                resolved = p
                items = entries.map {
                    FinderItem(name: $0.name, dir: $0.dir,
                               size: $0.size ?? 0, mtime: $0.mtime ?? 0,
                               path: p == "/" ? "/\($0.name)" : "\(p)/\($0.name)")
                }
            }
            columns.append(FinderColumn(path: resolved, items: items, selection: nil))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func localList(_ path: String) throws -> (String, [FinderItem]) {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: path)
        let items: [FinderItem] = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { name in
                let full = (path as NSString).appendingPathComponent(name)
                let attrs = try? fm.attributesOfItem(atPath: full)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: full, isDirectory: &isDir)
                return FinderItem(name: name, dir: isDir.boolValue,
                                  size: (attrs?[.size] as? Int) ?? 0,
                                  mtime: (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                                  path: full)
            }
        return (path, items)
    }

    // MARK: - Operaciones

    func createFolder(named name: String) async {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, let column = columns.last, let loc = location else { return }
        let target = column.path == "/" ? "/\(clean)" : "\(column.path)/\(clean)"
        do {
            switch loc.kind {
            case .local:
                try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
            case let .remote(serverID, machine):
                guard let client = client(for: serverID) else { return }
                try await client.fsOp(machine: machine, op: "mkdir", path: target)
            }
            await reload()
        } catch { self.error = error.localizedDescription }
    }

    func delete(_ item: FinderItem) async {
        guard let loc = location else { return }
        do {
            switch loc.kind {
            case .local:
                try FileManager.default.removeItem(atPath: item.path)
            case let .remote(serverID, machine):
                guard let client = client(for: serverID) else { return }
                try await client.fsOp(machine: machine, op: "delete", path: item.path)
            }
            await reload()
        } catch { self.error = error.localizedDescription }
    }

    /// Guarda una copia en la carpeta local del iPad (visible en Archivos).
    func share(_ item: FinderItem) async {
        guard case let .remote(serverID, machine) = location?.kind,
              let client = client(for: serverID) else { return }
        do {
            let data = try await client.download(path: item.path, machine: machine)
            let dest = URL(fileURLWithPath: localDocumentsPath)
                .appendingPathComponent(item.name)
            try data.write(to: dest)
            error = "Guardado en Archivos › iFinder: \(item.name)"
        } catch { self.error = error.localizedDescription }
    }

    /// Recibe archivos soltados (desde otra columna, otra app o el iPad).
    func receive(_ transfers: [FinderTransfer], into path: String) async {
        guard case let .remote(serverID, machine) = location?.kind,
              let client = client(for: serverID) else { return }
        for transfer in transfers {
            do {
                let data: Data
                if transfer.serverID == serverID {
                    data = try await client.download(path: transfer.path, machine: transfer.machine)
                } else {
                    let url = try await FinderTransferLoader.file(for: transfer)
                    data = try Data(contentsOf: url)
                }
                _ = try await client.upload(data: data, filename: transfer.name,
                                            machine: machine, dest: path)
            } catch { self.error = error.localizedDescription }
        }
        await reload()
    }

    func transfer(for item: FinderItem) -> FinderTransfer {
        switch location?.kind {
        case let .remote(serverID, machine):
            return FinderTransfer(serverID: serverID, machine: machine,
                                  path: item.path, name: item.name)
        default:
            return FinderTransfer(serverID: UUID(), machine: "",
                                  path: item.path, name: item.name)
        }
    }

    private func client(for serverID: UUID) -> ManagerClient? {
        guard let server = store?.servers.first(where: { $0.id == serverID }),
              let mgr = server.managerURL,
              let pw = Keychain.password(for: server.id) else { return nil }
        return ManagerClient(baseURL: mgr, password: pw)
    }
}
