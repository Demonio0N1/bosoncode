//! Boson Server: la ventana del servidor de BosonCode.
//!
//! La app no sabe nada del servidor por su cuenta: todo lo que enseña sale de
//! `setup.sh --estado` (JSON), lo que copia al portapapeles de `setup.sh
//! --clave`, y lo que hace —instalar, reiniciar, cambiar la contraseña— lo
//! hace `setup.sh` con sus propias opciones, cuya salida se enseña en vivo.
//! Así hay una sola verdad: los scripts, los mismos que usa quien instala
//! desde la terminal. La app es la cara, no otra copia.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;

use serde::Serialize;
use tauri::{
    image::Image,
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
    AppHandle, Emitter, Manager, RunEvent, WindowEvent,
};

/// Carpeta con setup.sh y serve.sh. Por orden: `BOSON_REPO` si está puesto
/// (para probar la app contra otra copia), los recursos del paquete
/// (`scripts/`, que es lo que lleva la app instalada) y, solo al ejecutar
/// desde el código con `cargo run`, la raíz del repositorio.
///
/// Los recursos van antes que el repositorio a propósito: el repositorio suele
/// estar en el Escritorio o en Documentos, y macOS pide permiso para que una
/// app entre ahí. Una app que al abrirse pide acceso al Escritorio para leer
/// sus propios scripts asusta sin motivo.
fn carpeta_scripts(app: &AppHandle) -> Result<PathBuf, String> {
    if let Ok(p) = std::env::var("BOSON_REPO") {
        let p = PathBuf::from(p);
        if p.join("setup.sh").exists() {
            return Ok(p);
        }
        return Err(format!("BOSON_REPO apunta a {}, pero ahí no hay setup.sh", p.display()));
    }
    if let Ok(recursos) = app.path().resource_dir() {
        let recursos = recursos.join("scripts");
        if recursos.join("setup.sh").exists() {
            return Ok(recursos);
        }
    }
    if cfg!(debug_assertions) {
        let p = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
        if p.join("setup.sh").exists() {
            return p.canonicalize().map_err(|e| e.to_string());
        }
    }
    Err("no encuentro setup.sh: ni dentro de la app ni en el repositorio".into())
}

/// Una app abierta desde el Finder o desde GNOME arranca con un PATH mínimo en
/// el que no están Homebrew ni /usr/local/bin, que es donde viven tailscale,
/// docker y python3 en muchos equipos. Los scripts los necesitan.
fn ruta_para_scripts() -> String {
    let base = std::env::var("PATH").unwrap_or_default();
    format!("/opt/homebrew/bin:/usr/local/bin:{base}:/usr/bin:/bin:/usr/sbin:/sbin")
}

/// El ayudante gráfico de sudo, copiado a ~/.ivscode con permiso de ejecución:
/// sudo lo ejecuta él mismo, y dentro de la app instalada no se puede tocar.
fn askpass(app: &AppHandle) -> Option<PathBuf> {
    let origen = app.path().resource_dir().ok()?.join("askpass.sh");
    let origen = if origen.exists() {
        origen
    } else {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../askpass.sh")
    };
    let destino = app.path().home_dir().ok()?.join(".ivscode").join("askpass.sh");
    std::fs::create_dir_all(destino.parent()?).ok()?;
    std::fs::copy(&origen, &destino).ok()?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&destino, std::fs::Permissions::from_mode(0o755)).ok()?;
    }
    Some(destino)
}

/// El entorno que ven los scripts: PATH completo, el modo app (marcas en la
/// salida, sin preguntas por teclado), la propia app como lanzador del
/// servicio en el Mac, y el ayudante de sudo.
fn entorno(app: &AppHandle) -> Vec<(String, String)> {
    let mut env = vec![
        ("PATH".to_string(), ruta_para_scripts()),
        ("BOSON_APP".to_string(), "1".to_string()),
    ];
    if let Ok(exe) = std::env::current_exe() {
        env.push(("BOSON_SERVER_APP".to_string(), exe.to_string_lossy().into_owned()));
    }
    if let Some(a) = askpass(app) {
        env.push(("SUDO_ASKPASS".to_string(), a.to_string_lossy().into_owned()));
    }
    env
}

