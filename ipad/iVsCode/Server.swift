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

/// Lista de servidores persistida en UserDefaults; contraseñas en el Llavero.
final class ServerStore: ObservableObject {
    /// Instancia única: si cada ventana creara la suya, escribirían el mismo
    /// UserDefaults sin enterarse y se pisarían la lista de servidores.
    static let shared = ServerStore()

    @Published var servers: [Server] {
        didSet { persist() }
    }
    @Published var activeID: UUID? {
        didSet { UserDefaults.standard.set(activeID?.uuidString, forKey: "activeServerID") }
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

    var active: Server? {
        if let match = servers.first(where: { $0.id == activeID }) { return match }
        // activeID apuntaba a un servidor borrado: se corrige para que la UI
        // no muestre "conectado" a ninguna tarjeta mientras carga otra
        let fallback = servers.first
        if let fallback, activeID != fallback.id {
            DispatchQueue.main.async { [weak self] in self?.activeID = fallback.id }
        }
        return fallback
    }

    init() {
        let defaults = UserDefaults.standard
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
            activeID = id
        } else {
            activeID = servers.first?.id
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
        if let active = activeID, !servers.contains(where: { $0.id == active }) {
            activeID = servers.first?.id
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
        if activeID == nil { activeID = server.id }
    }

    func delete(_ server: Server) {
        servers.removeAll { $0.id == server.id }
        Keychain.deletePassword(for: server.id)
        WKWebsiteDataStore.remove(forIdentifier: server.id) { _ in }
        if activeID == server.id { activeID = servers.first?.id }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: "servers")
        }
    }
}

enum Keychain {
    private static let service = "com.garyguaman.ivscode.server"

    static func setPassword(_ password: String, for id: UUID) {
        deletePassword(for: id)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func password(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
