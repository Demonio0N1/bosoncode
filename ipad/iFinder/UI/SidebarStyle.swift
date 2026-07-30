import SwiftUI

/// Fila de barra lateral con la tipografía y el espaciado del Finder de macOS.
///
/// iPadOS dimensiona sus listas para el dedo: 17 pt y filas de 44 pt. El
/// Finder usa ~13 pt y filas de ~24 pt. Aquí se replican esas proporciones y,
/// sobre todo, se fija el ancho del icono para que **todos los textos queden
/// alineados** aunque los símbolos tengan anchos distintos.
struct SidebarRow: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(dimmed ? Color.secondary : tint)
                .frame(width: 18, alignment: .center)   // columna fija = textos alineados
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)                            // nunca en dos líneas
                .truncationMode(.middle)
                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

extension View {
    /// Aplica el aspecto compacto de escritorio a una `List` de barra lateral.
    ///
    /// - Parameter width: ancho preferido. El rango es amplio a propósito: en
    ///   macOS la barra lateral se arrastra a gusto, y limitarla a 60 puntos de
    ///   margen —como estaba— hacía que el arrastre pareciera roto.
    func macSidebarStyle(width: Double = 220) -> some View {
        self
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 26)      // 44 → 26 pt
            .scrollContentBackground(.hidden)
            .listSectionSpacing(.compact)
            .navigationSplitViewColumnWidth(min: 150, ideal: width, max: 420)
    }

    /// Encabezado de sección como el del Finder: pequeño, gris y sin mayúsculas.
    func macSidebarSectionHeader() -> some View {
        self
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    /// Márgenes de fila ajustados (los de iPadOS son muy generosos).
    func macSidebarRowInsets() -> some View {
        self.listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 8))
    }
}
