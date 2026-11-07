import { useCallback, useEffect, useState, type ReactElement } from "react";
import { enable as activarArranque, disable as desactivarArranque, isEnabled as arranqueActivado } from "@tauri-apps/plugin-autostart";
import { abrir, bandeja, esMac, leerEstado, type Estado } from "./estado";
import { idiomaGuardado, textos, type Idioma } from "./textos";
import { accesoTotalDisco, buscarActualizacion, escucharRefresco, type Accion, type Actualizacion } from "./tarea";
import { Casa, Chispa, Deslizadores, Lineas, Llave, Movil, Puntos, Terminal } from "./iconos";
import { Boton } from "./ui";
import { Tarea } from "./PanelAccion";
import logoClaro from "./logos/boson-code-logo.svg";
import logoOscuro from "./logos/boson-code-logo-white.svg";
import { Inicio } from "./paginas/Inicio";
import { Tailscale } from "./paginas/Tailscale";
import { Claves } from "./paginas/Claves";
import { Sesiones } from "./paginas/Sesiones";
import { Asistente } from "./paginas/Asistente";
import { Simulador } from "./paginas/Simulador";
import { Registro } from "./paginas/Registro";
import { Ajustes } from "./paginas/Ajustes";

export type Seccion = "inicio" | "tailscale" | "claves" | "csm" | "ia" | "simulador" | "registro" | "ajustes";
const SECCIONES: Seccion[] = ["inicio", "tailscale", "claves", "csm", "ia", "simulador", "registro", "ajustes"];

// La sección va en el fragmento de la dirección (#claves): así el menú de la
// barra puede abrir una pantalla concreta, y en el navegador se puede enlazar.
function seccionInicial(): Seccion {
  const h = location.hash.replace("#", "") as Seccion;
  return SECCIONES.includes(h) ? h : "inicio";
}

/// Lo que cada pantalla recibe: el estado, los textos, cómo cambiar de
/// pantalla, cómo volver a consultar y cómo lanzar una acción.
export interface Comunes {
  e: Estado;
  t: ReturnType<typeof textos>;
  ir: (s: Seccion) => void;
  refrescar: () => void;
  lanzar: (a: Accion) => void;
  discoApp: boolean | null;
}

const VERSION = "1.0.0";
const CADA = 15_000;
const enTauri = "__TAURI_INTERNALS__" in window;

