import Vision
import CoreImage
import Foundation
import CoreImage.CIFilterBuiltins

class VideoFilter {
  struct Input {
    // Images are upright here; the capture handler restores the buffer orientation after filtering.
    public var originalImage: CIImage
  }

  let name: String
  var filter: (Input) -> CIImage

  init(name: String, filter: @escaping (Input) -> CIImage) {
    self.name = name
    self.filter = filter
  }

  func apply(to image: CIImage, rotationDegrees: Int) -> CIImage {
    let orientation: CGImagePropertyOrientation
    let inverse: CGImagePropertyOrientation
    switch rotationDegrees {
    case 90: (orientation, inverse) = (.right, .left)
    case 180: (orientation, inverse) = (.down, .down)
    case 270: (orientation, inverse) = (.left, .right)
    default: (orientation, inverse) = (.up, .up)
    }
    let upright = image.oriented(orientation)
    return filter(Input(originalImage: upright)).cropped(to: upright.extent).oriented(inverse)
  }
}

extension VideoFilter {
  static var blurredBackground: VideoFilter { BlurBackgroundVideoFilter() }

  static func imageBackground(_ backgroundImage: CIImage) -> VideoFilter {
    ImageBackgroundVideoFilter(backgroundImage)
  }
}

protocol ImageFilterProcessor {
  func applyFilter(_ image: CIImage, backgroundImage: CIImage) -> CIImage?
}

extension ImageFilterProcessor {
  func modify(image: CIImage, maskBuffer: CVPixelBuffer, backgroundImage: CIImage) -> CIImage? {
    let mask = CIImage(cvPixelBuffer: maskBuffer)
    let maskImage = mask.transformed(by: .init(
      scaleX: image.extent.width / mask.extent.width,
      y: image.extent.height / mask.extent.height
    )).transformed(by: .init(translationX: image.extent.minX, y: image.extent.minY))

    let blendFilter = CIFilter.blendWithMask()
    blendFilter.inputImage = image
    blendFilter.backgroundImage = backgroundImage
    blendFilter.maskImage = maskImage
    return blendFilter.outputImage?.cropped(to: image.extent)
  }
}

final class BlurBackgroundVideoFilter: VideoFilter {
  init() {
    let processor = BackgroundImageFilterProcessor()
    super.init(name: "BlurBackgroundVideoFilter", filter: \.originalImage)
    filter = { input in
      let image = input.originalImage
      let background = image.clampedToExtent()
        .applyingFilter("CIGaussianBlur")
        .cropped(to: image.extent)
      return processor.applyFilter(image, backgroundImage: background) ?? background
    }
  }
}

final class ImageBackgroundVideoFilter: VideoFilter {
  private let backgroundImage: CIImage
  private var cachedBackground: CIImage?

  init(_ backgroundImage: CIImage) {
    let processor = BackgroundImageFilterProcessor()
    self.backgroundImage = backgroundImage
    super.init(name: "ImageBackgroundVideoFilter", filter: \.originalImage)
    filter = { [weak self] input in
      guard let background = self?.backgroundImage(for: input.originalImage.extent) else {
        return input.originalImage
      }
      return processor.applyFilter(input.originalImage, backgroundImage: background) ?? background
    }
  }

  func backgroundImage(for extent: CGRect) -> CIImage {
    if let cachedBackground = cachedBackground, cachedBackground.extent == extent {
      return cachedBackground
    }
    let scale = max(extent.width / backgroundImage.extent.width, extent.height / backgroundImage.extent.height)
    let scaled = backgroundImage.transformed(by: .init(scaleX: scale, y: scale))
    let result = scaled.transformed(by: .init(
      translationX: extent.midX - scaled.extent.midX,
      y: extent.midY - scaled.extent.midY
    )).cropped(to: extent)
    cachedBackground = result
    return result
  }
}

final class BackgroundImageFilterProcessor: ImageFilterProcessor {
  private let request: VNGeneratePersonSegmentationRequest
  private let requestHandler = VNSequenceRequestHandler()

  init() {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .fast
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    self.request = request
  }

  func applyFilter(_ image: CIImage, backgroundImage: CIImage) -> CIImage? {
    do {
      // Reuse the video segmentation request; instance masks are too costly for live capture.
      try requestHandler.perform([request], on: image, orientation: .up)
      if let mask = request.results?.first?.pixelBuffer {
        return modify(image: image, maskBuffer: mask, backgroundImage: backgroundImage)
      }
    } catch {
      print("Background segmentation failed: \(error)")
    }
    return backgroundImage
  }
}

// Admit a frame before scheduling work so slow processing cannot retain a queue of camera buffers.
final class CaptureFrameGate {
  static let effectFrameIntervalNs: Int64 = 1_000_000_000 / 30

  private let lock = NSLock()
  private var processing = false
  private var lastTimestampNs: Int64?

  func tryBegin(timestampNs: Int64, minimumIntervalNs: Int64) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !processing else { return false }
    if let last = lastTimestampNs,
       timestampNs <= last || timestampNs - last < minimumIntervalNs {
      return false
    }
    processing = true
    lastTimestampNs = timestampNs
    return true
  }

  func finish() {
    lock.lock()
    processing = false
    lock.unlock()
  }
}
