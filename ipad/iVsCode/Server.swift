import Foundation
import Security
import WebKit

struct Server: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var urlString: String
    /// Sistema operativo anunciado por serve.sh en el TXT del mDNS (`os=`).
    ///
    /// Opcional por dos motivos: los servidores guardados antes de este campo
    /// no lo traen —y un campo obligatorio haría fallar la decodificación de
    /// la lista entera—, y un equipo añadido a mano tampoco lo anuncia.
    var os: String?

    var url: URL? { URL(string: urlString) }
}

/// Dónde viven los datos que BosonCode y ZeroSpin comparten.
///
/// Son dos apps distintas y cada una tiene su propio contenedor: sin un App
/// Group, ZeroSpin no ve ni un solo equipo de los que has guardado en
/// BosonCode — de ahí el "No hay ningún equipo conectado" aunque estuvieras
/// conectado. El grupo les da un UserDefaults y un Llavero comunes.
enum SharedStorage {
    static let appGroup = "group.com.garyguaman.boson"
    static let keychainGroup = "QJ2824WK6Q.com.garyguaman.boson"

    /// Preferencias compartidas, con la de la app como respaldo por si el
    /// grupo no estuviera disponible (perfil sin la capacidad).
    static let defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    static var isShared: Bool { defaults !== UserDefaults.standard }
}

/// Qué equipo mira ESTA ventana.
///
/// Vivía dentro de `ServerStore`, que es un singleton, y por eso abrir una
/// segunda ventana y cambiar de máquina cambiaba también la primera: las dos
/// leían el mismo `activeID`. La lista de equipos SÍ debe ser común —es tu
/// inventario, y guardarla dos veces sería peor— pero la selección es de cada
/// ventana. Como cada escena crea su propio `@StateObject`, quedan aisladas
/// sin más ceremonia.
@MainActor
final class WindowSession: ObservableObject {
    @Published var activeID: UUID?

    /// Arranca donde lo dejaste: la última selección se recuerda como valor
    /// inicial, no como estado compartido.
    init(initial: UUID? = ServerStore.shared.lastActiveID) {
        activeID = initial
    }

    /// El equipo de esta ventana, o nada si el que había ya no existe.
    ///
    /// Antes, no encontrarlo caía en `servers.first`. Eso hacía que borrar una
    /// máquina desde otra ventana convirtiera esta —en silencio, sin cambiar
    /// nada en pantalla— en una ventana de OTRO equipo. Devolver nil es más
    /// honesto: la ventana vuelve a la lista y eliges tú.
    ///
    /// Sin selección todavía (arranque sin nada guardado) sí vale el primero.
    var active: Server? {
        let store = ServerStore.shared
        guard let activeID else { return store.servers.first }
        return store.servers.first { $0.id == activeID }
    }

    /// Cambia de equipo en ESTA ventana y lo deja como preferencia para las
    /// que se abran después.
    func select(_ id: UUID?) {
        activeID = id
        ServerStore.shared.lastActiveID = id
    }
}

/// Lista de servidores persistida en UserDefaults; contraseñas en el Llavero.
final class ServerStore: ObservableObject {
    /// Instancia única: si cada ventana creara la suya, escribirían el mismo
    /// UserDefaults sin enterarse y se pisarían la lista de servidores.
    static let shared = ServerStore()

    @Published var servers: [Server] {
        didSet { persist() }
    }
    /// Última selección, solo para que una ventana nueva no arranque en blanco.
    /// NO es el estado activo de nadie: eso vive en `WindowSession`.
    @Published var lastActiveID: UUID? {
        didSet { SharedStorage.defaults.set(lastActiveID?.uuidString, forKey: "activeServerID") }
    }

    /// Contraseña que valida el **host**: la que esperan el gestor (puerto
    /// 9500) y el canal PTY del terminal.
    ///
    /// No siempre es la de la entrada activa. Un contenedor guarda la suya
    /// propia —la que se le grabó al crearlo— y esa puede ser distinta de la
    /// del host si el host la regeneró después. El terminal habla **siempre**
    /// con el host, así que aquí se busca primero la entrada del host que
    /// sirve esa máquina y solo se cae a la propia si no existe.
    func hostPassword(for server: Server) -> String? {
        if !server.isDockerMachine { return Keychain.password(for: server.id) }
        if let host = servers.first(where: { !$0.isDockerMachine && $0.sharesHost(with: server) }),
           let password = Keychain.password(for: host.id), !password.isEmpty {
            return password
        }
        return Keychain.password(for: server.id)
    }

    /// ¿Puede el terminal autenticarse sin preguntar nada? Falso cuando la
    /// entrada es un contenedor y no hay ninguna entrada del host guardada.
    func knowsHostPassword(for server: Server) -> Bool {
        guard server.isDockerMachine else { return Keychain.password(for: server.id) != nil }
        return servers.contains { !$0.isDockerMachine && $0.sharesHost(with: server)
                                  && Keychain.password(for: $0.id) != nil }
    }

    /// Guarda la contraseña del host que sirve esta máquina, creando la
    /// entrada del host si aún no estaba en la lista.
    func saveHostPassword(_ password: String, for server: Server) {
        if !server.isDockerMachine {
            Keychain.setPassword(password, for: server.id)
            return
        }
        if let host = servers.first(where: { !$0.isDockerMachine && $0.sharesHost(with: server) }) {
            Keychain.setPassword(password, for: host.id)
            return
        }
        guard let root = server.hostRootURLString else { return }
        let host = Server(name: URLComponents(string: root)?.host ?? "Host",
                          urlString: root, os: server.os)
        servers.append(host)
        Keychain.setPassword(password, for: host.id)
    }

