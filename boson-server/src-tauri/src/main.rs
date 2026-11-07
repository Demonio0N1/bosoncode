// Sin consola en Windows; en Mac y Linux no cambia nada.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // `boson-server --servir`: la app como lanzador del servicio (launchd la
    // arranca así). No abre ventana: ejecuta ~/.ivscode/serve.sh y nada más.
    if std::env::args().any(|a| a == "--servir") {
        boson_server_lib::servir();
    }
    boson_server_lib::run()
}
