import { useState } from "react";
import { abrir, leerClave } from "../estado";
import type { Comunes } from "../App";
import type { Textos } from "../textos";
import { Boton, BotonCopiar, Etiqueta, Pildora, Punto, type Nivel } from "../ui";

/// Pegar el enlace de otro panel: la dirección va en CSM_JOIN_HUB y el token,
/// que viaja en el propio enlace (#t=…), en CSM_JOIN_TOKEN.
function SumarAOtro({ t, cerrar, lanzar }: { t: Textos; cerrar: () => void; lanzar: Comunes["lanzar"] }) {
  const [enlace, setEnlace] = useState("");
  const [error, setError] = useState<string | null>(null);
  const sumar = () => {
    const m = enlace.trim().match(/^(https?:\/\/[^/#?]+)[^#]*#t=([0-9A-Za-z]+)/);
    if (!m) { setError(t.csm.sumarInvalido); return; }
    cerrar();
    lanzar({ titulo: t.csm.sumando, args: ["--csm", "--no-ai", "--no-linkspace"], extra: { CSM_JOIN_HUB: m[1], CSM_JOIN_TOKEN: m[2] } });
  };
  return (
    <div className="velo" role="dialog" aria-modal="true" aria-label={t.csm.sumarTitulo}>
      <div className="dialogo" style={{ width: 480 }}>
        <h2 style={{ margin: 0, fontSize: 16 }}>{t.csm.sumarTitulo}</h2>
        <span className="nota">{t.csm.sumarPega}</span>
        <label htmlFor="enlace-panel" className="etiqueta">{t.csm.sumarCampo}</label>
        <input id="enlace-panel" className="entrada mono" type="text" spellCheck={false} value={enlace} onChange={(ev) => { setEnlace(ev.target.value); setError(null); }} onKeyDown={(ev) => { if (ev.key === "Enter") sumar(); }} />
        {error && <span className="nota" style={{ color: "var(--mal)" }}>{error}</span>}
        <div className="botones" style={{ justifyContent: "flex-end" }}>
          <Boton onClick={cerrar}>{t.claves.cancelar}</Boton>
          <Boton primario disabled={!enlace.trim()} onClick={sumar}>{t.csm.sumarBoton}</Boton>
        </div>
      </div>
    </div>
  );
}

export function Sesiones({ e, t, lanzar }: Comunes) {
  const [sumando, setSumando] = useState(false);
  const c = e.csm;
  const mac = e.equipo.so === "macos";
  const instalado = e.servidor.estado !== "sin_instalar";
  const nivel: Nivel = c.estado === "hub" || c.estado === "agente" ? "ok" : c.estado === "parado" ? "aviso" : "gris";
  const titulo = c.estado === "hub" ? t.csm.hub(c.puerto ?? 4000) : c.estado === "agente" ? t.csm.agente : c.estado === "parado" ? t.csm.parado : t.csm.ninguno;
  const hayNueva = c.version && c.version_repositorio && c.version !== c.version_repositorio;
  const abrirPanel = async () => { try { await abrir(await leerClave("csm")); } catch { if (c.url_panel) abrir(c.url_panel); } };
  const instalarPanel = () => lanzar({ titulo: t.csm.instalando, args: ["--csm", "--no-ai", "--no-linkspace"], extra: { CSM_JOIN_HUB: "" } });
  const actualizar = async () => {
    if (c.estado === "agente" && c.url_panel) {
      let token = "";
      try { token = (await leerClave("csm")).split("#t=")[1] ?? ""; } catch { /* sin token: el instalador lo dirá */ }
      lanzar({ titulo: t.csm.actualizando, args: ["--csm", "--no-ai", "--no-linkspace"], extra: { CSM_JOIN_HUB: c.url_panel, CSM_JOIN_TOKEN: token } });
    } else {
      lanzar({ titulo: t.csm.actualizando, args: ["--csm", "--no-ai", "--no-linkspace"], extra: { CSM_JOIN_HUB: "" } });
    }
  };

  return (
    <>
      <header className="cabecera">
        <div className="titulos">
          <h1>{t.nav.csm}</h1>
          <span className="sub">{t.csm.sub}</span>
        </div>
        <div className="derecha"><Pildora nivel={nivel}>{titulo}</Pildora></div>
      </header>

      <section className="tarjeta">
        <div className="fila">
          <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 4, minWidth: 0 }}>
            <h2>{c.instalado ? t.csm.instalado(c.version) : t.csm.ninguno}{c.instalado && c.version_repositorio ? ` · ${hayNueva ? t.csm.nuevaVersion(c.version_repositorio) : t.csm.alDia}` : ""}</h2>
            <span className="nota">{c.estado === "hub" ? t.csm.instaladoNota : c.estado === "agente" && c.url_panel ? t.csm.agenteNota(c.url_panel) : c.instalado ? t.csm.instaladoNota : t.csm.noNota}</span>
          </div>
          {c.instalado && c.url_panel && (
            <div className="botones">
              <Boton primario onClick={abrirPanel}>{t.csm.abrirPanel}</Boton>
              <BotonCopiar obtener={() => leerClave("csm")} etiqueta={t.csm.copiarEnlace} t={t} />
              <Boton primario={!!hayNueva} onClick={actualizar}>{t.csm.actualizar}</Boton>
            </div>
          )}
        </div>
        {!c.instalado && (
          <div className="botones">
            <Boton primario disabled={!instalado} onClick={instalarPanel}>{t.csm.instalarPanel}</Boton>
            <Boton disabled={!instalado} onClick={() => setSumando(true)}>{t.csm.sumarOtro}</Boton>
          </div>
        )}
        {!c.instalado && <span className="nota">{t.csm.instalarPanelNota}</span>}
      </section>

      <div className="rejilla dos">
        <section className="tarjeta">
          <Etiqueta>{t.csm.equipos}</Etiqueta>
          <div className="filas">
            {c.equipos.length === 0 && <span className="nota">{c.estado === "hub" ? t.csm.sinEquipos : "—"}</span>}
            {c.equipos.map((m, i) => (
              <div className="fila" key={i}>
                <Punto nivel={m.en_linea ? "ok" : "gris"} />
                <span className="crece">{m.nombre ?? "?"}{m.nombre && e.equipo.nombre && m.nombre.toLowerCase() === e.equipo.nombre.toLowerCase() ? <span className="nota"> · {t.csm.esteEquipo}</span> : null}</span>
                <span className="gris">{t.csm.sesiones(m.sesiones)}{m.esperando > 0 ? ` · ${t.csm.esperando(m.esperando)}` : ""}</span>
              </div>
            ))}
          </div>
          {c.estado === "hub" && (
            <div className="tarjeta" style={{ marginTop: "auto", background: "var(--campo)", padding: "10px 12px", gap: 6 }}>
              <b style={{ fontSize: 12 }}>{t.csm.sumar}</b>
              <span className="nota">{t.csm.sumarTexto}</span>
              <span className="mono seleccionable" style={{ fontSize: 12 }}>./setup.sh --csm</span>
            </div>
          )}
        </section>
        <section className="tarjeta">
          <Etiqueta>{t.csm.servicios}</Etiqueta>
          <div className="filas">
            <div className="fila"><Punto nivel={c.hub_servicio ? "ok" : "gris"} /><span className="crece">{t.csm.hubServicio}</span><span className="gris">{c.hub_servicio ? t.csm.si : t.csm.no}</span></div>
            <div className="fila"><Punto nivel={c.agente_servicio ? "ok" : "gris"} /><span className="crece">{t.csm.agenteServicio}</span><span className="gris">{c.agente_servicio ? t.csm.si : t.csm.no}</span></div>
          </div>
          {mac && c.instalado && (
            <div className="tarjeta" style={{ marginTop: "auto", background: "var(--campo)", padding: "10px 12px", gap: 6 }}>
              <span className="fila" style={{ fontSize: 12, fontWeight: 600 }}><Punto nivel={c.acceso_total_disco === true ? "ok" : c.acceso_total_disco === false ? "aviso" : "gris"} />{c.acceso_total_disco === false ? t.csm.discoNo : t.csm.disco}</span>
              <span className="nota">{t.csm.discoNota}</span>
            </div>
          )}
        </section>
      </div>
      {sumando && <SumarAOtro t={t} cerrar={() => setSumando(false)} lanzar={lanzar} />}
    </>
  );
}
