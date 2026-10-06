// Extensión mínima: añade "Compartir carpeta…" (carpetas) y "Compartir enlace
// de descarga…" (archivos) al menú contextual del explorador. Delega todo el
// trabajo en el CLI carpeta-share; aquí solo elegimos el modo (web, solo
// descarga, con llave / sin llave) y mostramos el enlace.
import * as vscode from 'vscode';
import { execFile } from 'child_process';

const CLI = '/usr/local/bin/carpeta-share';

interface Resultado {
  modo: 'ssh' | 'web' | 'descarga';
  tipo?: 'archivo' | 'carpeta';
  directo?: string;
  expira?: number | null; // segundos desde 1970
  max?: number | null;
  omitidos?: number;
  invitado: string | null;
  usuario: string | null;
  host: string;
  enlace: string;
  contrasena: string | null;
  paquete: string | null;
}

function cli(args: string[], timeoutMs = 180000): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(CLI, args, { timeout: timeoutMs, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        reject(new Error(stderr.trim() || err.message));
      } else {
        resolve(stdout);
      }
    });
  });
}

// Condiciones opcionales de un enlace de descarga. Devuelve los argumentos
// para el CLI, o undefined si el usuario canceló.
async function opcionesDescarga(): Promise<string[] | undefined> {
  type Opcion = vscode.QuickPickItem & { args: string[] };
  const opciones: Opcion[] = [
    { label: 'Caduca en 24 horas', args: ['--expira', '24h'] },
    { label: 'Caduca en 7 días', args: ['--expira', '7d'] },
    {
      label: 'Un solo uso',
      description: 'Deja de funcionar tras la primera descarga completa',
      args: ['--una-vez'],
    },
    {
      label: 'Con contraseña',
      description: 'Se genera una; envíala por un canal distinto al del enlace',
      args: ['--con-contrasena'],
    },
  ];
  const marcadas = await vscode.window.showQuickPick(opciones, {
    canPickMany: true,
    placeHolder: 'Condiciones del enlace (Enter sin marcar nada = sin caducidad ni límite)',
  });
  if (!marcadas) {
    return undefined;
  }
  // Si se marcan las dos caducidades gana la más corta (va antes en la lista).
  const args: string[] = [];
  let conCaducidad = false;
  for (const o of opciones.filter((x) => marcadas.includes(x))) {
    if (o.args[0] === '--expira') {
      if (conCaducidad) {
        continue;
      }
      conCaducidad = true;
    }
    args.push(...o.args);
  }
  return args;
}

// Ejecuta 'carpeta-share compartir <ruta> …' y muestra el enlace resultante.
async function compartir(ruta: string, args: string[], titulo: string) {
  try {
    const salida = await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: titulo },
      () => cli(['compartir', ruta, ...args, '--si', '--json'])
    );
    // La escalada gráfica (osascript) puede devolver la salida con \r.
    const linea = salida
      .replace(/\r/g, '\n')
      .split('\n')
      .map((s) => s.trim())
      .filter((s) => s.startsWith('{'))
      .pop();
    if (!linea) {
      throw new Error(`respuesta inesperada del CLI: ${salida.slice(0, 300)}`);
    }
    const r = JSON.parse(linea) as Resultado;

    await vscode.env.clipboard.writeText(r.enlace);
    const botones = ['Copiar enlace'];
    if (r.contrasena) {
      botones.push('Copiar contraseña');
    }
    if (r.paquete) {
      botones.push('Abrir paquete');
    }
    let mensaje: string;
    if (r.modo === 'web') {
      mensaje = r.contrasena
        ? `Enlace web copiado: ${r.enlace} — Contraseña: ${r.contrasena} (envíala por otro canal). El invitado no instala nada.`
        : `Enlace web SIN contraseña copiado: ${r.enlace} — cualquiera con la URL puede entrar.`;
    } else if (r.modo === 'descarga') {
      const que = r.tipo === 'carpeta' ? 'esta carpeta (como .zip)' : 'este archivo';
      const partes = [
        `Enlace de solo descarga copiado: ${r.enlace} — quien lo abra solo puede bajar ${que}; no entra a tu equipo.`,
      ];
      if (r.expira) {
        partes.push(`Caduca el ${new Date(r.expira * 1000).toLocaleString()}.`);
      }
      if (r.max) {
        partes.push(r.max === 1 ? 'Un solo uso.' : `Máximo ${r.max} descargas.`);
      }
      if (r.contrasena) {
        partes.push(`Contraseña: ${r.contrasena} (envíala por otro canal).`);
      }
      if (r.omitidos) {
        partes.push(`Se dejaron fuera ${r.omitidos} elemento(s) oculto(s) (.git, .env…).`);
      }
      mensaje = partes.join(' ');
    } else if (r.paquete) {
      mensaje = 'Enlace copiado. Envía a tu invitado el paquete de acceso completo (llave + instrucciones).';
    } else {
      mensaje = `Enlace para "${r.invitado}" copiado al portapapeles.`;
    }
    const boton = await vscode.window.showInformationMessage(mensaje, ...botones);
    if (boton === 'Copiar enlace') {
      await vscode.env.clipboard.writeText(r.enlace);
      vscode.window.setStatusBarMessage('Enlace copiado al portapapeles', 4000);
    }
    if (boton === 'Copiar contraseña' && r.contrasena) {
      await vscode.env.clipboard.writeText(r.contrasena);
      vscode.window.setStatusBarMessage('Contraseña copiada al portapapeles', 4000);
    }
    if (boton === 'Abrir paquete' && r.paquete) {
      await vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(r.paquete));
    }
  } catch (e) {
    vscode.window.showErrorMessage(`No se pudo compartir: ${(e as Error).message}`);
  }
}

