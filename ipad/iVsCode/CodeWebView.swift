import SwiftUI
import WebKit

struct CodeWebView: UIViewRepresentable {
    let url: URL
    /// Aísla cookies y Service Workers por servidor: los SW de dos sesiones
    /// (p. ej. el PC y una máquina Docker del mismo origen) no pueden chocar.
    var dataStoreID: UUID?
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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        if let dataStoreID {
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: dataStoreID)
        } else {
            config.websiteDataStore = .default()      // cookies y sesión persistentes
        }
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        // Habilita Service Workers (los notebooks de VS Code los necesitan):
        // solo funcionan en dominios declarados en WKAppBoundDomains (Info.plist)
        config.limitsNavigationsToAppBoundDomains = true

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
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.overrideUserInterfaceStyle = interfaceStyle
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        let onOpenSettings: () -> Void
        let onLoadError: (String) -> Void
        let password: String?
        let onDownload: ((String) -> Void)?
        let onLoading: ((Bool) -> Void)?
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let onLoginPage = webView.url?.path.contains("/login") == true
            onLoading?(onLoginPage)
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
