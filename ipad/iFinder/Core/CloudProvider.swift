import SwiftUI

/// Servicio del que procede una carpeta montada.
///
/// iPadOS **no** ofrece API pública para preguntar "¿de qué proveedor es esta
/// URL?": `NSFileProviderManager.domains` solo devuelve los dominios de la
/// propia app, no los de Google o Microsoft. Lo que sí es estable es la ruta:
/// el sistema coloca cada extensión de File Provider bajo un contenedor que
/// lleva el identificador de su app. Eso permite reconocer el servicio para
/// ponerle nombre e icono correctos.
///
/// Cuando la ruta no delata a nadie se cae en `.folder`, y el usuario siempre
/// puede renombrar el montaje a mano — imprescindible cuando hay dos cuentas
/// del mismo servicio ("OneDrive – Yachay Tech" y "OneDrive – EPN"), que se
/// distinguen por la cuenta, no por el proveedor.
enum CloudProvider: String, Codable, CaseIterable {
    case googleDrive, oneDrive, dropbox, box, mega, proton, iCloud, smb, folder

    /// Trozos de ruta que identifican a cada servicio.
    private static let signatures: [(CloudProvider, [String])] = [
        (.googleDrive, ["com.google.Drive", "GoogleDrive", "google.drive"]),
        (.oneDrive,    ["com.microsoft.skydrive", "OneDrive", "SharePoint"]),
        (.dropbox,     ["com.getdropbox", "Dropbox"]),
        (.box,         ["com.box.", "BoxNet"]),
        (.mega,        ["mega.ios", "MEGA"]),
        (.proton,      ["ch.protonmail", "ProtonDrive"]),
        (.iCloud,      ["com~apple~CloudDocs", "Mobile Documents"]),
        (.smb,         ["/Volumes/", "smb:"]),
    ]

    /// Deduce el servicio a partir de la ruta que devolvió el selector.
    static func detect(_ url: URL) -> CloudProvider {
        let path = url.path
        for (provider, marks) in signatures where marks.contains(where: { path.contains($0) }) {
            return provider
        }
        return .folder
    }

    var title: String {
        switch self {
        case .googleDrive: return "Google Drive"
        case .oneDrive: return "OneDrive"
        case .dropbox: return "Dropbox"
        case .box: return "Box"
        case .mega: return "MEGA"
        case .proton: return "Proton Drive"
        case .iCloud: return "iCloud Drive"
        case .smb: return "Servidor"
        case .folder: return "Carpeta"
        }
    }

    var icon: String {
        switch self {
        case .googleDrive, .dropbox, .box, .mega, .proton: return "externaldrive.badge.icloud"
        case .oneDrive: return "cloud.fill"
        case .iCloud: return "icloud.fill"
        case .smb: return "externaldrive.connected.to.line.below"
        case .folder: return "folder.fill"
        }
    }

    var tint: Color {
        switch self {
        case .googleDrive: return Color(red: 0.98, green: 0.74, blue: 0.02)
        case .oneDrive: return Color(red: 0.05, green: 0.47, blue: 0.79)
        case .dropbox: return Color(red: 0.0, green: 0.38, blue: 0.92)
        case .box: return Color(red: 0.0, green: 0.45, blue: 0.79)
        case .mega: return Color(red: 0.82, green: 0.06, blue: 0.13)
        case .proton: return Color(red: 0.42, green: 0.33, blue: 0.83)
        case .iCloud: return Color(red: 0.35, green: 0.62, blue: 0.95)
        case .smb: return .gray
        case .folder: return Color(red: 0.35, green: 0.62, blue: 0.95)
        }
    }

    /// Un montaje de nube va en su propia sección de la barra lateral.
    var isCloud: Bool {
        switch self {
        case .folder: return false
        default: return true
        }
    }

    /// Nombre inicial sugerido: servicio + carpeta, para que dos cuentas del
    /// mismo proveedor no queden con la misma etiqueta.
    func suggestedName(for url: URL) -> String {
        let folder = url.displayName
        guard isCloud, self != .folder else { return folder }
        return folder.localizedCaseInsensitiveContains(title) ? folder : "\(title) – \(folder)"
    }
}