    /// Equipos físicos: todo lo que no es un contenedor montado en una ruta.
    var hosts: [Server] { servers.filter { !$0.isDockerMachine } }

    /// Contenedores que viven dentro de ese equipo.
    func machines(of host: Server) -> [Server] {
        servers.filter { $0.isDockerMachine && $0.sharesHost(with: host) }
    }

    /// Contenedores cuyo equipo no está guardado: sin esto desaparecerían de
    /// la pantalla al agrupar por anfitrión.
    var orphanMachines: [Server] {
        servers.filter { machine in
            machine.isDockerMachine && !hosts.contains { $0.sharesHost(with: machine) }
        }
    }

    /// Alias local del equipo. Solo cambia cómo se ve en la app; el anuncio
    /// mDNS del equipo sigue diciendo lo suyo.
    func rename(_ server: Server, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = servers.firstIndex(where: { $0.id == server.id })
        else { return }
        servers[index].name = clean
    }

    /// Equipo por defecto para una ventana nueva.
    var active: Server? {
        servers.first { $0.id == lastActiveID } ?? servers.first
    }

    init() {
        let defaults = SharedStorage.defaults
        // Traslado desde la época en que cada app guardaba lo suyo: si el
        // almacén compartido está vacío pero el propio tiene datos, se copian
        // una vez. Sin esto, activar el grupo parecería borrar los equipos.
        if SharedStorage.isShared, defaults.data(forKey: "servers") == nil,
           let legacy = UserDefaults.standard.data(forKey: "servers") {
            defaults.set(legacy, forKey: "servers")
            if let active = UserDefaults.standard.string(forKey: "activeServerID") {
                defaults.set(active, forKey: "activeServerID")
            }
        }
        if let data = defaults.data(forKey: "servers"),
           let list = try? JSONDecoder().decode([Server].self, from: data) {
            servers = list
        } else if let legacy = defaults.string(forKey: "backendURL"), !legacy.isEmpty {
            // migración desde la versión de un solo servidor
            servers = [Server(name: "PC RTX 4090", urlString: legacy)]
        } else {
            servers = []
        }
        if let raw = defaults.string(forKey: "activeServerID"), let id = UUID(uuidString: raw) {
            lastActiveID = id
        } else {
            lastActiveID = servers.first?.id
        }
        migrateLegacyMachineURLs()
        persist()
    }

    /// Las máquinas Docker antiguas usaban un puerto propio (https://host:101xx),
    /// donde WebKit veta los Service Workers (notebooks rotos). El esquema actual
    /// es una ruta del origen principal. Se reconstruye la URL cuando es posible
    /// (nombre "maquina · PC" + URL del PC) y si no, se descarta la tarjeta.
    private func migrateLegacyMachineURLs() {
        let legacy = servers.filter {
            $0.urlString.range(of: #":101\d\d/?$"#, options: .regularExpression) != nil
        }
        guard !legacy.isEmpty else { return }
        for old in legacy {
            let parts = old.name.components(separatedBy: " · ")
            if parts.count == 2,
               let parent = servers.first(where: { $0.name == parts[1] }),
               let host = URLComponents(string: parent.urlString),
               host.scheme == "https" {
                var fixed = old
                let machine = parts[0]
                let port = host.port.map { ":\($0)" } ?? ""
                fixed.urlString = "https://\(host.host ?? "")\(port)/m-\(machine)/"
                if let idx = servers.firstIndex(where: { $0.id == old.id }) {
                    servers[idx] = fixed
                }
            } else {
                servers.removeAll { $0.id == old.id }
                Keychain.deletePassword(for: old.id)
            }
        }
        if let active = lastActiveID, !servers.contains(where: { $0.id == active }) {
            lastActiveID = servers.first?.id
        }
    }

    func upsert(_ server: Server, password: String) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        } else {
            servers.append(server)
        }
        if password.isEmpty {
            Keychain.deletePassword(for: server.id)
        } else {
            Keychain.setPassword(password, for: server.id)
        }
        if lastActiveID == nil { lastActiveID = server.id }
    }

    func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        Keychain.deletePassword(for: server.id)
        WKWebsiteDataStore.remove(forIdentifier: server.id) { _ in }
        if lastActiveID == server.id { lastActiveID = servers.first?.id }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            SharedStorage.defaults.set(data, forKey: "servers")
        }
    }
}

enum Keychain {
    private static let service = "com.garyguaman.ivscode.server"

    static func setPassword(_ password: String, for id: UUID) {
        deletePassword(for: id)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        // En el grupo compartido, para que ZeroSpin pueda leerla también.
        query[kSecAttrAccessGroup as String] = SharedStorage.keychainGroup
        if SecItemAdd(query as CFDictionary, nil) != errSecSuccess {
            // sin la capacidad de Llavero compartido, se guarda como siempre
            query.removeValue(forKey: kSecAttrAccessGroup as String)
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static func password(for id: UUID) -> String? {
        // Primero el grupo compartido; si no está, el propio de la app —ahí
        // viven las contraseñas guardadas antes de compartir— y en ese caso se
        // copian al compartido para que la otra app las vea a partir de ahora.
        if let shared = read(id: id, group: SharedStorage.keychainGroup) { return shared }
        if let legacy = read(id: id, group: nil) {
            setPassword(legacy, for: id)
            return legacy
        }
        return nil
    }

    private static func read(id: UUID, group: String?) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for id: UUID) {
        // sin grupo: borra la del contenedor propio y la compartida
        for group in [SharedStorage.keychainGroup, nil] {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id.uuidString,
            ]
            if let group { query[kSecAttrAccessGroup as String] = group }
            SecItemDelete(query as CFDictionary)
        }
    }
}
