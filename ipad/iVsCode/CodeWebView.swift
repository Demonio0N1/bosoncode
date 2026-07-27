import SwiftUI
import WebKit

/// Contenedor del WebView: fuerza el relayout en cada cambio de tamaño de la
/// ventana, incluidos los que llegan sin pasar por SwiftUI.
final class WebContainerView: UIView {
    weak var webView: WKWebView?
    /// Restricción inferior: se "pellizca" 1pt para forzar a WebKit a recalcular
    /// el viewport cuando la página se queda maquetada más pequeña.
    var bottomConstraint: NSLayoutConstraint?
    private var lastSize: CGSize = .zero
    private var resizeWork: DispatchWorkItem?
    private var watchdog: Timer?

    /// Vigilante: la página puede quedarse con un viewport viejo sin que cambie
    /// el marco (pasa al activar otra ventana de la app). Se compara lo que la
    /// página cree medir con el tamaño real y se corrige solo si difieren.
    func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkViewport()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func checkViewport() {
        guard let webView, window != nil, bounds.height > 100 else { return }
        // Se compara la altura que VS Code está USANDO para maquetar (su
        // workbench) con la real: innerHeight puede ser correcto y aun así
        // tener el editor dibujado corto.
        let expected = bounds.height
        let js = "(document.querySelector('.monaco-workbench')||document.body).getBoundingClientRect().height"
        let webH = webView.bounds.height
        webView.evaluateJavaScript(js) { [weak self] value, _ in
            guard let self else { return }
            let used = (value as? CGFloat) ?? -1
            print("[vp] contenedor=\(Int(expected)) webview=\(Int(webH)) workbench=\(Int(used))")
            if used > 0, abs(used - expected) > 24 { self.forceViewportRefresh() }
        }
    }

    /// Cambiar de ventana es justo cuando el editor se queda corto: se le
    /// fuerza un cambio de tamaño real (no solo un evento) al recuperar o
    /// perder el foco, de modo que las ventanas sean independientes.
    func refreshOnFocusChange() {
        for delay in [0.05, 0.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.forceViewportRefresh()
            }
        }
    }

    private func forceViewportRefresh() {
        guard let webView, let bottom = bottomConstraint else { return }
        bottom.constant = -1
        layoutIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            bottom.constant = 0
            self.layoutIfNeeded()
            webView.evaluateJavaScript("window.dispatchEvent(new Event('resize'));")
        }
    }

    deinit { watchdog?.invalidate() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let webView else { return }
        // marco explícito además de las restricciones: si alguna se rompe, el
        // WebView deja de llenar la ventana y aparece la franja negra
        if webView.frame != bounds { webView.frame = bounds }
        webView.setNeedsLayout()
        webView.layoutIfNeeded()
        guard bounds.size != lastSize, bounds.width > 1, bounds.height > 1 else { return }
        lastSize = bounds.size

        // VS Code maqueta con el tamaño del último evento 'resize'. Si la
        // ventana cambia mientras la página no está activa, ese evento no
        // llega y el editor se queda dibujado a la altura vieja (franja negra
        // debajo). Se le fuerza el evento tras asentar el layout.
        resizeWork?.cancel()
        let work = DispatchWorkItem { [weak webView] in
            webView?.evaluateJavaScript("window.dispatchEvent(new Event('resize'));")
        }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        // segundo aviso por si el primero llegó a mitad de la animación
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak webView] in
            webView?.evaluateJavaScript("window.dispatchEvent(new Event('resize'));")
        }
    }
}

extension CodeWebView {
    /// ¿Está el destino entre los dominios declarados en el Info.plist?
    ///
    /// La comparación imita la de WebKit: coincidencia exacta del host o
    /// subdominio de uno declarado.
    static func isAppBound(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              let declared = Bundle.main.object(forInfoDictionaryKey: "WKAppBoundDomains") as? [String]
        else { return false }
        return declared.contains { entry in
            let domain = entry.lowercased()
            return host == domain || host.hasSuffix("." + domain)
        }
    }
}