fn ejecutar(app: &AppHandle, args: &[&str]) -> Result<String, String> {
    let dir = carpeta_scripts(app)?;
    let salida = Command::new("bash")
        .arg(dir.join("setup.sh"))
        .args(args)
        .current_dir(&dir)
        .envs(entorno(app))
        .output()
        .map_err(|e| format!("no pude ejecutar setup.sh: {e}"))?;
    if !salida.status.success() {
        let err = String::from_utf8_lossy(&salida.stderr).trim().to_string();
        return Err(if err.is_empty() {
            format!("setup.sh terminó con {}", salida.status)
        } else {
            err
        });
    }
    Ok(String::from_utf8_lossy(&salida.stdout).to_string())
}

/// El estado del equipo, tal cual lo cuenta `setup.sh --estado`.
///
/// `async` no es adorno: un comando síncrono se ejecuta en el hilo principal
/// y la ventana se queda helada el segundo que tarda el script. En async va
/// a otro hilo y la interfaz sigue respondiendo.
#[tauri::command]
async fn estado(app: AppHandle) -> Result<serde_json::Value, String> {
    let texto = ejecutar(&app, &["--estado"])?;
    serde_json::from_str(&texto).map_err(|e| format!("el estado no es JSON: {e}"))
}

/// Una clave, solo cuando alguien la pide desde la ventana: la contraseña del
/// editor o el enlace del panel de CSM con su token. No se guarda ni se registra.
#[tauri::command]
async fn clave(app: AppHandle, cual: String) -> Result<String, String> {
    if cual != "editor" && cual != "csm" {
        return Err("clave desconocida".into());
    }
    Ok(ejecutar(&app, &["--clave", &cual])?.trim_end().to_string())
}

/// Abre una dirección o una ruta con lo que el sistema tenga para ello. Solo
/// lo que la ventana puede necesitar: páginas web, el panel de Privacidad de
/// macOS y archivos o carpetas del propio equipo.
#[tauri::command]
async fn abrir(destino: String) -> Result<(), String> {
    let permitido = destino.starts_with("https://")
        || destino.starts_with("http://")
        || destino.starts_with("x-apple.systempreferences:")
        || destino.starts_with('/');
    if !permitido {
        return Err(format!("no abro {destino}"));
    }
    let programa = if cfg!(target_os = "macos") { "open" } else { "xdg-open" };
    Command::new(programa)
        .arg(&destino)
        .env("PATH", ruta_para_scripts())
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("no pude abrir {destino}: {e}"))
}

/// Acceso total al disco de ESTA app (y del servidor, que la app lanza con la
/// misma firma): macOS solo deja leer la base de datos de permisos a quien lo
/// tiene. En Linux no existe la pregunta.
#[tauri::command]
async fn acceso_total_disco(app: AppHandle) -> Option<bool> {
    if !cfg!(target_os = "macos") {
        return None;
    }
    let home = app.path().home_dir().ok()?;
    let tcc = home.join("Library/Application Support/com.apple.TCC/TCC.db");
    Some(std::fs::File::open(tcc).is_ok())
}

// ---------- acciones con salida en vivo ----------

/// Una línea de la acción en marcha, o su final. Viaja a la ventana como el
/// evento «accion».
#[derive(Clone, Serialize)]
struct Linea {
    id: u64,
    tipo: &'static str,
    texto: String,
    codigo: Option<i32>,
}

#[derive(Default)]
struct Tarea {
    en_curso: Mutex<Option<(u64, Arc<Mutex<Child>>)>>,
    contador: Mutex<u64>,
}

fn leer<R: Read + Send + 'static>(flujo: R, app: AppHandle, id: u64) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        let mut lector = BufReader::new(flujo);
        let mut buf = Vec::new();
        loop {
            buf.clear();
            match lector.read_until(b'\n', &mut buf) {
                Ok(0) | Err(_) => break,
                Ok(_) => {}
            }
            // Las barras de progreso de curl van con \r: cuentan como líneas.
            let texto = String::from_utf8_lossy(&buf);
            for parte in texto.split('\r') {
                let parte = parte.trim_end_matches('\n');
                if !parte.trim().is_empty() {
                    let _ = app.emit("accion", Linea { id, tipo: "linea", texto: parte.to_string(), codigo: None });
                }
            }
        }
    })
}

