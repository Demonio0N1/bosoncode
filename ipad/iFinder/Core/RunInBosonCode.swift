import UIKit

/// Manda un archivo al equipo y lo abre en BosonCode.
///
/// ZeroSpin no puede ejecutar nada: iOS no permite JIT ni correr binarios
/// descargados. Pero el equipo al que ya estás conectado sí tiene Python, Julia
/// y GPU, así que "ejecutar" aquí significa subir el archivo allí y abrirlo en
/// el editor, donde el kernel de Jupyter sí existe.
enum RunInBosonCode {

    enum Failure: LocalizedError {
        case noServer
        case unreachable(String)
        case cannotOpenApp

        var errorDescription: String? {
            switch self {
            case .noServer:
                return "No hay ningún equipo conectado. Abre BosonCode, conéctate a tu PC y vuelve a intentarlo."
            case .unreachable(let name):
                return "\(name) no está disponible ahora mismo. Comprueba que esté encendido y que su contraseña siga guardada en BosonCode."
            case .cannotOpenApp:
                return "No pude abrir BosonCode. ¿Está instalada?"
            }
        }
    }

    /// Equipos y contenedores donde se puede ejecutar algo.
    @MainActor
    static var destinations: [Server] {
        ServerStore.shared.servers.filter { $0.managerURL != nil }
    }

    /// Sube el archivo al destino elegido y abre BosonCode con él.
    /// - Returns: la ruta donde quedó, para poder decírselo al usuario.
    @MainActor
    @discardableResult
    static func run(_ url: URL, on target: Server? = nil) async throws -> String {
        let store = ServerStore.shared
        // Si se ELIGIÓ un equipo, es ese o ninguno.
        //
        // Antes el elegido era solo el primer candidato de una lista con
        // respaldos: si no tenía gestor o no había contraseña guardada, el
        // archivo acababa en otra máquina sin decirlo. Elegir destino y que el
        // archivo aparezca en otro sitio es peor que un error claro.
        let candidates = target.map { [$0] }
            ?? ([store.active].compactMap { $0 } + store.servers)
        guard let server = candidates.first(where: { $0.managerURL != nil }),
              let managerURL = server.managerURL,
              let password = store.hostPassword(for: server) else {
            throw target == nil ? Failure.noServer : Failure.unreachable(target!.name)
        }
        let client = ManagerClient(baseURL: managerURL, password: password)

        // El archivo puede estar en la nube sin descargar: se materializa antes
        // de subirlo, o se enviarían cero bytes.
        let data = try await CloudFileHandler.shared.read(url)
        // Carpeta propia dentro del equipo: dejarlo suelto en el home mezcla
        // lo que mandas desde el iPad con todo lo demás.
        let destination = try await client.upload(data: data,
                                                  filename: url.lastPathComponent,
                                                  machine: server.dockerMachineName,
                                                  dest: "@zerospin")
        let path = destination.hasSuffix("/")
            ? destination + url.lastPathComponent
            : destination + "/" + url.lastPathComponent

        var comps = URLComponents()
        comps.scheme = "bosoncode"
        comps.host = "open"
        comps.queryItems = [URLQueryItem(name: "server", value: server.id.uuidString),
                            URLQueryItem(name: "file", value: path)]
        guard let target = comps.url, UIApplication.shared.canOpenURL(target) else {
            throw Failure.cannotOpenApp
        }
        await UIApplication.shared.open(target)
        return path
    }
}
