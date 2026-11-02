import AppKit
import ScreenCaptureKit

/// Live capture of one window into a CALayer.
///
/// Cost notes from the spike (docs/SPIKE-RESULTS.md):
/// - YUV 420v is ~1.5 bytes/pixel instead of 4; queue depth 3 instead of 5.
/// - ScreenCaptureKit sends every captured window a full frame whenever anything on its display updates,
///   so identical frames are skipped (redrawing them is what's expensive), and a window that hasn't changed
///   for ~0.5 s is captured at 10 fps until it changes again.
/// - While the real window is swapped in, nobody sees the mirror: 1 fps.
@MainActor
final class WindowCapture {
    enum Rate { case live, background }

    var onStopped: ((String) -> Void)?
    /// The window's own corner shape, measured once per start.
    var onCorners: ((Corners) -> Void)?

    /// The window's real corners, cut from a snapshot with transparency, for masking the mirror exactly.
    struct Corners {
        /// Approximate radius in points, for the border.
        let radius: CGFloat
        /// The four corners around a one-pixel stretchable middle; use with `contentsCenter`.
        let mask: CGImage
        let contentsCenter: CGRect
        let scale: CGFloat
    }

    private let window: SCWindow
    private let output: FrameOutput
    private var stream: SCStream?
    private var scale: CGFloat = 2
    private var size: CGSize
    private var idle = false

    var rate: Rate = .live {
        didSet {
            guard rate != oldValue else { return }
            reconfigure()
        }
    }

    static let liveFrameRate = 60
    static let idleFrameRate = 10
    static let backgroundFrameRate = 1

    init(window: SCWindow, layer: CALayer) {
        self.window = window
        self.size = window.frame.size
        output = FrameOutput(layer: layer)
    }

    func start() {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        scale = CGFloat(filter.pointPixelScale)
        size = filter.contentRect.size

        output.onIdleChanged = { [weak self] idle in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.idle != idle else { return }
                    self.idle = idle
                    self.reconfigure()
                }
            }
        }
        output.onStop = { [weak self] message in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.stopped(message) }
            }
        }

        let stream = SCStream(filter: filter, configuration: makeConfig(), delegate: output)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        } catch {
            stopped("addStreamOutput: \(error.localizedDescription)")
            return
        }
        self.stream = stream
        measureCorners(filter)
        stream.startCapture { [weak self] error in
            guard let error else { return }
            let message = error.localizedDescription
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.stopped("startCapture: \(message)") }
            }
        }
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
    }

    /// Keeps capture pixels 1:1 with the window so the mirror stays sharp after a resize.
    func resize(to size: CGSize) {
        guard size != self.size else { return }
        self.size = size
        reconfigure()
    }

    private func reconfigure() {
        stream?.updateConfiguration(makeConfig()) { error in
            if let error { tackLog("capture: updateConfiguration failed: \(error.localizedDescription)") }
        }
    }

    private func makeConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = Int(size.width * scale)
        config.height = Int(size.height * scale)
        let fps = switch rate {
        case .background: Self.backgroundFrameRate
        case .live: idle ? Self.idleFrameRate : Self.liveFrameRate
        }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        config.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        config.showsCursor = false
        config.queueDepth = 3
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.captureResolution = .best
        return config
    }

    /// The live stream is YUV, which has no transparency, so the window's own rounded corners come through black.
    /// One BGRA snapshot shows how round they really are.
    private func measureCorners(_ filter: SCContentFilter) {
        let config = SCStreamConfiguration()
        config.width = Int(size.width * scale)
        config.height = Int(size.height * scale)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        let scale = scale
        Task { [weak self] in
            do {
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard let corners = Self.corners(of: image, scale: scale) else { return }
                self?.onCorners?(corners)
            } catch {
                tackLog("capture: corner snapshot failed: \(error.localizedDescription)")
            }
        }
    }

    /// Walks the top-left corner's diagonal until it hits the window. Along the diagonal a rounded corner is
    /// inset by about 0.29 × its radius, for both circular and continuous corners.
    nonisolated static func cornerRadius(of image: CGImage, scale: CGFloat) -> CGFloat? {
        let n = min(image.width, image.height, Int(80 * scale))
        guard n > 0, let context = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: n - image.height, width: image.width, height: image.height))
        var inset = 0
        while inset < n, pixels[(inset * n + inset) * 4 + 3] < 128 { inset += 1 }
        guard inset < n else { return nil }
        return CGFloat(inset) / scale / 0.29
    }

    /// Copies each corner of the snapshot into a small (2c+1)² image whose middle row and column can stretch,
    /// so the mask fits any pin size while the corners stay pixel-exact, anti-aliasing included.
    nonisolated static func corners(of image: CGImage, scale: CGFloat) -> Corners? {
        guard let radius = cornerRadius(of: image, scale: scale) else { return nil }
        let w = image.width, h = image.height
        // Continuous corners curve over about 1.5 × the radius along each edge.
        let c = min(Int(((radius * 1.6) + 4) * scale), (min(w, h) - 1) / 2)
        let m = 2 * c + 1
        guard c > 0, let context = CGContext(data: nil, width: m, height: m, bitsPerComponent: 8, bytesPerRow: m * 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Quartz's origin is bottom-left: the left part takes the image's left edge, the top part its top edge.
        for (clipX, originX) in [(0..<(c + 1), 0), ((c + 1)..<m, m - w)] {
            for (clipY, originY) in [(0..<c, 0), (c..<m, m - h)] {
                context.saveGState()
                context.clip(to: CGRect(x: clipX.lowerBound, y: clipY.lowerBound, width: clipX.count, height: clipY.count))
                context.draw(image, in: CGRect(x: originX, y: originY, width: w, height: h))
                context.restoreGState()
            }
        }
        guard let mask = context.makeImage() else { return nil }
        let unit = 1 / CGFloat(m)
        return Corners(radius: radius, mask: mask,
                       contentsCenter: CGRect(x: CGFloat(c) * unit, y: CGFloat(c) * unit, width: unit, height: unit),
                       scale: scale)
    }

    private func stopped(_ message: String) {
        guard stream != nil else { return }
        stream = nil
        tackLog("capture: stopped (\(message))")
        onStopped?(message)
    }
}

