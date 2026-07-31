import SwiftUI

/// Fila de la barra lateral con las proporciones del Finder de macOS.
///
/// iPadOS dimensiona sus listas para el dedo: 17 pt y filas de 44. El Finder
/// usa ~13 pt y filas compactas, que es lo que se quiere aquí: caben más
/// ubicaciones de un vistazo y la barra no le come sitio a los archivos. El
/// icono va en una columna de ancho fijo para que **todos los textos queden
/// alineados** aunque los símbolos midan distinto.
///
/// La fila activa se marca de dos maneras a la vez, como en el Finder: el fondo
/// redondeado —que no llega a los bordes, de ahí el efecto de pastilla
/// flotante— y el icono y el texto en el color de acento. El color es lo que se
/// capta de un vistazo; el fondo solo delimita.
struct SidebarRow: View {
    let title: String
    /// Segunda línea, más pequeña y gris: la cuenta de cada servicio, que es lo
    /// único que distingue dos OneDrive entre sí.
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
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 18, alignment: .center)   // columna fija = textos alineados
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)                        // nunca en dos líneas
                    .truncationMode(.middle)
                    .foregroundStyle(textColor)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(bubble)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    /// El resalte redondeado. En reposo no dibuja nada: la barra queda lisa.
    ///
    /// Sube a 9 acompañando al panel: dentro de un contenedor muy redondeado,
    /// una pastilla de esquinas cerradas se ve dura por contraste.
    private var bubble: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(bubbleFill)
    }

    private var bubbleFill: Color {
        if isSelected { return .primary.opacity(scheme == .dark ? 0.14 : 0.09) }
        if isHovered { return .primary.opacity(scheme == .dark ? 0.07 : 0.05) }
        return .clear
    }

    /// Icono y texto comparten el color de acento cuando la fila está activa.
    private var iconColor: Color {
        if dimmed { return .secondary }
        return isSelected ? .accentColor : tint
    }

    private var textColor: Color {
        if dimmed { return .secondary }
        return isSelected ? .accentColor : .primary
    }
}

/// Encabezado de sección: pequeño, gris y sin mayúsculas, como en el Finder.
///
/// El chevron solo aparece con el puntero encima o con la sección ya plegada.
/// En reposo el encabezado es una etiqueta discreta y nada más — un chevron
/// permanente en cada sección llena la barra de adornos que no informan.
struct SidebarSectionHeader: View {
    let title: String
    let collapsed: Bool
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .opacity(isHovered || collapsed ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}
