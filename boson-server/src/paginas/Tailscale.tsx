import { abrir } from "../estado";
import type { Comunes } from "../App";
import { Boton, BotonCopiar, Comprobacion, Etiqueta, Pildora, Punto, type Nivel } from "../ui";

const PANEL_DNS = "https://login.tailscale.com/admin/dns";
const DESCARGA = "https://tailscale.com/download";
const IPAD = "https://apps.apple.com/app/tailscale/id1470499037";

export function Tailscale({ e, t, lanzar }: Comunes) {
  const ts = e.tailscale;
  const mac = e.equipo.so === "macos";
  const nivel: Nivel = !ts.instalado ? "gris" : ts.sesion ? "ok" : "aviso";
  const titulo = !ts.instalado ? t.tailscale.noInstalado : ts.sesion ? t.tailscale.conectado : ts.estado === "NeedsLogin" ? t.tailscale.sinSesion : t.tailscale.parado;
  const abrirTailscale = () => abrir(mac ? "/Applications/Tailscale.app" : "https://login.tailscale.com/");
  const iniciarSesion = () => lanzar({ titulo: t.tarea.sesion, args: ["--sesion-tailscale"] });
  const nuestras = ts.publicaciones.filter((p) => p.nuestro);
  const ajenas = ts.publicaciones.filter((p) => !p.nuestro);

  return (
    <>
      <header className="cabecera">
        <div className="titulos">
          <h1>Tailscale</h1>
          <span className="sub">{t.tailscale.sub}</span>
        </div>
        <div className="derecha"><Pildora nivel={nivel}>{titulo}</Pildora></div>
      </header>

      <section className="tarjeta lista">
        <Comprobacion
          nivel={ts.instalado ? "ok" : "mal"}
          titulo={ts.instalado ? t.tailscale.instalado : t.tailscale.noInstalado}
          texto={ts.instalado ? t.tailscale.versionApp(ts.version ?? "") : t.tailscale.noInstaladoTexto}
          accion={ts.instalado ? <Boton pequeno onClick={abrirTailscale}>{t.tailscale.abrirTailscale}</Boton> : <Boton pequeno primario onClick={() => abrir(DESCARGA)}>{t.tailscale.descargar}</Boton>}
        />
        <Comprobacion
          nivel={ts.sesion ? "ok" : ts.instalado ? "aviso" : "gris"}
          titulo={ts.sesion ? t.tailscale.sesion : t.tailscale.sinSesion}
          texto={ts.sesion ? (<>{t.tailscale.esteEquipo}<span className="mono seleccionable" style={{ color: "var(--texto)" }}>{ts.dns}</span>{ts.ip ? ` · ${ts.ip}` : ""}{ts.cuenta ? ` · ${t.tailscale.cuenta(ts.cuenta)}` : ""}</>) : t.tailscale.sinSesionTexto}
          accion={ts.instalado && !ts.sesion ? <Boton pequeno primario onClick={iniciarSesion}>{t.tailscale.iniciarSesion}</Boton> : undefined}
        />
        <Comprobacion
          nivel={ts.serve_habilitado === true ? "ok" : ts.serve_habilitado === false ? "aviso" : "gris"}
          titulo={t.tailscale.serve}
          texto={ts.serve_habilitado === true ? t.tailscale.serveTexto : ts.serve_habilitado === false ? t.tailscale.serveNo : t.tailscale.serveDesconocido}
        />
        <Comprobacion
          nivel={ts.certificados === true ? "ok" : ts.certificados === false ? "aviso" : "gris"}
          titulo={t.tailscale.cert}
          texto={ts.certificados === true ? t.tailscale.certSi : ts.certificados === false ? t.tailscale.certNo : t.tailscale.serveDesconocido}
        />
        <Comprobacion
          nivel={mac ? "gris" : ts.operador === true ? "ok" : ts.operador === false ? "aviso" : "gris"}
          titulo={t.tailscale.operador}
          texto={mac ? t.tailscale.operadorMac : ts.operador === true ? t.tailscale.operadorSi : t.tailscale.operadorNo}
          accion={!mac && ts.instalado && ts.operador !== true ? <Boton pequeno primario onClick={() => lanzar({ titulo: t.tarea.operador, args: ["--operador"] })}>{t.tailscale.conceder}</Boton> : undefined}
        />
        <Comprobacion
          nivel={ts.certificados && ts.dns ? "ok" : "gris"}
          titulo={t.tailscale.dns}
          texto={t.tailscale.dnsTexto}
          accion={<Boton pequeno onClick={() => abrir(PANEL_DNS)}>{t.tailscale.abrirPanel}</Boton>}
        />
      </section>

      {ts.avisos.length > 0 && (
        <div className="aviso-caja">
          <div>
            <b>{t.tailscale.avisos}</b>
            {ts.avisos.map((a, i) => <div key={i}>{a}</div>)}
          </div>
        </div>
      )}

      <div className="rejilla ancha">
        <section className="tarjeta">
          <Etiqueta>{t.tailscale.publicado}</Etiqueta>
          <div className="filas">
            {nuestras.length === 0 && <span className="nota">{t.inicio.nadaPublicado}</span>}
            {nuestras.map((p, i) => (
              <div className="fila" key={i}>
                <Punto nivel="ok" />
                <span className="crece">{p.tipo === "editor" ? t.inicio.editor : p.tipo === "gestor" ? t.inicio.gestor : p.tipo === "terminal" ? t.inicio.terminal : t.inicio.maquina(p.nombre ?? "?")}</span>
                <span className="mono">{p.protocolo} :{p.puerto}{p.ruta && p.ruta !== "/" ? p.ruta : ""} → {p.destino.replace(/^https?:\/\//, "")}</span>
              </div>
            ))}
            {ajenas.map((p, i) => (
              <div className="fila" key={"a" + i}>
                <Punto nivel="gris" />
                <span className="crece gris mono">{p.protocolo} :{p.puerto}{p.ruta ?? ""} → {p.destino.replace(/^https?:\/\//, "")}</span>
                <span className="nota">{p.funnel ? t.tailscale.funnel : t.tailscale.ajeno}</span>
              </div>
            ))}
          </div>
          <span className="nota" style={{ marginTop: "auto" }}>{t.tailscale.nota}</span>
        </section>
        <section className="tarjeta">
          <Etiqueta>{t.tailscale.acciones}</Etiqueta>
          <div className="botones columna">
            {e.servidor.url && <BotonCopiar texto={e.servidor.url} etiqueta={t.tailscale.copiarDireccion} t={t} />}
            {e.servidor.estado !== "sin_instalar" && <Boton ancho onClick={() => lanzar({ titulo: t.tarea.reiniciando, args: ["--servidor", "reiniciar"] })}>{t.tailscale.republicar}</Boton>}
            <Boton ancho onClick={() => abrir(IPAD)}>{t.tailscale.ipad}</Boton>
          </div>
          <span className="nota">{t.tailscale.republicarNota} {t.tailscale.ipadNota}</span>
        </section>
      </div>
    </>
  );
}
