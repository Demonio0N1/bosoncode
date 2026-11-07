// El panel de una acción en marcha: los pasos, los enlaces que hay que abrir,
// el registro completo plegado y el final: hecho, te toca, o falló.
import { useEffect, useRef, useState } from "react";
import { abrir } from "./estado";
import { cancelarAccion, escucharAcciones, iniciarAccion, TE_TOCA, type Accion } from "./tarea";
import type { Textos } from "./textos";
import { Boton, Marca, type Nivel } from "./ui";

interface Paso { titulo: string; nivel: Nivel; }
interface Enlace { url: string; texto: string; }

const TAILSCALE_LOGIN = /https:\/\/login\.tailscale\.com\/\S+/;

export function Tarea({ accion, t, cerrar, alTerminar }: { accion: Accion; t: Textos; cerrar: () => void; alTerminar: () => void }) {
  const [lineas, setLineas] = useState<string[]>([]);
  const [pasos, setPasos] = useState<Paso[]>([]);
  const [enlaces, setEnlaces] = useState<Enlace[]>([]);
  const [fin, setFin] = useState<number | null | "cancelada">(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  const registro = useRef<HTMLPreElement>(null);
  const abiertoSolo = useRef(false);

  useEffect(() => {
    let id = -1;
    let quitar: (() => void) | null = null;
    let vivo = true;
    setLineas([]); setPasos([]); setEnlaces([]); setFin(null); setError(null);
    abiertoSolo.current = false;
    (async () => {
      quitar = await escucharAcciones((ev) => {
        if (!vivo || ev.id !== id) return;
        if (ev.tipo === "fin") { setFin(ev.codigo); return; }
        const texto = ev.texto;
        setLineas((l) => [...l, texto.replace(/^@@(titulo|ok|falta|enlace) /, "")]);
        if (texto.startsWith("@@titulo ")) {
          setPasos((p) => [...p, { titulo: texto.slice(9), nivel: "gris" }]);
        } else if (texto.startsWith("@@ok ")) {
          setPasos((p) => marcar(p, "ok"));
        } else if (texto.startsWith("@@falta ")) {
          setPasos((p) => marcar(p, "aviso"));
        } else if (texto.startsWith("@@enlace ")) {
          const [url, ...resto] = texto.slice(9).split(" ");
          setEnlaces((e) => (e.some((x) => x.url === url) ? e : [...e, { url, texto: resto.join(" ") || url }]));
        } else {
          const m = texto.match(TAILSCALE_LOGIN);
          if (m) {
            const url = m[0];
            setEnlaces((e) => (e.some((x) => x.url === url) ? e : [...e, { url, texto: t.tarea.iniciarSesionTailscale }]));
            if (!abiertoSolo.current) { abiertoSolo.current = true; abrir(url).catch(() => {}); }
          }
        }
      });
      try {
        id = await iniciarAccion(accion);
      } catch (e) {
        setError(String(e));
        setFin(1);
      }
    })();
    return () => { vivo = false; quitar?.(); };
  }, [accion, intento, t]);

  useEffect(() => {
    const el = registro.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [lineas]);

  // Un paso «se cierra» cuando empieza el siguiente: el último queda abierto
  // hasta entonces y es el que lleva las marcas que van llegando.
  const marcar = (p: Paso[], nivel: Nivel): Paso[] => {
    if (p.length === 0) return p;
    const ultimo = p[p.length - 1];
    const nuevo = ultimo.nivel === "aviso" ? "aviso" : nivel;
    return [...p.slice(0, -1), { ...ultimo, nivel: nuevo }];
  };

  const terminado = fin !== null;
  const titulo = !terminado ? accion.titulo : fin === 0 ? t.tarea.hecho : fin === TE_TOCA ? t.tarea.teToca : fin === "cancelada" ? t.tarea.cancelada : t.tarea.fallo;
  const nivelFinal: Nivel = !terminado ? "gris" : fin === 0 ? "ok" : fin === TE_TOCA ? "aviso" : "mal";

  const cancelar = async () => { await cancelarAccion(); setFin("cancelada"); };
  const terminar = () => { alTerminar(); cerrar(); };

  return (
    <div className="velo" role="dialog" aria-modal="true" aria-label={accion.titulo}>
      <div className="dialogo">
        <div className="fila" style={{ gap: 10 }}>
          {terminado ? <Marca nivel={nivelFinal} /> : <span className="girando" aria-hidden="true" />}
          <h2 style={{ margin: 0, fontSize: 16, flex: 1 }}>{titulo}</h2>
        </div>
        {!terminado && <span className="nota">{accion.titulo === t.tarea.hecho ? "" : t.tarea.enMarcha}</span>}
        {pasos.length > 0 && (
          <div className="filas">
            {pasos.map((p, i) => (
              <div className="fila" key={i}>
                <Marca nivel={i === pasos.length - 1 && !terminado && p.nivel === "gris" ? "gris" : p.nivel === "gris" ? "ok" : p.nivel} />
                <span className="crece">{p.titulo}</span>
              </div>
            ))}
          </div>
        )}
        {enlaces.length > 0 && (
          <div className="tarjeta" style={{ background: "var(--campo)", padding: "10px 12px", gap: 8 }}>
            <b style={{ fontSize: 12 }}>{t.tarea.abreEsto}</b>
            <div className="botones">
              {enlaces.map((e) => <Boton key={e.url} primario pequeno onClick={() => abrir(e.url)}>{e.texto}</Boton>)}
            </div>
          </div>
        )}
        {error && <span className="nota" style={{ color: "var(--mal)" }}>{error}</span>}
        <details open={terminado && fin !== 0}>
          <summary className="nota" style={{ cursor: "default" }}>{t.tarea.detalles}</summary>
          <pre className="registro" ref={registro}>{lineas.join("\n") || t.tarea.sinSalida}</pre>
        </details>
        <div className="botones" style={{ justifyContent: "flex-end" }}>
          {!terminado && <Boton onClick={cancelar}>{t.tarea.cancelar}</Boton>}
          {terminado && fin === TE_TOCA && <Boton primario onClick={() => setIntento((n) => n + 1)}>{t.tarea.reintentar}</Boton>}
          {terminado && <Boton primario={fin !== TE_TOCA} onClick={terminar}>{t.tarea.cerrar}</Boton>}
        </div>
      </div>
    </div>
  );
}
