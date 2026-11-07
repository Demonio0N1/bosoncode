import { useState } from "react";
import { abrir, leerClave } from "../estado";
import type { Comunes } from "../App";
import { Ojo } from "../iconos";
import { QR, enlaceDeEmparejamiento } from "../QR";
import { Boton, BotonCopiar, Punto } from "../ui";
import type { Textos } from "../textos";

const PRIVACIDAD = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles";

/// Una clave que se lee solo al pulsar «Mostrar» o «Copiar», y que se vuelve a
/// ocultar al salir de la pantalla: nunca se queda en memoria más de lo que se mira.
function Secreto({ cual, t, prefijo }: { cual: "editor" | "csm"; t: Textos; prefijo?: string }) {
  const [valor, setValor] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const mostrar = async () => {
    if (valor !== null) { setValor(null); return; }
    try { setValor(await leerClave(cual)); setError(null); } catch (e) { setError(String(e)); }
  };
  const visible = valor !== null;
  const texto = visible ? valor : prefijo ? `${prefijo}••••••••••••` : "••••••••••••••••";
  return (
    <>
      <div className="fila" style={{ gap: 8 }}>
        <div className="campo" style={{ flex: 1 }}>
          <span className={"valor" + (visible ? " seleccionable" : " oculto")}>{texto}</span>
          <button type="button" className="ojo" aria-label={visible ? t.ocultar : t.mostrar} title={visible ? t.ocultar : t.mostrar} onClick={mostrar}>
            <Ojo tachado={visible} />
          </button>
        </div>
        <BotonCopiar primario obtener={() => leerClave(cual)} etiqueta={cual === "editor" ? t.copiar : t.claves.copiarEnlace} t={t} alFallar={setError} />
        {cual === "csm" && <Boton onClick={async () => { try { await abrir(await leerClave("csm")); } catch (e) { setError(String(e)); } }}>{t.abrir}</Boton>}
      </div>
      {error && <span className="nota" style={{ color: "var(--mal)" }}>{t.claves.error}{error}</span>}
    </>
  );
}

/// El diálogo de la contraseña nueva: la escribe quien quiere, o la genera el
/// script. Viaja por la entrada estándar de setup.sh, nunca como argumento.
function CambiarClave({ t, cerrar, lanzar }: { t: Textos; cerrar: () => void; lanzar: Comunes["lanzar"] }) {
  const [clave, setClave] = useState("");
  const enviar = (valor: string) => {
    cerrar();
    lanzar({ titulo: t.claves.cambiando, args: ["--nueva-clave"], entrada: valor });
  };
  return (
    <div className="velo" role="dialog" aria-modal="true" aria-label={t.claves.cambiarTitulo}>
      <div className="dialogo" style={{ width: 440 }}>
        <h2 style={{ margin: 0, fontSize: 16 }}>{t.claves.cambiarTitulo}</h2>
        <span className="nota">{t.claves.cambiarTexto}</span>
        <label htmlFor="clave-nueva" className="etiqueta">{t.claves.cambiarCampo}</label>
        <input id="clave-nueva" className="entrada" type="password" autoComplete="new-password" value={clave} onChange={(ev) => setClave(ev.target.value)} onKeyDown={(ev) => { if (ev.key === "Enter" && clave.length >= 6) enviar(clave); }} />
        <div className="botones" style={{ justifyContent: "flex-end" }}>
          <Boton onClick={cerrar}>{t.claves.cancelar}</Boton>
          <Boton primario disabled={clave.length < 6} onClick={() => enviar(clave)}>{t.claves.guardar}</Boton>
        </div>
        <span className="nota">{t.claves.generarTexto}</span>
        <div className="botones"><Boton onClick={() => enviar("")}>{t.claves.generarBoton}</Boton></div>
      </div>
    </div>
  );
}

export function Claves({ e, t, lanzar, discoApp }: Comunes) {
  const [cambiando, setCambiando] = useState(false);
  const [qr, setQr] = useState<string | null>(null);
  const [errorQr, setErrorQr] = useState<string | null>(null);
  const mac = e.equipo.so === "macos";
  const csm = e.csm;
  const disco = csm.acceso_total_disco;
  const s = e.servidor;
  const mostrarQr = async () => {
    if (!s.url) return;
    try { setQr(enlaceDeEmparejamiento(s.url, s.nombre ?? e.equipo.nombre ?? "", await leerClave("editor"))); } catch (err) { setErrorQr(String(err)); }
  };
  return (
    <>
      <header className="cabecera">
        <div className="titulos">
          <h1>{t.nav.claves}</h1>
          <span className="sub">{t.claves.sub}</span>
        </div>
      </header>

      <section className="tarjeta">
        <div className="fila"><h2>{t.claves.password}</h2><span className="nota">{t.claves.passwordSub}</span></div>
        {s.password_existe ? <Secreto cual="editor" t={t} /> : <span className="nota">{t.claves.sinPassword}</span>}
        <div className="botones">
          <Boton pequeno onClick={() => setCambiando(true)}>{t.claves.cambiar}</Boton>
          {s.url && s.password_existe && <Boton pequeno onClick={mostrarQr}>{t.claves.qr}</Boton>}
        </div>
        {errorQr && <span className="nota" style={{ color: "var(--mal)" }}>{errorQr}</span>}
        <span className="nota">{t.claves.passwordNota}</span>
      </section>

      <section className="tarjeta">
        <div className="fila"><h2>{t.claves.enlace}</h2><span className="nota">{t.claves.enlaceSub}</span></div>
        {csm.instalado && csm.url_panel ? <Secreto cual="csm" t={t} prefijo={`${csm.url_panel}/#t=`} /> : <span className="nota">{t.claves.sinCsm}</span>}
        <span className="nota">{t.claves.enlaceNota}</span>
      </section>

      <div className="rejilla dos">
        <section className="tarjeta">
          <h2>{t.claves.copilot}</h2>
          <span className="fila"><Punto nivel={e.ia.copilot_integrado ? "ok" : "gris"} />{e.ia.copilot_integrado ? t.claves.copilotIntegrado(e.ia.copilot_integrado) : t.claves.copilotNo}</span>
          <span className="nota">{t.claves.copilotNota}</span>
        </section>
        {mac && (
          <section className="tarjeta">
            <h2>{t.claves.discoServidor}</h2>
            <span className="fila"><Punto nivel={discoApp === true ? "ok" : discoApp === false ? "aviso" : "gris"} />{discoApp === true ? t.claves.discoServidorSi : discoApp === false ? t.claves.discoServidorNo : t.desconocido}</span>
            <span className="nota">{t.claves.discoServidorNota}{s.lanzador && s.lanzador !== "app" ? ` ${t.claves.discoPendiente}` : ""}</span>
            {csm.instalado && <span className="fila nota"><Punto nivel={disco === true ? "ok" : disco === false ? "aviso" : "gris"} />{disco === true ? t.claves.discoSi : disco === false ? t.claves.discoNo : t.desconocido}</span>}
            <div className="botones"><Boton pequeno primario={discoApp === false} onClick={() => abrir(PRIVACIDAD)}>{t.claves.abrirPrivacidad}</Boton></div>
          </section>
        )}
      </div>
      {cambiando && <CambiarClave t={t} cerrar={() => setCambiando(false)} lanzar={lanzar} />}
      {qr && <QR texto={qr} titulo={t.inicio.qr} nota={t.inicio.qrNota} t={t} cerrar={() => setQr(null)} />}
    </>
  );
}
