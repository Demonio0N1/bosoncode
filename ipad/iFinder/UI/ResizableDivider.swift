import SwiftUI

/// Separador que se arrastra, como los del Finder.
///
/// iPadOS no trae divisores ajustables: `NavigationSplitView` solo acepta un
/// rango de anchos y decide él. Esto es un asa propia — fina a la vista, ancha
/// al tacto — que ajusta la anchura mientras arrastras y recuerda el resultado.
struct ResizableDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// El panel crece hacia la izquierda (inspector) o hacia la derecha.
    var growsLeading = false
    /// Doble toque: vuelve a este ancho.
    var resetTo: Double

    @State private var startWidth: Double?
    @State private var active = false

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(active ? 0.22 : 0.10))
            .frame(width: 1)
            // El asa táctil es mucho más ancha que la línea: un divisor de un
            // punto es imposible de agarrar con el dedo, y con el puntero pide
            // una puntería incómoda.
            .frame(width: 12)
            .contentShape(Rectangle())
            .hoverEffect(.highlight)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if startWidth == nil {
                            startWidth = width
                            active = true
                        }
                        let delta = growsLeading ? -value.translation.width : value.translation.width
                        width = min(max((startWidth ?? width) + delta, range.lowerBound),
                                    range.upperBound)
                    }
                    .onEnded { _ in
                        startWidth = nil
                        active = false
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeOut(duration: 0.18)) { width = resetTo }
            }
            .accessibilityLabel("Ajustar anchura")
    }
}