/// Arranca `setup.sh` con esos argumentos y manda su salida línea a línea.
/// `extra` son variables de entorno de la acción (CSM_JOIN_HUB, …); `entrada`
/// es lo que va por la entrada estándar (la contraseña nueva, que nunca va
/// como argumento). Solo una acción a la vez.
#[tauri::command]
async fn accion_iniciar(
    app: AppHandle,
    args: Vec<String>,
    extra: HashMap<String, String>,
    entrada: Option<String>,
) -> Result<u64, String> {
    let tarea = app.state::<Tarea>();
    {
        let en_curso = tarea.en_curso.lock().map_err(|e| e.to_string())?;
        if en_curso.is_some() {
            return Err("ya hay una acción en marcha".into());
        }
    }
    let dir = carpeta_scripts(&app)?;
    let mut cmd = Command::new("bash");
    cmd.arg(dir.join("setup.sh"))
        .args(&args)
        .current_dir(&dir)
        .envs(entorno(&app))
        .envs(extra)
        .stdin(if entrada.is_some() { Stdio::piped() } else { Stdio::null() })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut hijo = cmd.spawn().map_err(|e| format!("no pude ejecutar setup.sh: {e}"))?;
    if let Some(texto) = entrada {
        if let Some(mut stdin) = hijo.stdin.take() {
            let _ = stdin.write_all(texto.as_bytes());
            let _ = stdin.write_all(b"\n");
        }
    }
    let id = {
        let mut c = tarea.contador.lock().map_err(|e| e.to_string())?;
        *c += 1;
        *c
    };
    let stdout = hijo.stdout.take();
    let stderr = hijo.stderr.take();
    let hijo = Arc::new(Mutex::new(hijo));
    *tarea.en_curso.lock().map_err(|e| e.to_string())? = Some((id, hijo.clone()));

    let h1 = stdout.map(|f| leer(f, app.clone(), id));
    let h2 = stderr.map(|f| leer(f, app.clone(), id));
    let app2 = app.clone();
    thread::spawn(move || {
        if let Some(h) = h1 {
            let _ = h.join();
        }
        if let Some(h) = h2 {
            let _ = h.join();
        }
        let codigo = hijo.lock().ok().and_then(|mut h| h.wait().ok()).and_then(|s| s.code());
        if let Ok(mut en_curso) = app2.state::<Tarea>().en_curso.lock() {
            *en_curso = None;
        }
        let _ = app2.emit("accion", Linea { id, tipo: "fin", texto: String::new(), codigo });
    });
    Ok(id)
}

#[tauri::command]
async fn accion_cancelar(app: AppHandle) -> Result<(), String> {
    let tarea = app.state::<Tarea>();
    let en_curso = tarea.en_curso.lock().map_err(|e| e.to_string())?;
    if let Some((_, hijo)) = en_curso.as_ref() {
        if let Ok(mut h) = hijo.try_lock() {
            let _ = h.kill();
        }
    }
    Ok(())
}

// ---------- actualizaciones ----------

#[derive(Serialize)]
struct Actualizacion {
    version: String,
    url: String,
}

fn version_tupla(v: &str) -> Option<(u64, u64, u64)> {
    let v = v.trim().trim_start_matches('v');
    let mut partes = v.split('.').map(|p| p.parse::<u64>().ok());
    Some((partes.next()??, partes.next()??, partes.next()??))
}

/// Mira si hay una versión de Boson Server más nueva publicada en GitHub. Solo
/// avisa: la descarga la abre el navegador. Sin red, no hay aviso ni error.
#[tauri::command]
async fn actualizacion() -> Result<Option<Actualizacion>, String> {
    let salida = Command::new("curl")
        .args(["-fsSL", "-m", "8", "https://api.github.com/repos/Demonio0N1/bosoncode/releases/latest"])
        .env("PATH", ruta_para_scripts())
        .output()
        .map_err(|e| e.to_string())?;
    if !salida.status.success() {
        return Ok(None);
    }
    let json: serde_json::Value = serde_json::from_slice(&salida.stdout).map_err(|e| e.to_string())?;
    let etiqueta = json["tag_name"].as_str().unwrap_or_default();
    let url = json["html_url"].as_str().unwrap_or_default().to_string();
    let (Some(nueva), Some(actual)) = (version_tupla(etiqueta), version_tupla(env!("CARGO_PKG_VERSION"))) else {
        return Ok(None);
    };
    if nueva > actual {
        Ok(Some(Actualizacion { version: etiqueta.trim_start_matches('v').to_string(), url }))
    } else {
        Ok(None)
    }
}