/// Receives frames on a background queue and puts changed ones straight on the layer. Core Animation allows
/// layer changes from any thread inside an explicit transaction.
private final class FrameOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "studio.kweng.Tack.capture", qos: .userInteractive)
    /// Set before capture starts; only read on `queue` afterwards.
    var onIdleChanged: (@Sendable (Bool) -> Void)?
    var onStop: (@Sendable (String) -> Void)?

    private let layer: CALayer
    // Only touched on `queue`.
    private var lastFingerprint: UInt64 = 0
    private var unchangedFrames = 0
    private static let framesBeforeIdle = 30

    init(layer: CALayer) {
        self.layer = layer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }

        // No fingerprint means the frame couldn't be read: show it rather than skip it.
        let fingerprint = Self.fingerprint(surface) ?? 0
        guard fingerprint == 0 || fingerprint != lastFingerprint else {
            unchangedFrames += 1
            if unchangedFrames == Self.framesBeforeIdle { onIdleChanged?(true) }
            return
        }
        lastFingerprint = fingerprint
        if unchangedFrames >= Self.framesBeforeIdle { onIdleChanged?(false) }
        unchangedFrames = 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contents = surface
        CATransaction.commit()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error.localizedDescription)
    }

    /// Hash of every 8th row of the luma plane; four lanes to keep the multiply chains short.
    /// A line of text spans many rows, so sampling still catches typing.
    /// nil when the surface can't be read: while displays reconfigure (lid closing, say) a frame can arrive
    /// whose memory isn't mapped, and reading it crashed Tack.
    private static func fingerprint(_ surface: IOSurface) -> UInt64? {
        guard IOSurfaceLock(surface, .readOnly, nil) == kIOReturnSuccess else { return nil }
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }
        let planar = IOSurfaceGetPlaneCount(surface) > 0
        let base = planar ? IOSurfaceGetBaseAddressOfPlane(surface, 0) : IOSurfaceGetBaseAddress(surface)
        guard Int(bitPattern: base) != 0 else { return nil }
        let bytesPerRow = planar ? IOSurfaceGetBytesPerRowOfPlane(surface, 0) : IOSurfaceGetBytesPerRow(surface)
        let height = planar ? IOSurfaceGetHeightOfPlane(surface, 0) : IOSurfaceGetHeight(surface)
        let rowBytes = planar ? IOSurfaceGetWidthOfPlane(surface, 0) : IOSurfaceGetWidth(surface) * 4
        let words = rowBytes / 32 * 4
        guard words * 8 <= bytesPerRow else { return nil }
        let prime: UInt64 = 0x100000001b3
        var h0: UInt64 = 0xcbf29ce484222325, h1 = h0 &+ 1, h2 = h0 &+ 2, h3 = h0 &+ 3
        for y in stride(from: 0, to: height, by: 8) {
            let row = (base + y * bytesPerRow).assumingMemoryBound(to: UInt64.self)
            var x = 0
            while x < words {
                h0 = (h0 ^ row[x]) &* prime
                h1 = (h1 ^ row[x + 1]) &* prime
                h2 = (h2 ^ row[x + 2]) &* prime
                h3 = (h3 ^ row[x + 3]) &* prime
                x += 4
            }
        }
        return h0 ^ (h1 &* 3) ^ (h2 &* 5) ^ (h3 &* 7)
    }
}
