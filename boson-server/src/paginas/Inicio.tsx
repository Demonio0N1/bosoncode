import { useState } from "react";
import { abrir, leerClave, type Estado } from "../estado";
import type { Comunes } from "../App";
import { QR, enlaceDeEmparejamiento } from "../QR";
import { Boton, BotonCopiar, Etiqueta, Pildora, Punto, duracion, type Nivel } from "../ui";

export function Inicio({ e, t, ir, refrescar, lanzar }: Comunes) {
  const [qr, setQr] = useState<string | null>(null);
  const [errorQr, setErrorQr] = useState<string | null>(null);
  const s = e.servidor;
  const ts = e.tailscale;
  const mac = e.equipo.so === "macos";
  const nivelServidor: Nivel = s.estado === "sirviendo" ? "ok" : s.estado === "arrancando" ? "aviso" : s.estado === "parado" ? "mal" : "gris";
  const publicaEditor = ts.sesion && ts.publicaciones.some((p) => p.tipo === "editor");
  const tsNivel: Nivel = !ts.instalado ? "gris" : ts.sesion ? "ok" : "aviso";
  const tsValor = !ts.instalado ? t.inicio.tsNo : ts.sesion ? t.inicio.tsConectado : ts.estado === "NeedsLogin" ? t.inicio.tsSinSesion : t.inicio.tsParado;
  const csm = e.csm;
  const csmNivel: Nivel = csm.estado === "hub" || csm.estado === "agente" ? "ok" : csm.estado === "parado" ? "aviso" : "gris";
  const csmValor = csm.estado === "hub" ? t.inicio.csmHub : csm.estado === "agente" ? t.inicio.csmAgente : csm.estado === "parado" ? t.inicio.csmParado : t.inicio.csmNo;
  const ia = e.ia;
  const ls = e.linkspace;
  const lsNivel: Nivel = ls.comandos ? "ok" : ls.en_ivscode ? "aviso" : "gris";
  const lsValor = ls.comandos ? t.inicio.lsInstalado : ls.en_ivscode ? t.inicio.lsParcial : t.inicio.lsNo;
  const nuestras = ts.publicaciones.filter((p) => p.nuestro);
  const ajenas = ts.publicaciones.filter((p) => !p.nuestro);
  const instalado = s.estado !== "sin_instalar";
  const INSTALAR = ["--no-csm", "--no-ai", "--no-linkspace"];

  const nombrePub = (p: Estado["tailscale"]["publicaciones"][number]) => {
    switch (p.tipo) {
      case "editor": return t.inicio.editor;
      case "gestor": return t.inicio.gestor;
      case "terminal": return t.inicio.terminal;
      case "maquina": return t.inicio.maquina(p.nombre ?? "?");
      default: return `${p.protocolo} :${p.puerto}${p.ruta ?? ""}`;
    }
  };

  const mostrarQr = async () => {
    if (!s.url) return;
    try {
      setQr(enlaceDeEmparejamiento(s.url, s.nombre ?? e.equipo.nombre ?? "", await leerClave("editor")));
    } catch (err) { setErrorQr(String(err)); }
  };

  return (
    <>
      <header className="cabecera">
        <div className="titulos">
          <h1>{e.equipo.nombre ?? t.desconocido}</h1>
          <span className="sub">{t.inicio.sub(e.equipo.version_so ?? e.equipo.so, e.boson.code_server, t.inicio.servicio[s.servicio])}</span>
        </div>
        <div className="derecha">
          <Pildora nivel={nivelServidor}>
            {t.estado[s.estado]}
            {s.editor.segundos ? ` · ${duracion(s.editor.segundos, t)}` : ""}
          </Pildora>
        </div>
      </header>

      {!instalado && (
        <section className="tarjeta">
          <h2>{t.inicio.instalar}</h2>
          <span className="nota">{t.inicio.instalarTexto}</span>
          <div className="botones"><Boton primario onClick={() => lanzar({ titulo: t.tarea.instalando, args: INSTALAR })}>{t.inicio.instalar}</Boton></div>
        </section>
      )}

      <section className="tarjeta">
        <Etiqueta>{t.inicio.direccion}</Etiqueta>
        {s.url ? <span className="direccion seleccionable">{s.url}</span> : <span className="nota">{t.inicio.sinDireccion}</span>}
        {s.nombre && (
          <span className="nota">
            {t.inicio.nombreApp(s.nombre)}<b style={{ color: "var(--texto)" }}>{s.nombre}</b>{t.inicio.nombreApp2}
          </span>
        )}
        {s.url && (
          <div className="botones">
            <BotonCopiar primario texto={s.url} etiqueta={t.inicio.copiarDireccion} t={t} />
            <Boton onClick={() => abrir(s.url!)}>{t.inicio.abrirNavegador}</Boton>
            {s.password_existe && <Boton onClick={mostrarQr}>{t.inicio.qr}</Boton>}
          </div>
        )}
        {errorQr && <span className="nota" style={{ color: "var(--mal)" }}>{errorQr}</span>}
      </section>

      <div className="rejilla cuatro">
        <button type="button" className="tarjeta loseta" onClick={() => ir("tailscale")}>
          <Etiqueta>{t.inicio.losetas.tailscale}</Etiqueta>
          <span className="valor"><Punto nivel={tsNivel} />{tsValor}</span>
          <span className="detalle">{t.inicio.tsDetalle(publicaEditor)}</span>
        </button>
        <button type="button" className="tarjeta loseta" onClick={() => ir("csm")}>
          <Etiqueta>{t.inicio.losetas.csm}</Etiqueta>
          <span className="valor"><Punto nivel={csmNivel} />{csmValor}</span>
          <span className="detalle">{csm.estado === "hub" ? t.inicio.csmDetalle(csm.equipos.length, csm.sesiones) : csm.url_panel ?? "—"}</span>
        </button>
        <button type="button" className="tarjeta loseta" onClick={() => ir("ia")}>
          <Etiqueta>{t.inicio.losetas.ia}</Etiqueta>
          <span className="valor"><Punto nivel={ia.copilot_integrado ? "ok" : "gris"} />{ia.copilot_integrado ? t.inicio.iaCopilot : t.inicio.iaNo}</span>
          <span className="detalle">{t.inicio.iaDetalle(ia.copilot_integrado)}</span>
        </button>
        <div className="tarjeta loseta">
          <Etiqueta>{t.inicio.losetas.linkspace}</Etiqueta>
          <span className="valor"><Punto nivel={lsNivel} />{lsValor}</span>
          <span className="detalle">{t.inicio.lsDetalle}</span>
        </div>
      </div>

      <div className="rejilla ancha">
        <section className="tarjeta">
          <Etiqueta>{t.inicio.publica}</Etiqueta>
          <div className="filas">
            {nuestras.length === 0 && <span className="nota">{t.inicio.nadaPublicado}</span>}
            {nuestras.map((p, i) => (
              <div className="fila" key={i}>
                <Punto nivel="ok" />
                <span className="crece">{nombrePub(p)}</span>
                <span className="mono">{p.tipo === "maquina" ? p.ruta + "/" : `:${p.puerto}`}</span>
              </div>
            ))}
            {ajenas.map((p, i) => (
              <div className="fila" key={"a" + i}>
                <Punto nivel="gris" />
                <span className="crece gris">{nombrePub(p)}</span>
                <span className="nota">{p.funnel ? t.tailscale.funnel : t.tailscale.ajeno}</span>
              </div>
            ))}
          </div>
        </section>
        <section className="tarjeta">
          <Etiqueta>{t.inicio.acciones}</Etiqueta>
          <div className="botones columna">
            {instalado && e.boson.servidor_al_dia === false && (
              <Boton ancho primario onClick={() => lanzar({ titulo: t.inicio.actualizarServidor, args: INSTALAR })}>{t.inicio.actualizarServidor}</Boton>
            )}
            {instalado && mac && s.lanzador === "envoltura" && (
              <Boton ancho primario onClick={() => lanzar({ titulo: t.inicio.pasarALaApp, args: INSTALAR })}>{t.inicio.pasarALaApp}</Boton>
            )}
            {instalado && (
              <Boton ancho onClick={() => lanzar({ titulo: t.tarea.reiniciando, args: ["--servidor", "reiniciar"] })}>{t.inicio.reiniciar}</Boton>
            )}
            {instalado && s.corriendo && (
              <Boton ancho onClick={() => lanzar({ titulo: t.tarea.deteniendo, args: ["--servidor", "detener"] })}>{t.inicio.detener}</Boton>
            )}
            {instalado && !s.corriendo && (
              <Boton ancho onClick={() => lanzar({ titulo: t.tarea.arrancando, args: ["--servidor", "arrancar"] })}>{t.inicio.arrancar}</Boton>
            )}
            {instalado && !ls.comandos && (
              <Boton ancho onClick={() => lanzar({ titulo: t.tarea.linkspace, args: ["--linkspace", "--no-csm", "--no-ai"] })}>{t.inicio.linkspaceInstalar}</Boton>
            )}
            {instalado && (
              <Boton ancho onClick={() => lanzar({ titulo: t.tarea.reparando, args: INSTALAR })}>{t.inicio.reparar}</Boton>
            )}
            <Boton ancho onClick={() => ir("registro")}>{t.inicio.verRegistro}</Boton>
            <Boton ancho onClick={refrescar}>{t.inicio.refrescar}</Boton>
          </div>
          {instalado && e.boson.servidor_al_dia === false && <span className="nota">{t.inicio.actualizarServidorNota}</span>}
          {instalado && mac && s.lanzador === "envoltura" && <span className="nota">{t.inicio.pasarALaAppNota}</span>}
        </section>
      </div>
      {qr && <QR texto={qr} titulo={t.inicio.qr} nota={t.inicio.qrNota} t={t} cerrar={() => setQr(null)} />}
    </>
  );
}
