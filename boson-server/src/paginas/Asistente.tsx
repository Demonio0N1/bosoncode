import type { Comunes } from "../App";
import { Boton, Etiqueta, Punto } from "../ui";

export function Asistente({ e, t, lanzar }: Comunes) {
  const ia = e.ia;
  const continueInstalado = ia.extensiones.some((x) => x.startsWith("continue.continue@"));
  const instalado = e.servidor.estado !== "sin_instalar";
  return (
    <>
      <header className="cabecera">
        <div className="titulos">
          <h1>{t.nav.ia}</h1>
          <span className="sub">{t.ia.sub}</span>
        </div>
      </header>
      <section className="tarjeta">
        <h2>{t.ia.integrado}</h2>
        <span className="fila"><Punto nivel={ia.copilot_integrado ? "ok" : "aviso"} />{ia.copilot_integrado ? t.ia.integradoSi(ia.copilot_integrado, e.boson.vscode) : t.ia.integradoNo}</span>
        <span className="nota">{t.ia.integradoNota}</span>
      </section>
      <section className="tarjeta">
        <h2>{t.ia.continue}</h2>
        <span className="fila"><Punto nivel={continueInstalado ? "ok" : "gris"} />{continueInstalado ? t.ia.instaladoContinue : t.ia.continueTexto}</span>
        {!continueInstalado && (
          <div className="botones"><Boton pequeno disabled={!instalado} onClick={() => lanzar({ titulo: t.ia.instalando, args: ["--ai", "continue", "--no-csm", "--no-linkspace"] })}>{t.ia.instalarContinue}</Boton></div>
        )}
      </section>
      <section className="tarjeta">
        <Etiqueta>{t.ia.extensiones}</Etiqueta>
        <div className="filas">
          {ia.extensiones.length === 0 && <span className="nota">{t.ia.sinExtensiones}</span>}
          {ia.extensiones.map((x) => {
            const [id, version] = x.split("@");
            return (
              <div className="fila" key={x}>
                <Punto nivel="ok" />
                <span className="crece mono" style={{ color: "var(--texto)" }}>{id}</span>
                <span className="gris">{version}</span>
              </div>
            );
          })}
        </div>
        <span className="nota">{t.ia.nota}</span>
      </section>
    </>
  );
}
