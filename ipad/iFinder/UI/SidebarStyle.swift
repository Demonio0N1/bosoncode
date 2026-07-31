import SwiftUI

/// Fila de barra lateral con la tipografía, el espaciado y —sobre todo— la
/// **selección en burbuja** del Finder de macOS.
///
/// iPadOS dimensiona sus listas para el dedo: 17 pt, filas de 44 pt, un
/// separador entre cada dos y un recuadro agrupando cada sección. El Finder no
/// tiene nada de eso: fondo continuo, sin una sola línea, y la fila activa
/// marcada con un rectángulo redondeado que **no toca los bordes**, de modo que
/// se lee como una pastilla flotando sobre la barra.
///
/// Esa separación es la clave del efecto: el resalte lo dibuja la propia fila
/// con su margen, no la lista de lado a lado. Por eso el fondo del sistema se
/// anula (`listRowBackground(.clear)`) en vez de intentar teñirlo.
struct SidebarRow: View {
    let title: String
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
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)                            // nunca en dos líneas
                .truncationMode(.middle)
                .foregroundStyle(textColor)
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

    /// El resalte redondeado. Nada cuando la fila ni está activa ni tiene el
    /// puntero encima: en el Finder la barra en reposo es completamente lisa.
    @ViewBuilder
    private var bubble: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if isSelected {
            // Gris neutro y no el color de acento: en el Finder la pastilla es
            // discreta y quien lleva el color es el icono. Teñir el fondo
            // entero convierte una fila en un botón y compite con el contenido.
            shape.fill(Color.primary.opacity(scheme == .dark ? 0.16 : 0.10))
        } else if isHovered {
            shape.fill(Color.primary.opacity(scheme == .dark ? 0.07 : 0.05))
        }
    }

    private var iconColor: Color {
        dimmed ? .secondary : tint
    }

    private var textColor: Color {
        dimmed ? .secondary : .primary
    }
}
