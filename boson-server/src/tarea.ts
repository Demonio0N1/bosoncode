// Acciones con salida en vivo: setup.sh corre con unos argumentos y cada
// línea llega como un evento «accion» hasta el «fin» con su código.
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export interface EventoAccion {
  id: number;
  tipo: "linea" | "fin";
  texto: string;
  codigo: number | null;
}

/// Código con el que setup.sh dice «te toca a ti»: abre el enlace, haz lo que
/// pide y vuelve a intentarlo. No es un fallo.
export const TE_TOCA = 10;

export interface Accion {
  titulo: string;
  args: string[];
  extra?: Record<string, string>;
  entrada?: string;
}

const enTauri = "__TAURI_INTERNALS__" in window;

// Fuera de Tauri (vista previa en el navegador) la acción se finge: unas
// líneas con marcas, un enlace y un final, para poder mirar el panel.
const fingidos = new EventTarget();
let contadorFingido = 0;
function fingir(id: number) {
  const guion: [number, EventoAccion][] = [
    [200, { id, tipo: "linea", texto: "@@titulo 1 · Tailscale", codigo: null }],
    [500, { id, tipo: "linea", texto: "@@ok instalado", codigo: null }],
    [800, { id, tipo: "linea", texto: "@@titulo 2 · Sesión de Tailscale", codigo: null }],
    [1100, { id, tipo: "linea", texto: "    abriendo el inicio de sesión; termínalo en el navegador", codigo: null }],
    [1400, { id, tipo: "linea", texto: "@@enlace https://login.tailscale.com/a/ejemplo Iniciar sesión en Tailscale", codigo: null }],
    [1700, { id, tipo: "linea", texto: "@@titulo 3 · Servidor", codigo: null }],
    [2000, { id, tipo: "linea", texto: "→ descargando code-server-4.134.0…", codigo: null }],
    [2600, { id, tipo: "linea", texto: "@@falta el instalador se detuvo (ejemplo)", codigo: null }],
    [2900, { id, tipo: "fin", texto: "", codigo: TE_TOCA }],
  ];
  for (const [ms, ev] of guion) setTimeout(() => fingidos.dispatchEvent(new CustomEvent("accion", { detail: ev })), ms);
}

export async function iniciarAccion(a: Accion): Promise<number> {
  if (!enTauri) {
    const id = ++contadorFingido;
    fingir(id);
    return id;
  }
  return invoke<number>("accion_iniciar", { args: a.args, extra: a.extra ?? {}, entrada: a.entrada ?? null });
}

export const cancelarAccion = (): Promise<void> => (enTauri ? invoke<void>("accion_cancelar") : Promise.resolve());

export async function escucharAcciones(f: (e: EventoAccion) => void): Promise<UnlistenFn> {
  if (!enTauri) {
    const oyente = (ev: Event) => f((ev as CustomEvent<EventoAccion>).detail);
    fingidos.addEventListener("accion", oyente);
    return () => fingidos.removeEventListener("accion", oyente);
  }
  return listen<EventoAccion>("accion", (ev) => f(ev.payload));
}

export async function escucharRefresco(f: () => void): Promise<UnlistenFn> {
  if (!enTauri) return () => {};
  return listen("refrescar", () => f());
}

export const accesoTotalDisco = (): Promise<boolean | null> => (enTauri ? invoke<boolean | null>("acceso_total_disco") : Promise.resolve(false));

export interface Actualizacion {
  version: string;
  url: string;
}
export const buscarActualizacion = (): Promise<Actualizacion | null> =>
  enTauri ? invoke<Actualizacion | null>("actualizacion") : Promise.resolve(null);