struct CodeWebView: UIViewRepresentable {
    let url: URL
    /// Aísla cookies y Service Workers por servidor: los SW de dos sesiones
    /// (p. ej. el PC y una máquina Docker del mismo origen) no pueden chocar.
    var dataStoreID: UUID?
    /// Servidor de esta sesión: necesario para las descargas por arrastre
    var server: Server?
    /// Claro/oscuro/auto: el WebView lo expone como prefers-color-scheme y
    /// VS Code (con window.autoDetectColorScheme) cambia de tema en vivo.
    var interfaceStyle: UIUserInterfaceStyle = .unspecified
    var password: String?
    var onOpenSettings: () -> Void
    var onLoadError: (String) -> Void
    var onPasswordEntered: ((String) -> Void)? = nil
    var onDownload: ((String) -> Void)? = nil
    var onFileCopy: (() -> Void)? = nil
    var onFilePaste: (() -> Void)? = nil
    var onTerminalToggle: (() -> Void)? = nil
    /// true mientras la sesión sigue en la página de login (oculta); false al
    /// llegar al workbench — la app usa esto para su pantalla "Conectando…"
    var onLoading: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenSettings: onOpenSettings, onLoadError: onLoadError,
                    password: password, onDownload: onDownload, onLoading: onLoading)
    }

    /// Script de auto-login con guardas: no reenvía si hay error visible
    /// (contraseña mala) ni más de una vez cada 5s (rate-limit de code-server).
    static func autologinScript(password: String) -> String {
        let escaped = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (() => {
          if (!location.pathname.includes("/login")) return;
          const err = document.querySelector('.error');
          if (err && err.textContent.trim()) return;
          const last = +(sessionStorage.getItem('ivscode_al_ts') || 0);
          if (Date.now() - last < 5000) return;
          const input = document.querySelector('input[type="password"]');
          const form = input && input.closest('form');
          if (!input || !form) return;
          sessionStorage.setItem('ivscode_al_ts', String(Date.now()));
          input.value = "\(escaped)";
          form.submit();
        })();
        """
    }

    /// VS Code entrega al arrastrar solo la RUTA como texto (por eso salía un
    /// .txt). Este script añade el tipo `DownloadURL`, que WebKit convierte en
    /// una promesa de archivo: al soltar en Archivos llega el archivo real.
    static func dragOutScript(base: String, machine: String, token: String) -> String {
        """
        (() => {
          if (window.__ivscodeDrag) return;
          window.__ivscodeDrag = true;
          const BASE = "\(base)", MACHINE = "\(machine)", TOKEN = "\(token)";
          document.addEventListener('dragstart', (e) => {
            try {
              const dt = e.dataTransfer;
              if (!dt) return;
              let path = "";
              const codeFiles = dt.getData('CodeFiles');
              if (codeFiles) {
                const arr = JSON.parse(codeFiles);
                if (Array.isArray(arr) && arr.length) path = arr[0];
              }
              if (!path) {
                const uris = dt.getData('text/uri-list') || dt.getData('text/plain') || "";
                path = uris.split('\\n')[0].trim().replace(/^file:\\/\\//, '');
              }
              if (!path.startsWith('/')) return;
              const name = path.split('/').filter(Boolean).pop() || 'archivo';
              const url = BASE + '/download?machine=' + encodeURIComponent(MACHINE) +
                          '&path=' + encodeURIComponent(path) +
                          '&token=' + encodeURIComponent(TOKEN);
              dt.setData('DownloadURL', 'application/octet-stream:' + name + ':' + url);
            } catch (err) {}
          }, true);
        })();
        """
    }

    func makeUIView(context: Context) -> WebContainerView {
        let config = WKWebViewConfiguration()
        if let dataStoreID {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        } else {
            config.websiteDataStore = .default()      // cookies y sesión persistentes
        }
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        // Service Workers —que los notebooks de VS Code necesitan— solo
        // funcionan con esta bandera, y esta bandera solo permite navegar a los
        // dominios de WKAppBoundDomains. Activarla siempre significaba que un
        // equipo cuyo dominio no esté declarado NO CARGABA EN ABSOLUTO.
        //
        // Y no hay comodín posible: WebKit compara el dominio registrable, y
        // como `ts.net` está en la Public Suffix List, cada tailnet
        // (`loquesea.ts.net`) cuenta como dominio propio. Declarar `ts.net` no
        // cubre ninguno — comprobado en dispositivo.
        //
        // Así que se decide por destino: en un dominio declarado se activa y
        // los notebooks funcionan; en cualquier otro se deja apagada y al menos
        // el editor abre.
        config.limitsNavigationsToAppBoundDomains = Self.isAppBound(url)

        // El teclado de OTRA ventana encogía el "visual viewport" de esta
        // página: VS Code maquetaba 79pt más corto y dejaba una franja negra.
        // Se ancla el viewport visual al tamaño real de la ventana (el zoom
        // por pellizco está desactivado, así que no se pierde nada).
        let pinViewport = """
        (() => {
          const vv = window.visualViewport;
          if (!vv) return;
          const fix = (prop, get) => {
            try { Object.defineProperty(vv, prop, { get, configurable: true }); } catch (e) {}
          };
          fix('height', () => window.innerHeight);
          fix('width',  () => window.innerWidth);
          fix('offsetTop',  () => 0);
          fix('offsetLeft', () => 0);
          fix('pageTop',  () => window.scrollY);
          fix('pageLeft', () => window.scrollX);
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: pinViewport,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: false)
        )

        // Bridge de portapapeles: la Clipboard API del WebView pasa por UIPasteboard
        config.userContentController.addScriptMessageHandler(
            ClipboardBridge(), contentWorld: .page, name: "clipboard"
        )
        config.userContentController.addUserScript(
            WKUserScript(source: ClipboardBridge.script,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: false)
        )

        // Captura de contraseña: si el usuario la teclea a mano en /login, se
        // envía al lado nativo para guardarla en el Llavero. form.submit() del
        // auto-login NO dispara el evento 'submit', así que no hay bucle.
        if let onPasswordEntered {
            config.userContentController.add(AuthBridge(onPassword: onPasswordEntered), name: "auth")
            let capture = """
            (() => {
              if (!location.pathname.includes("/login")) return;
              const input = document.querySelector('input[type="password"]');
              const form = input && input.closest('form');
              if (!input || !form) return;
              form.addEventListener('submit', () => {
                try {
                  window.webkit.messageHandlers.auth.postMessage({ op: "password", value: input.value });
                } catch (e) {}
              });
            })();
            """
            config.userContentController.addUserScript(
                WKUserScript(source: capture,
                             injectionTime: .atDocumentEnd,
                             forMainFrameOnly: true)
            )
        }

        // Auto-login: rellena la contraseña en la página /login de code-server.
        if let password, !password.isEmpty {
            config.userContentController.addUserScript(
                WKUserScript(source: Self.autologinScript(password: password),
                             injectionTime: .atDocumentEnd,
                             forMainFrameOnly: true)
            )
            // la página de login nunca se ve: queda invisible mientras el
            // auto-login trabaja (la app muestra su propio "Conectando…")
            let hideLogin = """
            (() => {
              if (location.pathname.includes("/login")) {
                document.documentElement.style.visibility = "hidden";
                setTimeout(() => {
                  document.documentElement.style.visibility = "";
                }, 9000);   // si el auto-login fallara, la página reaparece
              }
            })();
            """
            config.userContentController.addUserScript(
                WKUserScript(source: hideLogin,
                             injectionTime: .atDocumentStart,
                             forMainFrameOnly: true)
            )
        }

        let webView = KeyboardWebView(frame: .zero, configuration: config)
        context.coordinator.serverForDragOut = server
        webView.navigationDelegate = context.coordinator
        webView.onFileCopy = onFileCopy
        webView.onFilePaste = onFilePaste
        webView.onTerminalToggle = onTerminalToggle
        // El scroll nativo debe estar ACTIVO: es el canal por el que el trackpad
        // entrega los eventos de rueda al editor. VS Code usa overflow:hidden,
        // así que la página en sí nunca se desplaza ni rebota.
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        // sin zoom de página por pellizco (el zoom del editor es cosa de VS Code)
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bouncesZoom = false
        webView.allowsBackForwardNavigationGestures = false   // un swipe no debe "navegar atrás"
        webView.isFindInteractionEnabled = false              // ⌘F debe llegar a VS Code, no a iOS
        webView.isOpaque = false
        webView.backgroundColor = .black
        #if DEBUG
        webView.isInspectable = true                          // debug desde Safari en el Mac
        #endif

        // Doble toque con tres dedos → ajustes nativos
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.openSettings))
        tap.numberOfTouchesRequired = 3
        tap.numberOfTapsRequired = 2
        webView.addGestureRecognizer(tap)

        webView.overrideUserInterfaceStyle = interfaceStyle
        webView.load(URLRequest(url: url))

        // El WebView va anclado por restricciones a un contenedor: cuando
        // iPadOS redimensiona la ventana (p. ej. al abrir la ventana-terminal),
        // el marco que da SwiftUI puede llegar tarde y quedaba una franja negra.
        let container = WebContainerView()
        container.backgroundColor = .black
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        let bottom = webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            bottom,
        ])
        container.bottomConstraint = bottom
        container.webView = webView
        container.startWatchdog()
        // al volver a primer plano (p. ej. tras abrir la ventana-terminal) la
        // página también debe recalcular su tamaño
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak container] _ in
                container?.refreshOnFocusChange()
            }
        }
        return container
    }

    func updateUIView(_ uiView: WebContainerView, context: Context) {
        guard let webView = uiView.webView as? KeyboardWebView else { return }
        webView.overrideUserInterfaceStyle = interfaceStyle
        // los callbacks capturan el servidor actual: sin refrescarlos, los
        // atajos podían apuntar a una sesión anterior
        webView.onFileCopy = onFileCopy
        webView.onFilePaste = onFilePaste
        webView.onTerminalToggle = onTerminalToggle
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        let onOpenSettings: () -> Void
        let onLoadError: (String) -> Void
        let password: String?
        let onDownload: ((String) -> Void)?
        let onLoading: ((Bool) -> Void)?
        /// Servidor de esta sesión (para construir las URLs de descarga)
        var serverForDragOut: Server?
        private var lastDownloadName = ""

        init(onOpenSettings: @escaping () -> Void,
             onLoadError: @escaping (String) -> Void,
             password: String?,
             onDownload: ((String) -> Void)?,
             onLoading: ((Bool) -> Void)?) {
            self.onOpenSettings = onOpenSettings
            self.onLoadError = onLoadError
            self.password = password
            self.onDownload = onDownload
            self.onLoading = onLoading
        }

        // ---- descargas: "Download..." de VS Code → Archivos › iVsCode › Descargas
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Descargas", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var url = dir.appendingPathComponent(suggestedFilename)
            var counter = 1
            while FileManager.default.fileExists(atPath: url.path) {
                url = dir.appendingPathComponent("\(counter)-\(suggestedFilename)")
                counter += 1
            }
            lastDownloadName = url.lastPathComponent
            completionHandler(url)
        }

        func downloadDidFinish(_ download: WKDownload) {
            onDownload?(lastDownloadName)
        }

        func download(_ download: WKDownload, didFailWithError error: Error,
                      resumeData: Data?) {
            onLoadError("Descarga fallida: \(error.localizedDescription)")
        }

        @objc func openSettings() { onOpenSettings() }

        /// Pide el token de descarga al gestor e instala el interceptor de
        /// arrastre para que salga el archivo y no un .txt con la ruta.
        private func installDragOut(in webView: WKWebView) {
            guard let server = serverForDragOut,
                  let mgr = server.managerURL,
                  let pw = Keychain.password(for: server.id) else { return }
            Task {
                do {
                    let client = ManagerClient(baseURL: mgr, password: pw)
                    let token = try await client.downloadToken()
                    let js = CodeWebView.dragOutScript(
                        base: mgr.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                        machine: server.dockerMachineName,
                        token: token)
                    await MainActor.run { webView.evaluateJavaScript(js) }
                } catch { /* sin token: se mantiene el comportamiento normal */ }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let onLoginPage = webView.url?.path.contains("/login") == true
            onLoading?(onLoginPage)
            if !onLoginPage { installDragOut(in: webView) }
            // refuerzo del auto-login: si seguimos en /login con clave conocida,
            // reintenta (el user script pudo no ejecutarse en cargas raras)
            guard let password, !password.isEmpty, onLoginPage else { return }
            let js = CodeWebView.autologinScript(password: password)
            webView.evaluateJavaScript(js)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak webView] in
                guard let webView, webView.url?.path.contains("/login") == true else { return }
                webView.evaluateJavaScript(js)
            }
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            onLoadError(error.localizedDescription)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            let nsError = error as NSError
            // -999 = carga cancelada por otra navegación; no es un fallo real
            if nsError.code != NSURLErrorCancelled {
                onLoadError(error.localizedDescription)
            }
        }
    }
}

