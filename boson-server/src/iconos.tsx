// Iconos de la barra lateral: trazo de 1,6 px, 16 px, el color del texto.
const base = { width: 16, height: 16, viewBox: "0 0 16 16", fill: "none", stroke: "currentColor", strokeWidth: 1.6, strokeLinecap: "round" as const, strokeLinejoin: "round" as const, "aria-hidden": true };

export const Casa = () => (<svg {...base}><path d="M2.5 8.2 8 3.5l5.5 4.7V13h-11z" /></svg>);
export const Puntos = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
    {[3, 8, 13].flatMap((y) => [3, 8, 13].map((x) => <circle key={`${x}${y}`} cx={x} cy={y} r="1.6" />))}
  </svg>
);
export const Llave = () => (<svg {...base}><circle cx="5.5" cy="10.5" r="3" /><path d="M8 8l6-6M11 5l2 2" /></svg>);
export const Terminal = () => (<svg {...base}><path d="M3 4l4 4-4 4M8.5 12H13" /></svg>);
export const Chispa = () => (<svg {...base}><path d="M8 2l1.4 3.6L13 7l-3.6 1.4L8 12 6.6 8.4 3 7l3.6-1.4z" /></svg>);
export const Movil = () => (<svg {...base}><rect x="4.5" y="1.5" width="7" height="13" rx="1.6" /><path d="M7 12.5h2" /></svg>);
export const Lineas = () => (<svg {...base}><path d="M3 4h10M3 8h10M3 12h6" /></svg>);
export const Deslizadores = () => (
  <svg {...base}><path d="M2 4.5h12M2 11.5h12" /><circle cx="6" cy="4.5" r="1.8" fill="var(--lateral)" /><circle cx="10" cy="11.5" r="1.8" fill="var(--lateral)" /></svg>
);
export const Ojo = ({ tachado }: { tachado?: boolean }) => (
  <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
    <path d="M1.5 9s2.8-5 7.5-5 7.5 5 7.5 5-2.8 5-7.5 5-7.5-5-7.5-5z" />
    <circle cx="9" cy="9" r="2.4" />
    {tachado && <path d="M3 15L15 3" strokeLinecap="round" />}
  </svg>
);
