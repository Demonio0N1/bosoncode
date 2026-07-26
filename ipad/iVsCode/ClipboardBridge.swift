import WebKit
import UIKit

/// Puente entre la Clipboard API del WebView y UIPasteboard.
/// Evita los prompts de permiso y los fallos silenciosos de navigator.clipboard.
final class ClipboardBridge: NSObject, WKScriptMessageHandlerWithReply {

    /// Inyectado en cada página: sobreescribe la Clipboard API con el pasteboard
    /// nativo. En orígenes http:// (serve.sh en LAN) navigator.clipboard no
    /// existe — contexto no seguro — así que se instala como polyfill completo.
    static let script = """
    (() => {
      const impl = {
        writeText: (text) =>
          window.webkit.messageHandlers.clipboard.postMessage({ op: "write", text }),
        readText: () =>
          window.webkit.messageHandlers.clipboard.postMessage({ op: "read" }),
      };
      if (navigator.clipboard) {
        navigator.clipboard.writeText = impl.writeText;
        navigator.clipboard.readText = impl.readText;
      } else {
        try {
          Object.defineProperty(navigator, "clipboard", { value: impl });
        } catch (e) {}
      }
    })();
    """

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any],
              let op = body["op"] as? String else {
            replyHandler(nil, "mensaje inválido")
            return
        }
        switch op {
        case "write":
            UIPasteboard.general.string = body["text"] as? String ?? ""
            replyHandler(nil, nil)
        case "read":
            replyHandler(UIPasteboard.general.string ?? "", nil)
        default:
            replyHandler(nil, "operación desconocida: \(op)")
        }
    }
}
