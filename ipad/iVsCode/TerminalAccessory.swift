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

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupScroll()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScroll()
    }

    /// Scroll de historial con trackpad y dos dedos: SwiftTerm no traduce el
    /// gesto, así que se envían eventos de rueda al programa remoto (tmux con
    /// el ratón activo los convierte en desplazamiento del historial).
    private func setupScroll() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        pan.allowedScrollTypesMask = .all      // rueda y trackpad
        pan.maximumNumberOfTouches = 2
        pan.minimumNumberOfTouches = 2         // un dedo sigue seleccionando
        pan.delegate = self
        addGestureRecognizer(pan)
        scrollPan = pan
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            scrollAccum = 0
        case .changed:
            let dy = gesture.translation(in: self).y
            gesture.setTranslation(.zero, in: self)
            scrollAccum += dy
            let lineHeight: CGFloat = 22
            while abs(scrollAccum) >= lineHeight {
                let up = scrollAccum > 0
                scrollAccum += up ? -lineHeight : lineHeight
                sendWheel(up: up)
            }
        default:
            scrollAccum = 0
        }
    }

    /// Rueda en codificación SGR (la que entiende tmux con `mouse on`)
    private func sendWheel(up: Bool) {
        let button = up ? 64 : 65
        send(txt: "\u{1b}[<\(button);1;1M")
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

    @objc private func fontBigger() { onFontSizeDelta?(1) }
    @objc private func fontSmaller() { onFontSizeDelta?(-1) }
    @objc private func fontReset() { onFontSizeReset?() }
    /// ⌘K en Terminal.app limpia la pantalla y el scrollback
    @objc private func clearScreen() { send(txt: "\u{0c}") }
}

extension MacTerminalView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
