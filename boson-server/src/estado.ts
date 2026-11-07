// El contrato con `setup.sh --estado`: lo que la app sabe del equipo.
// Cada campo puede venir a null cuando el script no lo sabe; la interfaz lo
// enseña como «desconocido», nunca como fallo.
import { invoke } from "@tauri-apps/api/core";

export interface Publicacion {
  tipo: "editor" | "gestor" | "terminal" | "maquina" | "otro";
  nombre: string | null;
  nuestro: boolean;
  protocolo: "tcp" | "https";
  puerto: number;
  ruta: string | null;
  destino: string;
  funnel: boolean;
}

export interface Estado {
  version: number;
  generado: string;
  equipo: { nombre: string | null; so: "macos" | "linux"; version_so: string | null; arquitectura: string | null; usuario: string | null; home: string | null };
  boson: { repositorio: string | null; commit: string | null; fecha: string | null; copia_en_ivscode: boolean | null; servidor_al_dia: boolean | null; code_server: string | null; code_server_instalado: boolean | null; vscode: string | null };
  servidor: {
    estado: "sirviendo" | "arrancando" | "parado" | "sin_instalar";
    servicio: "launchd" | "systemd" | "ninguno";
    activado: boolean | null; corriendo: boolean | null; pid_servicio: number | null; puerto: number | null;
    editor: { responde: boolean | null; pid: number | null; segundos: number | null };
    gestor: { responde: boolean | null; puerto: number };
    terminal: { escucha: boolean; puerto: number };
    url: string | null; nombre: string | null; registro: string | null; password_existe: boolean | null;
    lanzador: "app" | "envoltura" | "script" | null;
  };
  tailscale: {
    instalado: boolean; ruta: string | null; version: string | null; estado: string | null; sesion: boolean;
    dns: string | null; ip: string | null; tailnet: string | null; cuenta: string | null; certificados: boolean | null;
    avisos: string[]; serve_habilitado: boolean | null; operador: boolean | null; serve_consultable: boolean | null;
    serve_error: string | null; publicaciones: Publicacion[];
  };
  csm: {
    instalado: boolean | null; estado: "hub" | "agente" | "parado" | "ninguno"; puerto: number | null; puerto_agente: number | null;
    url_panel: string | null; hub_servicio: boolean | null; agente_servicio: boolean | null; version: string | null;
    version_repositorio: string | null; acceso_total_disco: boolean | null;
    equipos: { nombre: string | null; so: string | null; en_linea: boolean; sesiones: number; esperando: number }[];
    sesiones: number; esperando: number;
  };
  ia: { copilot_integrado: string | null; extensiones: string[]; copilot: { estado: string | null; usuario: string | null } | null };
  linkspace: { comandos: boolean; al_dia: boolean; en_ivscode: boolean };
  simulador: { xcode: boolean | null; idb: boolean | null; adb: string | null; kvm: boolean | null; docker: string | null; docker_version: string | null };
}

// Fuera de Tauri (la interfaz abierta en un navegador con `npm run dev`) no
// hay scripts que consultar: se enseña un equipo de ejemplo, inventado, para
// poder mirar y probar las pantallas. Las claves son de mentira y «abrir» abre
// una pestaña.
const enTauri = "__TAURI_INTERNALS__" in window;

export const leerEstado = (): Promise<Estado> =>
  enTauri ? invoke<Estado>("estado") : fetch("/estado-ejemplo.json").then((r) => r.json() as Promise<Estado>);
export const leerClave = (cual: "editor" | "csm"): Promise<string> =>
  enTauri ? invoke<string>("clave", { cual }) : Promise.resolve(cual === "editor" ? "ejemplo-no-es-real" : "http://100.64.0.12:4000/#t=token-de-ejemplo");
export const abrir = (destino: string): Promise<void> =>
  enTauri ? invoke<void>("abrir", { destino }) : Promise.resolve(void window.open(destino, "_blank"));
export const bandeja = (texto: string): Promise<void> => (enTauri ? invoke<void>("bandeja", { texto }) : Promise.resolve());

export const esMac = navigator.platform.toLowerCase().includes("mac");
