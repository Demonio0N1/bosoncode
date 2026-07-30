import SwiftUI
import SwiftTerm

/// Aspecto del terminal: tema de color y tipografía.
///
/// Se guarda en `UserDefaults` y lo consulta `MacTerminalTheme`, así que un
/// cambio alcanza a la vez a la consola, a la barra de título y a cualquier
/// ventana abierta — no hay una copia del color por cada sitio que lo pinta.
enum TerminalTheme: String, CaseIterable, Identifiable {
    case system, macDark, macLight, solarized, dracula, nord, gruvbox

    static let storageKey = "terminalTheme"

    /// El elegido ahora mismo.
    static var current: TerminalTheme {
        TerminalTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Automático"
        case .macDark: return "macOS oscuro"
        case .macLight: return "macOS claro"
        case .solarized: return "Solarized Dark"
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .gruvbox: return "Gruvbox Dark"
        }
    }

    var hint: String? {
        self == .system ? "Sigue el modo claro u oscuro del iPad" : nil
    }

    /// Colores del tema. `.system` es el único que mira el modo del iPad.
    func palette(for scheme: ColorScheme) -> MacTerminalTheme.Palette {
        switch self {
        case .system:
            return scheme == .dark ? Self.macDark.palette(for: .dark)
                                   : Self.macLight.palette(for: .light)
        case .macDark:
            return .init(background: hex(0x161616), foreground: hex(0xE5E5E5),
                         cursor: hex(0xE5E5E5), selection: hex(0x3D598C),
                         ansi: MacTerminalTheme.ansi)
        case .macLight:
            return .init(background: hex(0xFFFFFF), foreground: hex(0x000000),
                         cursor: hex(0x000000), selection: hex(0xB3CCFA),
                         ansi: MacTerminalTheme.lightAnsi)
        case .solarized:
            return .init(background: hex(0x002B36), foreground: hex(0x93A1A1),
                         cursor: hex(0x93A1A1), selection: hex(0x073642),
                         ansi: Self.ansi([0x073642, 0xDC322F, 0x859900, 0xB58900,
                                          0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
                                          0x002B36, 0xCB4B16, 0x586E75, 0x657B83,
                                          0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3]))
        case .dracula:
            return .init(background: hex(0x282A36), foreground: hex(0xF8F8F2),
                         cursor: hex(0xF8F8F2), selection: hex(0x44475A),
                         ansi: Self.ansi([0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C,
                                          0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
                                          0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5,
                                          0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF]))
        case .nord:
            return .init(background: hex(0x2E3440), foreground: hex(0xD8DEE9),
                         cursor: hex(0xD8DEE9), selection: hex(0x434C5E),
                         ansi: Self.ansi([0x3B4252, 0xBF616A, 0xA3BE8C, 0xEBCB8B,
                                          0x81A1C1, 0xB48EAD, 0x88C0D0, 0xE5E9F0,
                                          0x4C566A, 0xBF616A, 0xA3BE8C, 0xEBCB8B,
                                          0x81A1C1, 0xB48EAD, 0x8FBCBB, 0xECEFF4]))
        case .gruvbox:
            return .init(background: hex(0x282828), foreground: hex(0xEBDBB2),
                         cursor: hex(0xEBDBB2), selection: hex(0x504945),
                         ansi: Self.ansi([0x282828, 0xCC241D, 0x98971A, 0xD79921,
                                          0x458588, 0xB16286, 0x689D6A, 0xA89984,
                                          0x928374, 0xFB4934, 0xB8BB26, 0xFABD2F,
                                          0x83A598, 0xD3869B, 0x8EC07C, 0xEBDBB2]))
        }
    }

    /// ¿El tema es oscuro? Lo usa la barra de título para elegir el color del
    /// texto sin volver a mirar el modo del sistema.
    func isDark(for scheme: ColorScheme) -> Bool {
        switch self {
        case .system: return scheme == .dark
        case .macLight: return false
        default: return true
        }
    }

    private func hex(_ value: Int) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private static func ansi(_ values: [Int]) -> [SwiftTerm.Color] {
        values.map {
            SwiftTerm.Color(red: UInt16(((($0 >> 16) & 0xFF)) * 257),
                            green: UInt16(((($0 >> 8) & 0xFF)) * 257),
                            blue: UInt16((($0 & 0xFF)) * 257))
        }
    }
}

/// Tipografía monoespaciada del terminal.
enum TerminalTypeface: String, CaseIterable, Identifiable {
    case meslo, menlo, courier, system

    static let storageKey = "terminalTypeface"

    static var current: TerminalTypeface {
        TerminalTypeface(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .meslo
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meslo: return "MesloLGS NF"
        case .menlo: return "Menlo"
        case .courier: return "Courier New"
        case .system: return "Del sistema"
        }
    }

    var hint: String? {
        self == .meslo ? "Incluye los glifos de Powerlevel10k" : nil
    }

    func font(size: CGFloat) -> UIFont {
        switch self {
        case .meslo:
            return UIFont(name: "MesloLGSNF-Regular", size: size)
                ?? UIFont(name: "MesloLGS NF", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        case .menlo:
            return UIFont(name: "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        case .courier:
            return UIFont(name: "CourierNewPSMT", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        case .system:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}

extension MacTerminalTheme.Palette {
    /// Un color ANSI como `UIColor`, para pintarlo fuera de SwiftTerm.
    ///
    /// SwiftTerm los guarda en componentes de 16 bits y su tipo se llama
    /// `Color`, igual que el de SwiftUI: convertir aquí evita que las vistas
    /// tengan que importar SwiftTerm y lidiar con la ambigüedad.
    func ansiColor(_ index: Int) -> UIColor {
        guard ansi.indices.contains(index) else { return foreground }
        let c = ansi[index]
        return UIColor(red: CGFloat(c.red) / 65535, green: CGFloat(c.green) / 65535,
                       blue: CGFloat(c.blue) / 65535, alpha: 1)
    }
}
