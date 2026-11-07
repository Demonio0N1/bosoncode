import type { Estado } from "../estado";
import type { Textos } from "../textos";
import type { Seccion } from "../App";
import { Comprobacion } from "../ui";

export function Simulador({ e, t }: { e: Estado; t: Textos; ir: (s: Seccion) => void; refrescar: () => void }) {
  const s = e.simulador;
  const mac = e.equipo.so === "macos";
  return (
    <>
      <header className="cabecera">
        <div className="titulos">
          <h1>{t.nav.simulador}</h1>
          <span className="sub">{t.simulador.sub}</span>
        </div>
      </header>
      <section className="tarjeta lista">
        <Comprobacion nivel={!mac ? "gris" : s.xcode ? "ok" : "gris"} titulo={t.simulador.xcode} texto={!mac ? t.simulador.xcodeLinux : s.xcode ? t.simulador.xcodeSi : t.simulador.xcodeNo} />
        {mac && s.xcode && <Comprobacion nivel={s.idb ? "ok" : "aviso"} titulo={t.simulador.idb} texto={s.idb ? t.simulador.idbSi : t.simulador.idbNo} />}
        <Comprobacion nivel={s.adb ? "ok" : "gris"} titulo={t.simulador.adb} texto={s.adb ? t.simulador.adbSi(s.adb) : t.simulador.adbNo} />
        <Comprobacion nivel={mac ? "gris" : s.kvm ? "ok" : "aviso"} titulo={t.simulador.kvm} texto={mac ? t.simulador.kvmMac : s.kvm ? t.simulador.kvmSi : t.simulador.kvmNo} />
        <Comprobacion nivel={s.docker_version ? "ok" : s.docker ? "aviso" : "gris"} titulo={t.simulador.docker} texto={s.docker_version ? t.simulador.dockerSi(s.docker_version) : s.docker ? t.simulador.dockerParado : t.simulador.dockerNo} />
      </section>
    </>
  );
}