export function activate(context: vscode.ExtensionContext) {
  context.subscriptions.push(
    vscode.commands.registerCommand('carpetaShare.compartir', async (uri?: vscode.Uri) => {
      // Si se invoca desde la paleta (sin recurso), pedimos la carpeta.
      let carpeta = uri?.fsPath;
      if (!carpeta) {
        const sel = await vscode.window.showOpenDialog({
          canSelectFiles: false,
          canSelectFolders: true,
          canSelectMany: false,
          openLabel: 'Compartir esta carpeta',
        });
        if (!sel || sel.length === 0) {
          return;
        }
        carpeta = sel[0].fsPath;
      }

      let invitados: string[] = [];
      try {
        const salida = await cli(['listar-invitados']);
        invitados = salida.split('\n').map((s) => s.trim()).filter(Boolean);
      } catch (e) {
        vscode.window.showErrorMessage(
          `No encuentro el CLI carpeta-share (${(e as Error).message}). Ejecuta setup.sh primero.`
        );
        return;
      }

      // El enlace siempre ofrece las opciones: web con/sin contraseña
      // (cero instalación), solo descarga, o VS Code de escritorio con/sin
      // llave.
      type Item = vscode.QuickPickItem & { args: string[] };
      const items: Item[] = [
        {
          label: '$(globe) Enlace web CON contraseña',
          description: 'El invitado no instala nada: abre la URL en su navegador',
          args: ['--web', '--con-contrasena'],
        },
        {
          label: '$(globe) Enlace web SIN contraseña',
          description: 'URL abierta: cualquiera con el enlace entra — solo para cosas no sensibles',
          args: ['--web', '--sin-contrasena'],
        },
        {
          label: '$(cloud-download) Enlace de SOLO DESCARGA (.zip)',
          description: 'Quien lo abra solo puede bajar la carpeta: no entra a tu equipo',
          args: ['--descarga'],
        },
        ...invitados.map((n) => ({
          label: `$(key) ${n}`,
          description: 'VS Code escritorio — usa la llave SSH que ya te dio',
          args: ['--con', n],
        })),
        {
          label: '$(add) Nuevo acceso sin llave (VS Code escritorio)',
          description: 'Genera la llave por ti y crea un paquete para enviárselo al invitado',
          args: ['--sin-clave'],
        },
      ];
      const eleccion = await vscode.window.showQuickPick(items, {
        placeHolder: `¿Con quién compartir "${carpeta}"?`,
      });
      if (!eleccion) {
        return;
      }

      let args = eleccion.args;
      if (args[0] === '--descarga') {
        const extra = await opcionesDescarga();
        if (!extra) {
          return;
        }
        args = [...args, ...extra];
      }
      await compartir(carpeta, args, 'Compartiendo carpeta…');
    }),

    // Un archivo suelto solo admite el modo de descarga: sin menú intermedio.
    vscode.commands.registerCommand('carpetaShare.descarga', async (uri?: vscode.Uri) => {
      let ruta = uri?.fsPath;
      if (!ruta) {
        const sel = await vscode.window.showOpenDialog({
          canSelectFiles: true,
          canSelectFolders: false,
          canSelectMany: false,
          openLabel: 'Crear enlace de descarga',
        });
        if (!sel || sel.length === 0) {
          return;
        }
        ruta = sel[0].fsPath;
      }
      const extra = await opcionesDescarga();
      if (!extra) {
        return;
      }
      await compartir(ruta, ['--descarga', ...extra], 'Creando enlace de descarga…');
    })
  );
}

export function deactivate() {}
