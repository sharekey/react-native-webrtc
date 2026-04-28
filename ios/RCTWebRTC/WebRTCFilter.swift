//
//  WebRTCFilter.swift
//  react-native-webrtc
//
//  Created by  Denis on 18.12.24.
//

import Vision
import WebRTC
import CoreImage
import Foundation
import CoreImage.CIFilterBuiltins

#if targetEnvironment(simulator)
#else
import MLCompute
#endif

class VideoFilter {
  struct Input {
    public var originalImage: CIImage
    public var originalPixelBuffer: CVPixelBuffer
    public var originalImageOrientation: CGImagePropertyOrientation
  }

  let name: String
  var filter: (Input) async -> CIImage

  init(name: String, filter: @escaping (Input) async -> CIImage) {
    self.name = name
    self.filter = filter
  }
}

extension VideoFilter {
  static let blurredBackground: VideoFilter = BlurBackgroundVideoFilter()
  static func imageBackground(_ backgroundImage: CIImage) -> VideoFilter {
    ImageBackgroundVideoFilter(backgroundImage)
  }
}

protocol ImageFilterProcessor {
  func applyFilter(_ pixelBuffer: CVPixelBuffer, backgroundImage: CIImage) -> CIImage?
  func modify(buffer: CVPixelBuffer, maskBuffer: CVPixelBuffer, backgroundImage: CIImage) throws -> CIImage?
}

extension ImageFilterProcessor {
  func modify(buffer: CVPixelBuffer, maskBuffer: CVPixelBuffer, backgroundImage: CIImage) throws -> CIImage? {
    let originalImage = CIImage(cvPixelBuffer: buffer)
    var maskImage = CIImage(cvPixelBuffer: maskBuffer)

    let scaleX = originalImage.extent.width / maskImage.extent.width
    let scaleY = originalImage.extent.height / maskImage.extent.height
    maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

    let blendFilter = CIFilter.blendWithMask()
    blendFilter.inputImage = originalImage
    blendFilter.backgroundImage = backgroundImage
    blendFilter.maskImage = maskImage

    return blendFilter.outputImage
  }
}

final class BlurBackgroundVideoFilter: VideoFilter {
  private let processor: ImageFilterProcessor

  init() {
    let name = String(describing: type(of: self))

    if #available(iOS 17.0, *) {
      self.processor = NewBackgroundImageFilterProcessor()
    } else {
      self.processor = BackgroundImageFilterProcessor()
    }

    super.init(name: name, filter: \.originalImage)

    filter = { [processor] input in
      let backgroundImage = input
        .originalImage
        .applyingFilter("CIGaussianBlur")

      return processor
        .applyFilter(
          input.originalPixelBuffer,
          backgroundImage: backgroundImage
        ) ?? input.originalImage
    }
  }
}

final class ImageBackgroundVideoFilter: VideoFilter {
  private struct CacheValue: Hashable {
    var originalImageSize: CGSize
    var originalImageOrientation: CGImagePropertyOrientation
    var result: CIImage

    func hash(into hasher: inout Hasher) {
      hasher.combine(originalImageSize.width)
      hasher.combine(originalImageSize.height)
      hasher.combine(originalImageOrientation)
    }
  }

  private let processor: ImageFilterProcessor
  private var cachedValue: CacheValue?
  private let backgroundImage: CIImage

  init(_ backgroundImage: CIImage?) {
    let name = String(describing: type(of: self))

    if #available(iOS 17.0, *) {
      self.processor = NewBackgroundImageFilterProcessor()
    } else {
      self.processor = BackgroundImageFilterProcessor()
    }

    self.backgroundImage = backgroundImage ?? CIImage()

    super.init(name: name, filter: \.originalImage)

    filter = { [processor, weak self] input in
      guard
        let backgroundImage = self?.backgroundImage(for: input)
      else { return input.originalImage }

      return processor.applyFilter(
        input.originalPixelBuffer,
        backgroundImage: backgroundImage
      ) ?? input.originalImage
    }
  }

  private func backgroundImage(for input: Input) -> CIImage {
    if
      let cachedValue = cachedValue,
      cachedValue.originalImageSize == input.originalImage.extent.size,
      cachedValue.originalImageOrientation == input.originalImageOrientation {
      return cachedValue.result
    } else {
      var cachedBackgroundImage = backgroundImage.oriented(input.originalImageOrientation)

      if cachedBackgroundImage.extent.size != input.originalImage.extent.size {
        cachedBackgroundImage = cachedBackgroundImage
          .resize(input.originalImage.extent.size) ?? cachedBackgroundImage
      }

      cachedValue = .init(
        originalImageSize: input.originalImage.extent.size,
        originalImageOrientation: input.originalImageOrientation,
        result: cachedBackgroundImage
      )
      return cachedBackgroundImage
    }
  }
}

@available(iOS 15.0, *)
final class BackgroundImageFilterProcessor: ImageFilterProcessor {
  private let request: VNGeneratePersonSegmentationRequest
  private let requestHandler: VNSequenceRequestHandler = .init()

  init() {
    let request: VNGeneratePersonSegmentationRequest = .init()
    request.qualityLevel = .fast

    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    self.request = request
  }

  func applyFilter(_ buffer: CVPixelBuffer, backgroundImage: CIImage) -> CIImage? {
    do {
      try requestHandler.perform([request], on: buffer)

      if let maskPixelBuffer = request.results?.first?.pixelBuffer {
        return try modify(buffer: buffer, maskBuffer: maskPixelBuffer, backgroundImage: backgroundImage)
      }
    } catch {
      print(error)
    }

    return backgroundImage
  }
}

@available(iOS 17.0, *)
final class NewBackgroundImageFilterProcessor: ImageFilterProcessor {
  private let maskRequest: VNGeneratePersonInstanceMaskRequest

  init() {
    self.maskRequest = VNGeneratePersonInstanceMaskRequest()
  }

  func applyFilter(_ buffer: CVPixelBuffer, backgroundImage: CIImage) -> CIImage? {
    do {
      let handler = VNImageRequestHandler(ciImage: CIImage(cvPixelBuffer: buffer), options: [:])
      try handler.perform([maskRequest])

      if let observation = maskRequest.results?.first {
        let maskPixelBuffer = try observation.generateMask(forInstances: observation.allInstances)
        return try modify(buffer: buffer, maskBuffer: maskPixelBuffer, backgroundImage: backgroundImage)
      }
    } catch {
      print(error)
    }

    return backgroundImage
  }
}

extension CIImage {
  func resize(_ targetSize: CGSize) -> CIImage? {
    let scale = targetSize.height / (extent.height)
    let aspectRatio = targetSize.width / ((extent.width) * scale)

    if let filter = CIFilter(name: "CILanczosScaleTransform") {
      filter.setValue(self, forKey: kCIInputImageKey)
      filter.setValue(NSNumber(value: scale), forKey: kCIInputScaleKey)
      filter.setValue(NSNumber(value: aspectRatio), forKey: kCIInputAspectRatioKey)

      return filter.outputImage
    }

    return nil
  }
}
