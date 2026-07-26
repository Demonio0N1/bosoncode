import AVFoundation
import AVKit
import SwiftUI

/// Picture-in-Picture del sistema para la terminal: retransmite instantáneas
/// de la vista como frames de video a un AVSampleBufferDisplayLayer, que iOS
/// puede sacar de la app. Mientras el PiP está activo, la app sigue viva en
/// segundo plano y la conexión PTY no se corta.
final class PiPManager: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var isPossible = false

    let displayLayer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var timer: Timer?
    private var frameSource: (() -> UIView?)?
    private var possibleObservation: NSKeyValueObservation?
    private var timebase: CMTimebase?

    func attach(frameSource: @escaping () -> UIView?) {
        self.frameSource = frameSource
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        // reentrante: no crear un segundo controller sobre el anterior
        guard controller == nil else { return }
        displayLayer.videoGravity = .resizeAspect
        // reloj de reproducción corriendo (rate 1.0): sin él, la cola muere
        // tras cada frame y AVKit alterna la elegibilidad del PiP sin parar
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                        sourceClock: CMClockGetHostTimeClock(),
                                        timebaseOut: &tb)
        if let tb {
            CMTimebaseSetTime(tb, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(tb, rate: 1.0)
            displayLayer.controlTimebase = tb
            timebase = tb
        }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        controller = pip
        // isPictureInPicturePossible tarda en volverse true (necesita frames
        // fluyendo y capa en pantalla): se observa en vez de asumirse
        possibleObservation = pip.observe(\.isPictureInPicturePossible,
                                          options: [.initial, .new]) { [weak self] c, _ in
            print("[PiP] isPictureInPicturePossible = \(c.isPictureInPicturePossible)")
            DispatchQueue.main.async { self?.isPossible = c.isPictureInPicturePossible }
        }
        startFrames()
        pushFrame()   // primer frame inmediato
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            print("[PiP] estado a los 3s: possible=\(self.controller?.isPictureInPicturePossible ?? false) layerStatus=\(self.displayLayer.status.rawValue) layerEnPantalla=\(self.displayLayer.superlayer != nil) error=\(String(describing: self.displayLayer.error))")
        }
    }

    deinit {
        timer?.invalidate()
        possibleObservation = nil
    }

    func detach() {
        timer?.invalidate()
        timer = nil
        possibleObservation = nil
        controller?.stopPictureInPicture()
        controller = nil
        frameSource = nil
        displayLayer.controlTimebase = nil
        timebase = nil
        isActive = false
        releaseAudioSession()
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            // la sesión de audio se reclama SOLO al entrar en PiP (si se
            // activara al abrir la terminal, cortaría tu música sin motivo)
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            controller.startPictureInPicture()
        }
    }

    private func releaseAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: [.notifyOthersOnDeactivation])
    }

    /// Cadencia adaptativa: 10 fps con el PiP activo (fluido), 3 fps mientras
    /// está inactivo — lo justo para que AVKit lo considere elegible sin
    /// quemar CPU/batería renderizando la vista todo el rato.
    private func startFrames() {
        setFrameRate(inactive: true)
    }

    private func setFrameRate(inactive: Bool) {
        timer?.invalidate()
        let t = Timer(timeInterval: inactive ? 0.33 : 0.1, repeats: true) { [weak self] _ in
            self?.pushFrame()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Diagnóstico: true = patrón rojo con reloj en vez de la captura real
    static let testPattern = false

    private func pushFrame() {
        guard let view = frameSource?(), view.bounds.width > 10 else { return }
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image: UIImage
        if Self.testPattern {
            image = renderer.image { ctx in
                UIColor.systemRed.setFill()
                ctx.fill(view.bounds)
                let text = "PiP \(Date().formatted(date: .omitted, time: .standard))"
                (text as NSString).draw(
                    at: CGPoint(x: 20, y: 20),
                    withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 28, weight: .bold),
                                     .foregroundColor: UIColor.white])
            }
        } else {
            // layer.render captura contenido CoreText/CoreGraphics del terminal
            image = renderer.image { ctx in
                view.layer.render(in: ctx.cgContext)
            }
        }
        // programado 0.3s en el futuro contra el timebase: la cola siempre
        // tiene media pendiente y el PiP se mantiene elegible
        let pts = timebase.map { CMTimeAdd(CMTimebaseGetTime($0),
                                           CMTime(value: 3, timescale: 10)) }
            ?? CMClockGetTime(CMClockGetHostTimeClock())
        frameCount += 1
        guard let buffer = Self.sampleBuffer(from: image, presentationTime: pts) else {
            if frameCount % 20 == 0 { print("[PiP] sampleBuffer devolvió NIL") }
            return
        }
        // camino moderno (iOS 17+): sampleBufferRenderer en vez de enqueue directo
        let renderer2 = displayLayer.sampleBufferRenderer
        if renderer2.requiresFlushToResumeDecoding { renderer2.flush() }
        if renderer2.isReadyForMoreMediaData {
            renderer2.enqueue(buffer)
        } else if frameCount % 20 == 0 {
            print("[PiP] renderer NO acepta media")
        }
        if frameCount % 30 == 0 {
            let tb = timebase.map { CMTimeGetSeconds(CMTimebaseGetTime($0)) } ?? -1
            print("[PiP] frames=\(frameCount) status=\(renderer2.status.rawValue) error=\(String(describing: renderer2.error)) timebase=\(String(format: "%.1f", tb)) imgSize=\(Int(image.size.width))x\(Int(image.size.height))")
        }
    }

    private var frameCount = 0

    private static func sampleBuffer(from image: UIImage,
                                     presentationTime: CMTime) -> CMSampleBuffer? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var pixelBufferOut: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            // CLAVE: sin respaldo IOSurface, el display layer acepta el frame
            // pero no lo muestra jamás (negro silencioso)
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBufferOut)
        guard let pixelBuffer = pixelBufferOut else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        context?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var formatOut: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatOut)
        guard let format = formatOut else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 10),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &sampleOut)
        return sampleOut
    }
}

extension PiPManager: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        isActive = true
        setFrameRate(inactive: false)   // fluido mientras se ve en PiP
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        isActive = false
        setFrameRate(inactive: true)
        releaseAudioSession()           // devuelve el audio a otras apps
    }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        print("PiP error: \(error)")
    }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
                                    completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)   // "en vivo"
    }
    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime) async {}
}

/// Aloja el AVSampleBufferDisplayLayer en la jerarquía (requisito de PiP).
/// El sublayer sigue el tamaño real en layoutSubviews — SwiftUI no notifica
/// los cambios de layout a updateUIView, y un frame en cero = capa invisible.
final class LayerHostUIView: UIView {
    var hostedLayer: CALayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let hostedLayer {
                layer.addSublayer(hostedLayer)
                hostedLayer.frame = bounds
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostedLayer?.frame = bounds
        CATransaction.commit()
    }
}

struct PiPHostView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> LayerHostUIView {
        let view = LayerHostUIView()
        view.hostedLayer = layer
        return view
    }

    func updateUIView(_ uiView: LayerHostUIView, context: Context) {}
}
