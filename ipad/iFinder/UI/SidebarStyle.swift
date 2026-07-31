import SwiftUI

/// Fila de la barra lateral, con las proporciones de la app Archivos del iPad.
///
/// Antes esto imitaba al Finder de escritorio: 13 pt y filas de 26. En un iPad
/// eso se lee apretado y, sobre todo, no se parece a lo que el usuario tiene al
/// lado para comparar. Archivos usa el tamaño de texto normal del sistema,
/// iconos grandes y filas holgadas, y esas son las proporciones de aquí.
///
/// La fila activa se marca de dos maneras a la vez, como en Archivos: el fondo
/// redondeado —que no toca los bordes, de ahí el efecto de pastilla flotante— y
/// el texto en el color de acento. El color es lo que de verdad se ve de un
/// vistazo; el fondo solo delimita.
struct SidebarRow: View {
    let title: String
    /// Segunda línea, más pequeña y gris. Archivos la usa para la cuenta de
    /// cada servicio, que es lo único que distingue dos OneDrive.
    var subtitle: String? = nil
    let systemImage: String
    var tint: Color = .accentColor
    var dimmed: Bool = false
    /// Fila correspondiente a la ubicación abierta ahora mismo.
    var isSelected: Bool = false

    /// Puntero del Magic Keyboard encima. Con el dedo nunca se activa, así que
    /// no estorba en uso táctil.
    @State private var isHovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 19))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor)
                .frame(width: 28, alignment: .center)   // columna fija = textos alineados
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)                        // nunca en dos líneas
                    .truncationMode(.middle)
                    .foregroundStyle(textColor)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(bubble)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    /// El resalte redondeado. En reposo no dibuja nada: la barra queda lisa.
    private var bubble: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(bubbleFill)
    }

    private var bubbleFill: Color {
        if isSelected { return .primary.opacity(scheme == .dark ? 0.14 : 0.09) }
        if isHovered { return .primary.opacity(scheme == .dark ? 0.07 : 0.05) }
        return .clear
    }

    private var iconColor: Color {
        dimmed ? .secondary : tint
    }

    /// El texto de la fila activa toma el color de acento, como en Archivos.
    /// Es la señal que se capta sin mirar: el fondo gris solo la enmarca.
    private var textColor: Color {
        if dimmed { return .secondary }
        return isSelected ? .accentColor : .primary
    }
}
