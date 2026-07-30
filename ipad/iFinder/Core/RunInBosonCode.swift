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
        case cannotOpenApp

        var errorDescription: String? {
            switch self {
            case .noServer:
                return "No hay ningún equipo conectado. Abre BosonCode, conéctate a tu PC y vuelve a intentarlo."
            case .cannotOpenApp:
                return "No pude abrir BosonCode. ¿Está instalada?"
            }
        }
    }

    /// Sube el archivo al equipo activo y abre BosonCode con él.
    /// - Returns: la ruta donde quedó en el equipo, para poder decírselo al usuario.
    @MainActor
    @discardableResult
    static func run(_ url: URL) async throws -> String {
        let store = ServerStore.shared
        let candidates = [store.active].compactMap { $0 } + store.servers
        guard let server = candidates.first(where: { $0.managerURL != nil }),
              let managerURL = server.managerURL,
              let password = store.hostPassword(for: server) else {
            throw Failure.noServer
        }
        let client = ManagerClient(baseURL: managerURL, password: password)

        // El archivo puede estar en la nube sin descargar: se materializa antes
        // de subirlo, o se enviarían cero bytes.
        let data = try await CloudFileHandler.shared.read(url)
        let destination = try await client.upload(data: data,
                                                  filename: url.lastPathComponent,
                                                  machine: server.dockerMachineName,
                                                  dest: "")
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
