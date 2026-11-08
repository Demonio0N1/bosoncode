import { useState } from "react";
import { abrir } from "../estado";
import type { Comunes } from "../App";
import type { Idioma } from "../textos";
import { buscarActualizacion, type Actualizacion } from "../tarea";
import { Boton, Etiqueta } from "../ui";

export function Ajustes({ e, t, idioma, cambiarIdioma, version, arranque, cambiarArranque, actualizacion, setActualizacion }: Comunes & {
  idioma: Idioma; cambiarIdioma: (i: Idioma) => void; version: string;
  arranque: boolean | null; cambiarArranque: (activar: boolean) => void;
  actualizacion: Actualizacion | null; setActualizacion: (a: Actualizacion | null) => void;
}) {
  const [buscando, setBuscando] = useState(false);
  const [resultado, setResultado] = useState<"alDia" | "sinRed" | null>(null);
  const buscar = async () => {
    setBuscando(true); setResultado(null);
    try {
      const a = await buscarActualizacion();
      setActualizacion(a);
      if (!a) setResultado("alDia");
    } catch { setResultado("sinRed"); } finally { setBuscando(false); }
  };
  return (
    <>
      <header className="cabecera">
        <div className="titulos">
          <h1>{t.nav.ajustes}</h1>
          <span className="sub">{t.ajustes.sub}</span>
        </div>
      </header>
      <section className="tarjeta">
        <Etiqueta>{t.ajustes.general}</Etiqueta>
        <div className="fila">
          <label htmlFor="idioma" className="crece">{t.ajustes.idioma}</label>
          <select id="idioma" className="selector" value={idioma} onChange={(ev) => cambiarIdioma(ev.target.value as Idioma)}>
            <option value="sistema">{t.ajustes.sistema}</option>
            <option value="es">{t.ajustes.espanol}</option>
            <option value="en">{t.ajustes.ingles}</option>
          </select>
        </div>
        <label className="interruptor">
          <input type="checkbox" id="arranque" checked={arranque === true} disabled={arranque === null} onChange={(ev) => cambiarArranque(ev.target.checked)} />
          <span>{t.ajustes.arranque}</span>
        </label>
        <span className="nota">{t.ajustes.arranqueNota}</span>
      </section>
      <section className="tarjeta">
        <Etiqueta>{t.ajustes.actualizaciones}</Etiqueta>
        <div className="fila">
          <span className="crece">{actualizacion ? t.ajustes.hay(actualizacion.version) : resultado === "alDia" ? t.ajustes.alDia : resultado === "sinRed" ? t.ajustes.sinRed : `Boson Server ${version}`}</span>
          {actualizacion && <Boton pequeno primario onClick={() => abrir(actualizacion.url)}>{t.ajustes.descargar}</Boton>}
          <Boton pequeno disabled={buscando} onClick={buscar}>{buscando ? t.ajustes.buscando : t.ajustes.buscar}</Boton>
        </div>
      </section>
      <section className="tarjeta">
        <Etiqueta>{t.ajustes.acerca}</Etiqueta>
        <div className="filas">
          <div className="fila"><span className="crece">Boson Server</span><span className="gris">{version}</span></div>
          <div className="fila"><span className="crece">{t.ajustes.repo}</span><span className="gris mono seleccionable">{e.boson.repositorio ?? "—"}</span></div>
          {e.boson.commit && <div className="fila"><span className="crece">BosonCode</span><span className="gris">{t.ajustes.commit(e.boson.commit, e.boson.fecha ?? "?")}</span></div>}
          {e.boson.code_server && <div className="fila"><span className="crece">code-server</span><span className="gris">{e.boson.code_server}{e.boson.vscode ? ` · VS Code ${e.boson.vscode}` : ""}</span></div>}
        </div>
      </section>
    </>
  );
}