export default function App() {
  const [seccion, setSeccionEstado] = useState<Seccion>(seccionInicial);
  const [idioma, setIdioma] = useState<Idioma>(idiomaGuardado);
  const [estado, setEstado] = useState<Estado | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [accion, setAccion] = useState<Accion | null>(null);
  const [discoApp, setDiscoApp] = useState<boolean | null>(null);
  const [actualizacion, setActualizacion] = useState<Actualizacion | null>(null);
  const [arranque, setArranque] = useState<boolean | null>(null);
  const t = textos(idioma);

  const setSeccion = (s: Seccion) => {
    setSeccionEstado(s);
    history.replaceState(null, "", "#" + s);
  };

  const refrescar = useCallback(async () => {
    try {
      const e = await leerEstado();
      setEstado(e);
      setError(null);
      const linea = t.bandeja[e.servidor.estado] + (e.servidor.nombre ? ` · ${e.servidor.nombre}` : "");
      bandeja(linea).catch(() => {});
      accesoTotalDisco().then(setDiscoApp).catch(() => {});
    } catch (e) {
      setError(String(e));
    }
  }, [t]);

  useEffect(() => {
    refrescar();
    const id = setInterval(refrescar, CADA);
    const alVolver = () => refrescar();
    window.addEventListener("focus", alVolver);
    let quitar: (() => void) | null = null;
    escucharRefresco(refrescar).then((q) => { quitar = q; });
    return () => {
      clearInterval(id);
      window.removeEventListener("focus", alVolver);
      quitar?.();
    };
  }, [refrescar]);

  // Una vez por arranque: ¿hay versión nueva? ¿Arranca con la sesión? Y en la
  // vista previa del navegador, `?demo` abre el panel de una acción fingida.
  useEffect(() => {
    buscarActualizacion().then(setActualizacion).catch(() => {});
    if (enTauri) arranqueActivado().then(setArranque).catch(() => setArranque(null));
    if (!enTauri && location.search.includes("demo")) setAccion({ titulo: "Instalando el servidor", args: [] });
  }, []);

  const cambiarIdioma = (i: Idioma) => {
    setIdioma(i);
    try { localStorage.setItem("idioma", i); } catch { /* sin almacenamiento: se queda para esta sesión */ }
  };

  const cambiarArranque = async (activar: boolean) => {
    try {
      if (activar) await activarArranque(); else await desactivarArranque();
      setArranque(await arranqueActivado());
    } catch { setArranque(null); }
  };

  const nav: { id: Seccion; icono: () => ReactElement; nombre: string }[] = [
    { id: "inicio", icono: Casa, nombre: t.nav.inicio },
    { id: "tailscale", icono: Puntos, nombre: t.nav.tailscale },
    { id: "claves", icono: Llave, nombre: t.nav.claves },
    { id: "csm", icono: Terminal, nombre: t.nav.csm },
    { id: "ia", icono: Chispa, nombre: t.nav.ia },
    { id: "simulador", icono: Movil, nombre: t.nav.simulador },
    { id: "registro", icono: Lineas, nombre: t.nav.registro },
    { id: "ajustes", icono: Deslizadores, nombre: t.nav.ajustes },
  ];

  let pagina;
  if (!estado) {
    pagina = error ? (
      <div className="aviso-caja mal">
        <div>
          <b>{t.errorEstado}</b>
          <div className="seleccionable">{error}</div>
          <div style={{ marginTop: 8 }}><Boton pequeno onClick={refrescar}>{t.reintentar}</Boton></div>
        </div>
      </div>
    ) : (
      <div className="vacio">{t.cargando}</div>
    );
  } else {
    const comunes: Comunes = { e: estado, t, ir: setSeccion, refrescar, lanzar: setAccion, discoApp };
    switch (seccion) {
      case "inicio": pagina = <Inicio {...comunes} />; break;
      case "tailscale": pagina = <Tailscale {...comunes} />; break;
      case "claves": pagina = <Claves {...comunes} />; break;
      case "csm": pagina = <Sesiones {...comunes} />; break;
      case "ia": pagina = <Asistente {...comunes} />; break;
      case "simulador": pagina = <Simulador {...comunes} />; break;
      case "registro": pagina = <Registro {...comunes} />; break;
      case "ajustes":
        pagina = <Ajustes {...comunes} idioma={idioma} cambiarIdioma={cambiarIdioma} version={VERSION} arranque={arranque} cambiarArranque={cambiarArranque} actualizacion={actualizacion} setActualizacion={setActualizacion} />;
        break;
    }
  }

  const so = estado?.equipo.so === "linux" ? "Linux" : estado?.equipo.so === "macos" ? "macOS" : esMac ? "macOS" : "Linux";

  return (
    <div className={"app" + (esMac ? " mac" : "")}>
      <aside className="lateral">
        <div className="arrastre" data-tauri-drag-region />
        <div className="marca" data-tauri-drag-region>
          <img className="claro" src={logoClaro} alt="Boson Code" draggable={false} />
          <img className="oscuro" src={logoOscuro} alt="Boson Code" draggable={false} />
          <span className="etiqueta">{t.marca}</span>
        </div>
        <nav className="nav" aria-label={t.nav.inicio}>
          {nav.map((n) => (
            <button key={n.id} type="button" className={seccion === n.id ? "activo" : ""} onClick={() => setSeccion(n.id)}>
              <n.icono />
              {n.nombre}
            </button>
          ))}
        </nav>
        <div className="pie">
          <span>{t.version(VERSION, so)}</span>
          {actualizacion && (
            <button type="button" className="boton pequeno" style={{ alignSelf: "flex-start", color: "var(--enlace)", fontWeight: 600 }} onClick={() => abrir(actualizacion.url)}>
              {t.actualizacion(actualizacion.version)}
            </button>
          )}
          {error && estado && <span style={{ color: "var(--mal)" }}>{t.errorEstado}</span>}
        </div>
      </aside>
      <main className="contenido">{pagina}</main>
      {accion && <Tarea accion={accion} t={t} cerrar={() => setAccion(null)} alTerminar={refrescar} />}
    </div>
  );
}