/// Recibe la contraseña tecleada a mano en la página de login.
final class AuthBridge: NSObject, WKScriptMessageHandler {
    let onPassword: (String) -> Void

    init(onPassword: @escaping (String) -> Void) {
        self.onPassword = onPassword
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              body["op"] as? String == "password",
              let value = body["value"] as? String, !value.isEmpty else { return }
        onPassword(value)
    }
}

/// WKWebView que arrebata al sistema los atajos que iPadOS captura antes de
/// entregarlos a la página (⌘W, ⌘T, ⌘N…) y los reinyecta en el DOM para que
/// los keybindings de VS Code los reciban.
final class KeyboardWebView: WKWebView {
    /// Portapapeles de archivos entre sesiones (⌃⌥C / ⌃⌥V)
    var onFileCopy: (() -> Void)?
    var onFilePaste: (() -> Void)?
    /// Terminal flotante (⌃⌥T)
    var onTerminalToggle: (() -> Void)?

    private static let stolenShortcuts: [(String, UIKeyModifierFlags)] = [
        ("w", .command), ("t", .command), ("n", .command),
        ("w", [.command, .shift]), ("t", [.command, .shift]),
        ("n", [.command, .shift]),
        ("[", .command), ("]", .command),
    ]

    override var keyCommands: [UIKeyCommand]? {
        var cmds = Self.stolenShortcuts.map { input, mods in
            let cmd = UIKeyCommand(input: input, modifierFlags: mods,
                                   action: #selector(forwardKey(_:)))
            cmd.wantsPriorityOverSystemBehavior = true
            return cmd
        }
        let copy = UIKeyCommand(title: "Copiar archivo entre sesiones",
                                action: #selector(fileCopy),
                                input: "c", modifierFlags: [.control, .alternate])
        copy.wantsPriorityOverSystemBehavior = true
        let paste = UIKeyCommand(title: "Pegar archivo entre sesiones",
                                 action: #selector(filePaste),
                                 input: "v", modifierFlags: [.control, .alternate])
        paste.wantsPriorityOverSystemBehavior = true
        let term = UIKeyCommand(title: "Terminal flotante",
                                action: #selector(terminalToggle),
                                input: "t", modifierFlags: [.control, .alternate])
        term.wantsPriorityOverSystemBehavior = true
        cmds.append(contentsOf: [copy, paste, term])
        return cmds
    }

    @objc private func terminalToggle() { onTerminalToggle?() }

    /// ⌃⌥C: dispara el "Copy Path" de VS Code (⌥⌘C) sobre el archivo
    /// seleccionado y avisa a la app cuando la ruta ya está en el portapapeles.
    /// Monaco resuelve atajos leyendo e.keyCode (legacy), que los KeyboardEvent
    /// sintéticos traen a 0 — hay que forzarlo con defineProperty.
    @objc private func fileCopy() {
        evaluateJavaScript(Self.syntheticKeyJS(key: "c", meta: true, alt: true))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.onFileCopy?()
        }
    }

