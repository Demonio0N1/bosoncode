import { abrir, type Estado } from "../estado";
import type { Textos } from "../textos";
import type { Seccion } from "../App";
import { Boton, BotonCopiar, Etiqueta } from "../ui";

export function Registro({ e, t }: { e: Estado; t: Textos; ir: (s: Seccion) => void; refrescar: () => void }) {
  const mac = e.equipo.so === "macos";
  const registro = e.servidor.registro;
  return (
    <>
      <header className="cabecera">
        <div className="titulos">
          <h1>{t.nav.registro}</h1>
          <span className="sub">{t.registro.sub}</span>
        </div>
      </header>
      <section className="tarjeta">
        <Etiqueta>{t.registro.donde}</Etiqueta>
        {!mac && <span className="nota">{t.registro.linux}</span>}
        <span className="mono seleccionable">{registro ?? "—"}</span>
        <div className="botones">
          {registro && mac && <Boton primario onClick={() => abrir(registro)}>{t.registro.abrir}</Boton>}
          {registro && !mac && <BotonCopiar primario texto={registro + " -f"} etiqueta={t.registro.copiarComando} t={t} />}
        </div>
      </section>
    </>
  );
}
