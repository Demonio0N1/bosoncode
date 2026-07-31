import UIKit
import SwiftTerm

/// Barra de teclas colapsada en un solo botón: en reposo ocupa una esquina y
/// al tocarla despliega las teclas que un terminal necesita y el iPad no tiene
/// (esc, ctrl, tab, flechas, funciones…). Evita tapar la última línea.
final class CollapsibleAccessory: UIInputView {
    private weak var terminal: TerminalView?
    private let toggle = UIButton(type: .system)
    private let scroller = UIScrollView()
    private let stack = UIStackView()
    private var expanded = false

    /// Alto en reposo: lo justo para el botón, sin comerse el terminal.
    static let collapsedHeight: CGFloat = 38
    static let expandedHeight: CGFloat = 44

    init(terminal: TerminalView) {
        self.terminal = terminal
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: Self.collapsedHeight),
                   inputViewStyle: .keyboard)
        translatesAutoresizingMaskIntoConstraints = false
        buildToggle()
        buildKeys()
        applyState(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("no soportado") }

    private func buildToggle() {
        var config = UIButton.Configuration.gray()
        config.image = UIImage(systemName: "keyboard.chevron.compact.up")
        config.cornerStyle = .medium
        toggle.configuration = config
        toggle.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggle)
        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.widthAnchor.constraint(equalToConstant: 46),
            toggle.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func buildKeys() {
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroller.showsHorizontalScrollIndicator = false
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(stack)
        addSubview(scroller)
        NSLayoutConstraint.activate([
            scroller.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 8),
            scroller.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroller.centerYAnchor.constraint(equalTo: centerYAnchor),
            scroller.heightAnchor.constraint(equalToConstant: 32),
            stack.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: scroller.centerYAnchor),
            stack.heightAnchor.constraint(equalTo: scroller.heightAnchor),
        ])

        for key in Key.all {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.gray()
            config.title = key.title
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
            button.configuration = config
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            button.tag = key.rawValue
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    @objc private func toggleTapped() {
        expanded.toggle()
        UIView.animate(withDuration: 0.2) { self.applyState(animated: true) }
    }

    private func applyState(animated: Bool) {
        scroller.alpha = expanded ? 1 : 0
        scroller.isUserInteractionEnabled = expanded
        toggle.configuration?.image = UIImage(
            systemName: expanded ? "keyboard.chevron.compact.down" : "keyboard.chevron.compact.up")
        var f = frame
        f.size.height = expanded ? Self.expandedHeight : Self.collapsedHeight
        frame = f
        terminal?.reloadInputViews()
    }

    @objc private func keyTapped(_ sender: UIButton) {
        guard let key = Key(rawValue: sender.tag), let terminal else { return }
        terminal.send(txt: key.sequence)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Teclas ausentes en el Magic Keyboard o incómodas en el iPad.
    private enum Key: Int, CaseIterable {
        case esc, tab, ctrlC, ctrlD, ctrlZ, ctrlL, ctrlR
        case left, down, up, right, home, end, pageUp, pageDown
        case f1, f2, f3, f4

        static var all: [Key] { allCases }

        var title: String {
            switch self {
            case .esc: return "esc"
            case .tab: return "⇥"
            case .ctrlC: return "^C"
            case .ctrlD: return "^D"
            case .ctrlZ: return "^Z"
            case .ctrlL: return "^L"
            case .ctrlR: return "^R"
            case .left: return "←"
            case .down: return "↓"
            case .up: return "↑"
            case .right: return "→"
            case .home: return "inicio"
            case .end: return "fin"
            case .pageUp: return "⇞"
            case .pageDown: return "⇟"
            case .f1: return "F1"
            case .f2: return "F2"
            case .f3: return "F3"
            case .f4: return "F4"
            }
        }

        var sequence: String {
            switch self {
            case .esc: return "\u{1b}"
            case .tab: return "\t"
            case .ctrlC: return "\u{03}"
            case .ctrlD: return "\u{04}"
            case .ctrlZ: return "\u{1a}"
            case .ctrlL: return "\u{0c}"
            case .ctrlR: return "\u{12}"
            case .left: return "\u{1b}[D"
            case .down: return "\u{1b}[B"
            case .up: return "\u{1b}[A"
            case .right: return "\u{1b}[C"
            case .home: return "\u{1b}[H"
            case .end: return "\u{1b}[F"
            case .pageUp: return "\u{1b}[5~"
            case .pageDown: return "\u{1b}[6~"
            case .f1: return "\u{1b}OP"
            case .f2: return "\u{1b}OQ"
            case .f3: return "\u{1b}OR"
            case .f4: return "\u{1b}OS"
            }
        }
    }
}

/// TerminalView con los atajos y gestos de Terminal.app de macOS.
final class MacTerminalView: TerminalView {
    /// ⌘+ / ⌘− / ⌘0 (y sus equivalentes con Control) para el tamaño de letra
    var onFontSizeDelta: ((CGFloat) -> Void)?
    var onFontSizeReset: (() -> Void)?

    private var scrollPan: UIPanGestureRecognizer?
    private var scrollAccum: CGFloat = 0
    /// Deceleración tras levantar el dedo (ver `startGlide`)
    private var glide: CADisplayLink?
    private var glideVelocity: CGFloat = 0
    /// Velocidad estimada a mano, en puntos por segundo (ver `.ended`)
    private var trackedVelocity: CGFloat = 0
    private var lastSampleTime: CFTimeInterval = 0
    /// Indicador de desplazamiento y cuántas líneas llevamos hacia atrás
    private let scrollThumb = UIView()
    private var linesBack = 0
    /// Líneas de rueda enviadas cuya respuesta todavía no ha llegado
    private var unconfirmedLines = 0
    private var thumbFade: DispatchWorkItem?
    /// Profundidad de historial descubierta hasta ahora, en líneas.
    ///
    /// No hay forma de preguntarle a tmux cuánto guarda, pero sí de observar
    /// hasta dónde deja llegar: cada vez que confirma un desplazamiento, el
    /// historial es al menos eso. Con ese dato el indicador ya puede ser
    /// proporcional de verdad.
    private var knownDepth = 0
    private var topProbe: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupScroll()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScroll()
    }

    /// Desplazamiento del historial con el dedo, el trackpad o la rueda.
    ///
    /// SwiftTerm no traduce el gesto a rueda, así que se hace aquí: con tmux
    /// delante —que es siempre, porque serve.sh abre las sesiones dentro de
    /// tmux— el emulador NO tiene historial propio que desplazar. tmux usa la
    /// pantalla alternativa, de modo que el búfer local mide exactamente una
    /// pantalla y el UIScrollView de SwiftTerm no tiene recorrido. El historial
    /// vive dentro de tmux y solo se alcanza por su modo copia, que se activa
    /// con la RUEDA.
    ///
    /// Hacen falta DOS dedos: uno solo queda para la selección y para lo que el
    /// programa remoto haga con el ratón. Es también lo que hace Terminal en
    /// macOS con el trackpad, y evita desplazar sin querer mientras se marca
    /// texto.
    private func setupScroll() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        pan.allowedScrollTypesMask = .all      // rueda y trackpad
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)
        scrollPan = pan
        buildScrollThumb()
    }

    /// Barra fina en el borde derecho, como la de cualquier vista de iOS:
    /// aparece al desplazar y se desvanece al parar.
    private func buildScrollThumb() {
        scrollThumb.backgroundColor = UIColor.label.withAlphaComponent(0.35)
        scrollThumb.layer.cornerRadius = 1.5
        scrollThumb.alpha = 0
        scrollThumb.isUserInteractionEnabled = false
        addSubview(scrollThumb)
    }

    /// Coloca y enseña el indicador, proporcional al contenido real.
    ///
    /// Fuera de tmux el emulador conoce su propio recorrido y se usa tal cual.
    ///
    /// Con tmux delante el historial es suyo y no se puede preguntar cuánto
    /// guarda. Pero sí se puede APRENDER: cada desplazamiento que confirma
    /// demuestra que hay al menos esa profundidad, y al llegar al tope deja de
    /// confirmar. Así el total se descubre solo y el indicador acaba siendo tan
    /// proporcional como el de cualquier vista — el alto del pulgar es la
    /// pantalla frente a pantalla más historial.
    ///
    /// Mientras aún no se ha llegado al fondo, lo descubierto es una cota
    /// inferior: el pulgar empieza grande y encoge conforme aparece historial,
    /// que es lo honesto cuando el total todavía no se conoce.
    private func flashScrollThumb() {
        guard bounds.height > 40 else { return }
        let travel: CGFloat
        let thumbHeight: CGFloat
        if getTerminal().mouseMode != .off {
            let visible = max(1, getTerminal().rows)
            let total = visible + knownDepth
            thumbHeight = max(24, bounds.height * CGFloat(visible) / CGFloat(total))
            travel = knownDepth > 0 ? min(1, CGFloat(linesBack) / CGFloat(knownDepth)) : 0
        } else {
            travel = 1 - CGFloat(scrollPosition)
            thumbHeight = max(24, bounds.height * CGFloat(scrollThumbsize))
        }
        let usable = max(0, bounds.height - thumbHeight - 8)
        let y = 4 + usable * (1 - travel)
        scrollThumb.frame = CGRect(x: bounds.width - 6, y: contentOffset.y + y,
                                   width: 3, height: thumbHeight)
        bringSubviewToFront(scrollThumb)

        thumbFade?.cancel()
        scrollThumb.alpha = 1
        let fade = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.35) { self?.scrollThumb.alpha = 0 }
        }
        thumbFade = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: fade)
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            stopGlide()                       // tocar corta la inercia anterior
            scrollAccum = 0
            trackedVelocity = 0
            lastSampleTime = CACurrentMediaTime()
        case .changed:
            let dy = gesture.translation(in: self).y
            gesture.setTranslation(.zero, in: self)
            scrollAccum += dy
            sampleVelocity(dy)
            emitWheelLines()
        case .ended:
            // `velocity(in:)` sirve para el dedo, pero en un desplazamiento
            // INDIRECTO —el trackpad— llega en cero: el sistema no rastrea
            // velocidad ahí, solo entrega deltas. Por eso el trackpad no
            // arrancaba la inercia y el dedo sí. Se usa la medida propia como
            // respaldo, que vale para los dos.
            let reported = gesture.velocity(in: self).y
            startGlide(velocity: abs(reported) > 1 ? reported : trackedVelocity)
        default:
            stopGlide()
            scrollAccum = 0
        }
    }

    /// Estima la velocidad con los deltas que van llegando.
    ///
    /// Media móvil y no el último delta a secas: un fotograma con un salto raro
    /// —o uno diminuto justo antes de soltar— no debe decidir por sí solo cuánta
    /// inercia lleva el gesto.
    ///
    /// Una pausa larga entre deltas significa que el gesto se detuvo aunque los
    /// dedos sigan puestos: ahí la velocidad se descarta, para que soltar tras
    /// pararse no lance la vista.
    private func sampleVelocity(_ dy: CGFloat) {
        let now = CACurrentMediaTime()
        let dt = now - lastSampleTime
        lastSampleTime = now
        guard dt > 0, dt < 0.1 else { trackedVelocity = 0; return }
        let instant = dy / CGFloat(dt)
        trackedVelocity = trackedVelocity * 0.7 + instant * 0.3
    }

    /// Convierte lo acumulado en líneas de rueda. El alto de línea sale de la
    /// tipografía en uso: con un número fijo, cambiar el tamaño de letra
    /// desajustaba cuánto se movía cada gesto.
    private func emitWheelLines() {
        let lineHeight = max(8, font.lineHeight)
        var moved = false
        while abs(scrollAccum) >= lineHeight {
            let up = scrollAccum > 0
            scrollAccum += up ? -lineHeight : lineHeight
            sendWheel(up: up)
            // NO se da por movido todavía: ver `didReceiveOutput`
            unconfirmedLines += up ? 1 : -1
            moved = true
        }
        guard moved else { return }
        if getTerminal().mouseMode == .off {
            flashScrollThumb()      // local: se sabe al instante
        } else {
            scheduleTopProbe()      // remoto: hay que esperar confirmación
        }
    }

    /// El host respondió: lo enviado sí movió la pantalla.
    ///
    /// Aquí está la corrección del indicador. Antes se contaba cada línea de
    /// rueda ENVIADA, y al llegar al principio del historial tmux deja de
    /// responder pero las líneas se seguían enviando: el contador crecía y la
    /// barrita seguía deslizándose contra un tope que ya se había alcanzado.
    ///
    /// Contando solo lo que el host confirma con datos de vuelta, al llegar al
    /// límite deja de llegar respuesta y la barrita se para sola — sin
    /// necesidad de saber cuánto historial tiene tmux, que desde aquí no se
    /// puede averiguar.
    func didReceiveOutput() {
        guard unconfirmedLines != 0 else { return }
        topProbe?.cancel()
        linesBack = max(0, linesBack + unconfirmedLines)
        unconfirmedLines = 0
        // el historial es al menos hasta donde nos han dejado llegar
        knownDepth = max(knownDepth, linesBack)
        flashScrollThumb()
    }

    /// Comprueba si hemos tocado el principio del historial.
    ///
    /// Si lo enviado sigue sin confirmarse pasado un momento, tmux no se movió:
    /// estamos en el tope. Se descarta lo pendiente para que el indicador no
    /// avance, y lo alcanzado queda como profundidad conocida.
    private func scheduleTopProbe() {
        topProbe?.cancel()
        let probe = DispatchWorkItem { [weak self] in
            guard let self, self.unconfirmedLines > 0 else { return }
            self.unconfirmedLines = 0
            self.knownDepth = max(self.knownDepth, self.linesBack)
            self.flashScrollThumb()
        }
        topProbe = probe
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: probe)
    }

    /// Deceleración propia al levantar el dedo.
    ///
    /// La inercia del sistema la aporta UIScrollView, y aquí no se mueve
    /// ninguno: el desplazamiento lo hace tmux al otro lado del cable. Por eso
    /// el contenido se paraba en seco. Esto prolonga el gesto con la velocidad
    /// que traía y la va apagando fotograma a fotograma.
    private func startGlide(velocity: CGFloat) {
        stopGlide()
        // por debajo de este umbral el gesto fue una colocación, no un impulso
        guard abs(velocity) > 150 else { scrollAccum = 0; return }
        glideVelocity = velocity
        let link = CADisplayLink(target: self, selector: #selector(stepGlide(_:)))
        link.add(to: .main, forMode: .common)
        glide = link
    }

    @objc private func stepGlide(_ link: CADisplayLink) {
        // el decaimiento se ata al tiempo real, no al fotograma: así frena
        // igual a 60 Hz que a los 120 de un iPad Pro
        glideVelocity *= pow(0.9, CGFloat(link.duration) * 60)
        guard abs(glideVelocity) > 50 else { stopGlide(); return }
        scrollAccum += glideVelocity * CGFloat(link.duration)
        emitWheelLines()
    }

    private func stopGlide() {
        glide?.invalidate()
        glide = nil
        glideVelocity = 0
        trackedVelocity = 0
        scrollAccum = 0
        // lo que no llegó a confirmarse no cuenta: si el host no respondió, no
        // se movió nada
        unconfirmedLines = 0
        topProbe?.cancel()
    }

    /// Si el programa remoto lee el ratón (tmux, vim, htop…) se le manda la
    /// rueda en codificación SGR; si no (bash pelado), se desplaza el historial
    /// local — mandar las secuencias a ciegas las escribía como texto basura
    /// (`64;1;1M64;1;1M…`) en la línea de comandos.
    private func sendWheel(up: Bool) {
        if getTerminal().mouseMode != .off {
            let button = up ? 64 : 65
            send(txt: "\u{1b}[<\(button);1;1M")
        } else if up {
            scrollUp(lines: 1)
        } else {
            scrollDown(lines: 1)
        }
    }

    // MARK: - Atajos

    override var keyCommands: [UIKeyCommand]? {
        var cmds = super.keyCommands ?? []
        func add(_ input: String, _ mods: UIKeyModifierFlags, _ sel: Selector, _ title: String) {
            let c = UIKeyCommand(title: title, action: sel, input: input, modifierFlags: mods)
            c.wantsPriorityOverSystemBehavior = true
            cmds.append(c)
        }
        for mod in [UIKeyModifierFlags.command, .control] {
            add("+", mod, #selector(fontBigger), "Aumentar tamaño")
            add("=", mod, #selector(fontBigger), "Aumentar tamaño")   // + sin shift
            add("-", mod, #selector(fontSmaller), "Reducir tamaño")
            add("0", mod, #selector(fontReset), "Tamaño original")
        }
        add("k", .command, #selector(clearScreen), "Limpiar pantalla")
        return cmds
    }

    /// Red de seguridad: si SwiftTerm consume la pulsación antes de que actúen
    /// los UIKeyCommand, se atiende aquí (es lo que pasaba con ⌘+ / ⌘−).
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            let mods = key.modifierFlags
            guard mods.contains(.command) || mods.contains(.control) else { continue }
            switch key.charactersIgnoringModifiers {
            case "+", "=":
                onFontSizeDelta?(1); return
            case "-", "_":
                onFontSizeDelta?(-1); return
            case "0":
                onFontSizeReset?(); return
            case "k" where mods.contains(.command):
                clearScreen(); return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    /// El terminal pide el foco en cuanto entra en una ventana.
    ///
    /// Está para escribir en él: exigir un toque previo antes de poder teclear
    /// es un paso que no aporta nada. Se pide en el siguiente ciclo porque en
    /// este momento la vista acaba de entrar en la jerarquía y aún no puede ser
    /// primer respondedor.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !isFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            _ = self.becomeFirstResponder()
        }
    }

    /// Qué cuenta como "desplazar" y qué no.
    ///
    /// El reparto que se busca es el de un terminal de escritorio:
    ///   · un dedo, o clic sostenido del trackpad → seleccionar
    ///   · dos dedos, o desplazamiento del trackpad → desplazar
    ///
    /// `minimumNumberOfTouches` ya lo impone para los dedos, pero conviene
    /// dejarlo explícito por el caso del trackpad: un desplazamiento indirecto
    /// NO trae dedos —llega como evento de scroll, con `numberOfTouches` a
    /// cero—, mientras que un clic arrastrado sí cuenta como uno. Esa es
    /// justamente la línea que separa desplazar de seleccionar con el trackpad,
    /// y la que hace que ambos convivan sin pisarse.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g === scrollPan else { return super.gestureRecognizerShouldBegin(g) }
        return g.numberOfTouches == 0 || g.numberOfTouches == 2
    }

    deinit { glide?.invalidate() }

    @objc private func fontBigger() { onFontSizeDelta?(1) }
    @objc private func fontSmaller() { onFontSizeDelta?(-1) }
    @objc private func fontReset() { onFontSizeReset?() }
    /// ⌘K en Terminal.app limpia la pantalla y el scrollback
    @objc private func clearScreen() { send(txt: "\u{0c}") }
}

extension MacTerminalView: UIGestureRecognizerDelegate {
    /// Desplazar y seleccionar son excluyentes.
    ///
    /// Aquí estaba el texto que se marcaba solo: este delegado devolvía `true`
    /// a todo, así que el gesto de scroll y los de SwiftTerm —el de selección y
    /// el que reenvía el ratón al programa remoto— corrían A LA VEZ. Con dos
    /// dedos se mandaba la rueda y, en paralelo, una pulsación arrastrada que
    /// tmux interpreta como "selecciona".
    ///
    /// Con otro gesto de arrastre, no. Con toques y pulsaciones largas sí:
    /// esos no compiten con desplazar y son los que dan la selección
    /// deliberada.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        !(other is UIPanGestureRecognizer)
    }

    /// Y entre los arrastres, manda el de desplazar.
    ///
    /// Sin esto, cuál gana depende de cuál reconozca primero — una carrera que
    /// se resuelve distinto según cómo apoyes los dedos, que es la peor clase
    /// de comportamiento: intermitente. Dos dedos rara vez tocan a la vez, y al
    /// moverse el primero el gesto de selección ya se había quedado el toque.
    ///
    /// Obligando a los demás a esperar a que este falle, dos dedos siempre
    /// desplazan. Y con uno solo este falla enseguida —no puede empezar sin dos
    /// toques—, así que la selección arranca sin retraso apreciable.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        g === scrollPan && other is UIPanGestureRecognizer
    }
}