    /// ⌃⌥V: primero captura la ruta del elemento seleccionado en ESTA sesión
    /// (para pegar en esa carpeta) y luego avisa a la app.
    @objc private func filePaste() {
        evaluateJavaScript(Self.syntheticKeyJS(key: "c", meta: true, alt: true))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.onFilePaste?()
        }
    }

    static func syntheticKeyJS(key: String, meta: Bool = false, shift: Bool = false,
                               alt: Bool = false, ctrl: Bool = false) -> String {
        """
        (() => {
          const k = "\(key)";
          const kc = ({"[":219, "]":221}[k]) || k.toUpperCase().charCodeAt(0);
          const e = new KeyboardEvent('keydown', {
            key: k, code: 'Key' + k.toUpperCase(),
            metaKey: \(meta), shiftKey: \(shift), altKey: \(alt), ctrlKey: \(ctrl),
            bubbles: true, cancelable: true
          });
          Object.defineProperty(e, 'keyCode', { get: () => kc });
          Object.defineProperty(e, 'which', { get: () => kc });
          (document.activeElement || document.body).dispatchEvent(e);
        })();
        """
    }

    @objc private func forwardKey(_ sender: UIKeyCommand) {
        guard let input = sender.input else { return }
        evaluateJavaScript(Self.syntheticKeyJS(
            key: input,
            meta: sender.modifierFlags.contains(.command),
            shift: sender.modifierFlags.contains(.shift),
            alt: sender.modifierFlags.contains(.alternate),
            ctrl: sender.modifierFlags.contains(.control)
        ))
    }
}
