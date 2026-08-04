import SwiftUI
import UniformTypeIdentifiers

/// Fondo de la carpeta: capta el clic derecho en el **espacio vacío**.
///
/// El problema que resuelve: si el `.contextMenu` se pone en el `ScrollView` o
/// en el `LazyVGrid`, al pulsar entre dos iconos no aparece nada. La razón es
/// que SwiftUI busca la vista más superficial que contenga el punto, y en un
/// hueco de la rejilla esa vista es el propio contenedor, que no dibuja nada y
/// por tanto no es "tocable".
///
/// La solución son dos piezas juntas:
///   1. una capa `Color.clear` con `.contentShape(Rectangle())`, que le da al
///      hueco una forma sí tocable aunque no se vea;
///   2. colocarla **dentro** del ScrollView y con la altura del visor, para
///      que cubra también la zona que sobra cuando hay pocos archivos.
struct FolderBackground: View {
    @ObservedObject var model: BrowserViewModel
    /// Observado para que el menú refleje si hay fondo puesto ahora mismo
    @ObservedObject private var wallpaper = Wallpaper.shared
    /// Altura del área visible, para llenar la carpeta aunque esté casi vacía.
    let minHeight: CGFloat

    /// Algo se está arrastrando por encima ahora mismo.
    @State private var targeted = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())          // sin esto el hueco no recibe el toque
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
            .folderContextMenu(model)
            // La alerta de "archivo nuevo" se reparte aquí por lo mismo que la
            // de renombrar: una por vista. Y este es su sitio natural, porque
            // es el fondo de la carpeta quien ofrece crearlo.
            .newFileAlert(model)
            // Soltar en la CARPETA ABIERTA, no sobre un icono.
            //
            // Antes solo se aceptaba encima de una carpeta concreta, así que
            // traer algo de Fotos o de Archivos a la carpeta que estabas
            // mirando no tenía dónde soltarse: el hueco no era destino de nada.
            // Es el gesto natural y el que faltaba.
            // `.onDrop` con proveedores y no `dropDestination(for: URL.self)`:
            // ese solo ve lo que el origen entregue como URL, y Fotos entrega
            // los DATOS de la imagen. Ver `IncomingDrop`.
            .onDrop(of: [.item], isTargeted: $targeted) { providers in
                guard let destination = model.currentURL else { return false }
                Task {
                    let staged = await IncomingDrop.stage(providers)
                    guard !staged.isEmpty else { return }
                    await model.receive(staged, into: destination, move: false)
                }
                return true
            }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor,
                                      style: StrokeStyle(lineWidth: 3, dash: [10]))
                        .background(Color.accentColor.opacity(0.06))
                        .padding(6)
                        // el aviso no debe robarle la suelta a quien la espera
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Menú de la carpeta (no de un archivo concreto).
    func folderContextMenu(_ model: BrowserViewModel) -> some View {
        contextMenu {
            Button { model.beginNewFile() } label: {
                Label("Nuevo archivo…", systemImage: "doc.badge.plus")
            }
            Button { Task { await model.newFolder() } } label: {
                Label("Nueva carpeta", systemImage: "folder.badge.plus")
            }
            Divider()
            Button { Task { await model.paste() } } label: {
                Label("Pegar", systemImage: "doc.on.clipboard")
            }
            .disabled(!model.canPaste)
            Divider()
            Button { model.showHidden.toggle(); Task { await model.reload() } } label: {
                Label(model.showHidden ? "Ocultar archivos ocultos" : "Mostrar archivos ocultos",
                      systemImage: "eye")
            }
            Button { Task { await model.reload() } } label: {
                Label("Actualizar", systemImage: "arrow.clockwise")
            }
            // El fondo se pone desde una imagen, así que quitarlo tiene que
            // vivir en otro sitio: aquí, en el menú de la ventana, que es a
            // quien pertenece el ajuste. Solo aparece si hay fondo puesto.
            if Wallpaper.shared.image != nil {
                Divider()
                Menu {
                    ForEach([0.15, 0.35, 0.6, 1.0], id: \.self) { level in
                        Button {
                            Wallpaper.shared.opacity = level
                        } label: {
                            if Wallpaper.shared.opacity == level {
                                Label("\(Int(level * 100)) %", systemImage: "checkmark")
                            } else {
                                Text("\(Int(level * 100)) %")
                            }
                        }
                    }
                } label: {
                    Label("Intensidad del fondo", systemImage: "slider.horizontal.below.rectangle")
                }
                Button(role: .destructive) {
                    Wallpaper.shared.clear()
                } label: {
                    Label("Quitar fondo de ZeroSpin", systemImage: "photo.badge.exclamationmark")
                }
            }
        }
    }

    /// Alerta de creación: un campo de texto y dos botones, como pide macOS.
    ///
    /// Va en la ventana, no en cada fila: una alerta por escena basta y así el
    /// foco del teclado llega solo al campo.
    func newFileAlert(_ model: BrowserViewModel) -> some View {
        alert("Nuevo archivo", isPresented: Binding(
            get: { model.creatingFile },
            set: { model.creatingFile = $0 }
        )) {
            TextField("Nombre del archivo con extensión",
                      text: Binding(get: { model.newFileName },
                                    set: { model.newFileName = $0 }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Crear") { Task { await model.createFile() } }
                .disabled(model.newFileName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancelar", role: .cancel) { model.creatingFile = false }
        } message: {
            Text("Se creará vacío en \(model.currentURL?.lastPathComponent ?? "esta carpeta").\nEjemplos: main.py, script.jl, data.json")
        }
    }
}
