// Piezas pequeñas que se repiten en todas las pantallas.
import { useState, type ReactNode } from "react";
import { writeText } from "@tauri-apps/plugin-clipboard-manager";
import type { Textos } from "./textos";

export type Nivel = "ok" | "aviso" | "mal" | "gris";

export function Punto({ nivel }: { nivel: Nivel }) {
  return <span className={"punto " + nivel} />;
}

export function Pildora({ nivel, children }: { nivel: Nivel; children: ReactNode }) {
  return (
    <span className={"pildora " + nivel}>
      <Punto nivel={nivel} />
      {children}
    </span>
  );
}

export function Etiqueta({ children }: { children: ReactNode }) {
  return <span className="etiqueta">{children}</span>;
}

export function Boton({
  primario, pequeno, ancho, disabled, onClick, children,
}: { primario?: boolean; pequeno?: boolean; ancho?: boolean; disabled?: boolean; onClick?: () => void; children: ReactNode }) {
  const clases = ["boton", primario && "primario", pequeno && "pequeno", ancho && "ancho"].filter(Boolean).join(" ");
  return (
    <button type="button" className={clases} disabled={disabled} onClick={onClick}>
      {children}
    </button>
  );
}

/// Copia un texto, o el resultado de obtenerlo (una clave que se lee justo
/// entonces), y lo dice durante un momento.
export function BotonCopiar({
  texto, obtener, etiqueta, t, primario, pequeno, alFallar,
}: { texto?: string; obtener?: () => Promise<string>; etiqueta: string; t: Textos; primario?: boolean; pequeno?: boolean; alFallar?: (e: string) => void }) {
  const [hecho, setHecho] = useState(false);
  const copiar = async () => {
    try {
      const v = texto ?? (obtener ? await obtener() : "");
      await writeText(v);
      setHecho(true);
      setTimeout(() => setHecho(false), 1500);
    } catch (e) {
      alFallar?.(String(e));
    }
  };
  return (
    <Boton primario={primario} pequeno={pequeno} onClick={copiar}>
      {hecho ? t.copiado : etiqueta}
    </Boton>
  );
}

/// El círculo con la marca, la exclamación o vacío, para las listas de comprobaciones.
export function Marca({ nivel }: { nivel: Nivel }) {
  if (nivel === "ok") {
    return (
      <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
        <circle cx="9" cy="9" r="8" fill="var(--pildora-ok-fondo)" stroke="var(--ok)" strokeWidth="1.4" />
        <path d="M5.5 9.3l2.3 2.2 4.7-4.8" fill="none" stroke="var(--ok)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    );
  }
  if (nivel === "aviso" || nivel === "mal") {
    const color = nivel === "aviso" ? "var(--aviso)" : "var(--mal)";
    const fondo = nivel === "aviso" ? "var(--pildora-aviso-fondo)" : "var(--pildora-mal-fondo)";
    return (
      <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
        <circle cx="9" cy="9" r="8" fill={fondo} stroke={color} strokeWidth="1.4" />
        <path d="M9 5v4.5M9 12.2v.3" fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round" />
      </svg>
    );
  }
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
      <circle cx="9" cy="9" r="8" fill="none" stroke="var(--gris)" strokeWidth="1.4" />
    </svg>
  );
}

/// Una fila de comprobación: marca, título, explicación y, si hace falta, un botón.
export function Comprobacion({ nivel, titulo, texto, accion }: { nivel: Nivel; titulo: ReactNode; texto?: ReactNode; accion?: ReactNode }) {
  return (
    <div className="fila">
      <Marca nivel={nivel} />
      <div className="texto">
        <b>{titulo}</b>
        {texto && <span>{texto}</span>}
      </div>
      {accion}
    </div>
  );
}

export function duracion(segundos: number, t: Textos): string {
  const d = Math.floor(segundos / 86400);
  const h = Math.floor((segundos % 86400) / 3600);
  const m = Math.floor((segundos % 3600) / 60);
  if (d > 0) return `${d} ${t.duracion.d} ${h} ${t.duracion.h}`;
  if (h > 0) return `${h} ${t.duracion.h} ${m} ${t.duracion.min}`;
  if (m > 0) return `${m} ${t.duracion.min}`;
  return `${segundos} ${t.duracion.s}`;
}