// ---------- barra de menús ----------

/// La línea de estado del menú de la barra: la ventana la actualiza cada vez
/// que vuelve a leer el estado.
struct Bandeja(Mutex<Option<MenuItem<tauri::Wry>>>);

#[tauri::command]
fn bandeja(app: AppHandle, texto: String) -> Result<(), String> {
    if let Some(item) = app.state::<Bandeja>().0.lock().map_err(|e| e.to_string())?.as_ref() {
        item.set_text(texto).map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn mostrar_ventana(app: &AppHandle) {
    if let Some(v) = app.get_webview_window("main") {
        let _ = v.show();
        let _ = v.unminimize();
        let _ = v.set_focus();
    }
}

/// `boson-server --servir`: ejecuta ~/.ivscode/serve.sh en el lugar de este
/// proceso. Es lo que launchd arranca; así el permiso de disco que se concede
/// a la app vale para el servidor, que es quien lee los archivos.
pub fn servir() -> ! {
    let home = std::env::var("HOME").unwrap_or_default();
    let script = PathBuf::from(home).join(".ivscode").join("serve.sh");
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        let error = Command::new("/bin/bash").arg(&script).exec();
        eprintln!("Boson Server: no pude ejecutar {}: {error}", script.display());
    }
    std::process::exit(1)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let oculto = std::env::args().any(|a| a == "--oculto");
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--oculto"]),
        ))
        .manage(Bandeja(Mutex::new(None)))
        .manage(Tarea::default())
        .invoke_handler(tauri::generate_handler![
            estado, clave, abrir, acceso_total_disco, accion_iniciar, accion_cancelar, actualizacion, bandeja
        ])
        .setup(move |app| {
            // El menú de la barra (Mac) o de la bandeja (Linux): el estado en
            // una línea y lo imprescindible. Lo demás está en la ventana.
            let linea = MenuItem::with_id(app, "estado", "Consultando el estado…", false, None::<&str>)?;
            let abrir = MenuItem::with_id(app, "abrir", "Abrir Boson Server…", true, None::<&str>)?;
            let reiniciar = MenuItem::with_id(app, "reiniciar", "Reiniciar el servidor", true, None::<&str>)?;
            let salir = MenuItem::with_id(app, "salir", "Salir", true, None::<&str>)?;
            let menu = Menu::with_items(
                app,
                &[&linea, &PredefinedMenuItem::separator(app)?, &abrir, &reiniciar, &PredefinedMenuItem::separator(app)?, &salir],
            )?;
            *app.state::<Bandeja>().0.lock().unwrap() = Some(linea);
            let icono = Image::from_bytes(include_bytes!("../iconos/bandeja@2x.png"))?;
            TrayIconBuilder::with_id("principal")
                .icon(icono)
                .icon_as_template(true)
                .tooltip("Boson Server")
                .menu(&menu)
                .show_menu_on_left_click(true)
                .on_menu_event(|app, evento| match evento.id().as_ref() {
                    "abrir" => mostrar_ventana(app),
                    "reiniciar" => {
                        let app = app.clone();
                        thread::spawn(move || {
                            let _ = ejecutar(&app, &["--servidor", "reiniciar"]);
                            let _ = app.emit("refrescar", ());
                        });
                    }
                    "salir" => app.exit(0),
                    _ => {}
                })
                .build(app)?;
            // Arrancada al iniciar sesión va escondida: solo el icono de la
            // barra. Abierta a mano, se enseña.
            if !oculto {
                mostrar_ventana(app.handle());
            }
            Ok(())
        })
        // Cerrar la ventana no cierra la app: sigue en la barra, como un
        // servidor que es. Salir está en el menú de la barra.
        .on_window_event(|ventana, evento| {
            if let WindowEvent::CloseRequested { api, .. } = evento {
                api.prevent_close();
                let _ = ventana.hide();
            }
        })
        .build(tauri::generate_context!())
        .expect("no pude arrancar Boson Server");
    app.run(|app, evento| {
        // En el Mac, el clic en el icono del Dock con la ventana escondida.
        #[cfg(target_os = "macos")]
        if let RunEvent::Reopen { .. } = evento {
            mostrar_ventana(app);
        }
        #[cfg(not(target_os = "macos"))]
        let _ = (app, evento);
    });
}
