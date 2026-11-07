// Un código QR grande, para que ZeroSpin lo lea con la cámara.
import { useEffect, useState } from "react";
import QRCode from "qrcode";
import type { Textos } from "./textos";
import { Boton } from "./ui";

export function QR({ texto, titulo, nota, t, cerrar }: { texto: string; titulo: string; nota: string; t: Textos; cerrar: () => void }) {
  const [imagen, setImagen] = useState<string | null>(null);
  useEffect(() => {
    QRCode.toDataURL(texto, { width: 360, margin: 1, errorCorrectionLevel: "M", color: { dark: "#1B1C20", light: "#FFFFFF" } })
      .then(setImagen)
      .catch(() => setImagen(null));
  }, [texto]);
  return (
    <div className="velo" role="dialog" aria-modal="true" aria-label={titulo}>
      <div className="dialogo" style={{ alignItems: "center", textAlign: "center" }}>
        <h2 style={{ margin: 0, fontSize: 16 }}>{titulo}</h2>
        {imagen ? <img src={imagen} alt={titulo} style={{ width: 300, height: 300, borderRadius: 8, background: "#fff", padding: 6 }} /> : <div className="vacio">…</div>}
        <span className="nota" style={{ maxWidth: 380 }}>{nota}</span>
        <div className="botones"><Boton primario onClick={cerrar}>{t.tarea.cerrar}</Boton></div>
      </div>
    </div>
  );
}

/// Lo que ZeroSpin necesita para añadir este equipo, en un enlace que la app
/// entiende: la dirección, el nombre y la contraseña.
export function enlaceDeEmparejamiento(url: string, nombre: string, clave: string): string {
  const q = new URLSearchParams({ url, name: nombre, password: clave });
  return `bosoncode://add?${q.toString()}`;
}
