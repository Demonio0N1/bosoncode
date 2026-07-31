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

extension View {
    /// Aplica el aspecto de barra lateral de escritorio a una `List`.
    ///
    /// - Parameter width: ancho preferido. El rango es amplio a propósito: en
    ///   macOS la barra lateral se arrastra a gusto, y limitarla a 60 puntos de
    ///   margen —como estaba— hacía que el arrastre pareciera roto.
    ///
    /// Se usa `.plain` y no `.sidebar`: en iPadOS, `.sidebar` es una lista
    /// agrupada con recuadro por sección y separadores dentro, que es
    /// exactamente el aspecto "de formulario" que aquí sobra. `.plain` da un
    /// lienzo liso sobre el que las filas ponen su propio resalte.
    func macSidebarStyle(width: Double = 220) -> some View {
        self
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 28)     // 44 → 28 pt
            .scrollContentBackground(.hidden)
            .listRowSpacing(0)
    }

    /// Encabezado de sección como el del Finder: pequeño, gris, sin mayúsculas
    /// y sin fondo propio —en `.plain` los encabezados traen uno translúcido
    /// que se queda pegado arriba al desplazar—.
    func macSidebarSectionHeader() -> some View {
        self
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// Deja la fila lista para el estilo burbuja.
    ///
    /// Tres cosas, y las tres hacen falta: quitar el separador, anular el fondo
    /// que la lista dibuja de lado a lado —si no, el resalte del sistema
    /// aparecería DEBAJO de la burbuja, con sus esquinas rectas asomando— y
    /// dejar un margen lateral pequeño, que es el aire por el que la burbuja se
    /// ve flotar en vez de pegada a los bordes.
    func macSidebarRowInsets() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
