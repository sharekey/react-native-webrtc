//
//  WebRTCVideoCaptureHandler.swift
//  react-native-webrtc
//
//  Created by  Denis on 18.12.24.
//

import Vision
import WebRTC
import Combine
import Foundation
import CoreImage
import Foundation
import CoreImage.CIFilterBuiltins

final public class WebRTCVoiceHandler: NSObject {
  private var outgoingVoicePublisher: CurrentValueSubject<(RTCPeerConnection?, Bool, Double), Never> = .init((nil, false, 0))
  private var incomingVoicePublisher: CurrentValueSubject<(RTCPeerConnection?, Bool, Double), Never> = .init((nil, false, 0))

  private var observeTask: Task<Void, Never>?
  private var disposeBag: Set<AnyCancellable> = []

  @objc
  public func startObserve(peerConnections: [RTCPeerConnection],
                           voiceClosure: @escaping (RTCPeerConnection, Bool, Bool, Double) -> Void) -> Self {
    let _ = stopObserve()

    observeTask = Task {
      await observeVoiceActivity(peerConnections: peerConnections)
    }

    outgoingVoicePublisher.removeDuplicates(by: { $0.1 == $1.1 }).sink { (peer, isSpeaking, audioLevel) in
      guard let peer else { return }
      voiceClosure(peer, true, isSpeaking, audioLevel)
    }.store(in: &disposeBag)

    incomingVoicePublisher.removeDuplicates(by: { $0.1 == $1.1 }).sink { (peer, isSpeaking, audioLevel) in
      guard let peer else { return }
      voiceClosure(peer, false, isSpeaking, audioLevel)
    }.store(in: &disposeBag)

    return self
  }

  @objc
  public func stopObserve() -> Self {
    observeTask?.cancel()
    disposeBag.forEach { $0.cancel() }

    return self
  }

  private func observeVoiceActivity(peerConnections: [RTCPeerConnection]) async {
    let checkInterval: Double = 0.1
    let silenceThreshold: Double = 0.3

    var silenceIncomingCount: Double = 0
    var silenceOutgoingCount: Double = 0

    while !Task.isCancelled {
      do {
        peerConnections.forEach { [weak self] peerConnection in
          guard let self = self else { return }

          if peerConnection.connectionState == .connected {
            peerConnection.statistics { reports in
              for statistic in reports.statistics.values {
                if statistic.type == "inbound-rtp" {
                  guard let audioLevel = statistic.values["audioLevel"] as? Double else { return }

                  if audioLevel > 0.1 {
                    self.incomingVoicePublisher.send((peerConnection, true, audioLevel))
                  } else {
                    silenceIncomingCount += 1

                    if silenceIncomingCount > silenceThreshold / checkInterval {
                      self.incomingVoicePublisher.send((peerConnection, false, audioLevel))
                    }
                  }
                }

                if statistic.type == "media-source" {
                  guard let audioLevel = statistic.values["audioLevel"] as? Double else { return }

                  if audioLevel > 0.1 {
                    self.outgoingVoicePublisher.send((peerConnection, true, audioLevel))
                  } else {
                    silenceOutgoingCount += 1

                    if silenceOutgoingCount > silenceThreshold / checkInterval {
                      self.outgoingVoicePublisher.send((peerConnection, false, audioLevel))
                    }
                  }
                }
              }
            }
          } else {
            self.incomingVoicePublisher.send((peerConnection, false, 0))
            self.outgoingVoicePublisher.send((peerConnection, false, 0))
          }
        }

        try await Task.sleep(nanoseconds: UInt64(checkInterval * 1000000000))
      } catch {
        print(error)
      }
    }
  }
}

final public class WebRTCVideoCaptureHandler: NSObject, RTCVideoCapturerDelegate {
  var selectedFilter: VideoFilter?

  private lazy var serialActor = SerialActor()

  private let source: RTCVideoCapturerDelegate
  private let context: CIContext
  private let colorSpace: CGColorSpace
  private var frameCount: Int = 0
  private var fpsInterval: Int64 = 1000000000 / 15
  private let handleRotation: Bool
  private var sceneOrientation: StreamDeviceOrientation = .portrait(isUpsideDown: false)
  private var latestTimestampNs: Int64 = 0
  private var currentCameraPosition: AVCaptureDevice.Position = .front
  private var lastProcessedTimestamp: Int64 = 0
  private var orientationCancellable: AnyCancellable?

  @objc
  public init(source: RTCVideoCapturerDelegate, backgroundImageData: Data?) {
    self.source = source
    self.context = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
    self.colorSpace = CGColorSpaceCreateDeviceRGB()
    self.handleRotation = true

    super.init()
  }


  @objc
  public func enable(blur: Bool, backgroundImageData: Data?) {
    if let data = backgroundImageData, let backgroundImage: CIImage = CIImage(data: data) {
      selectedFilter = .imageBackground(backgroundImage)
    } else if blur {
      selectedFilter = .blurredBackground
    } else {
      selectedFilter = nil
    }
  }


  public func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
    let currentTimestamp = frame.timeStampNs
    let elapsedTimeSinceLastProcessedFrame = currentTimestamp - lastProcessedTimestamp

    if elapsedTimeSinceLastProcessedFrame < fpsInterval {
      return
    }

    Task { [serialActor, weak self] in
      do {
        try await serialActor.execute { [weak self] in
          guard let self else { return }

          var _buffer: RTCCVPixelBuffer?

          if self.selectedFilter != nil, let buffer: RTCCVPixelBuffer = frame.buffer as? RTCCVPixelBuffer {
            _buffer = buffer
            let imageBuffer = buffer.pixelBuffer
            CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
            let inputImage = CIImage(cvPixelBuffer: imageBuffer, options: [CIImageOption.colorSpace: self.colorSpace])
            let outputImage = await self.filter(image: inputImage, pixelBuffer: imageBuffer)
            CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
            self.context.render(outputImage, to: imageBuffer, bounds: outputImage.extent, colorSpace: self.colorSpace)
          }

          let updatedFrame = self.handleRotation
          ? self.adjustRotation(capturer, for: _buffer, frame: frame)
          : frame

          self.lastProcessedTimestamp = currentTimestamp

          if updatedFrame.timeStampNs <= self.latestTimestampNs {
            return
          }

          self.latestTimestampNs = updatedFrame.timeStampNs
          self.source.capturer(capturer, didCapture: updatedFrame)
        }
      } catch {
        print(error)
      }
    }
  }

  private func adjustRotation(
    _ capturer: RTCVideoCapturer,
    for buffer: RTCCVPixelBuffer?,
    frame: RTCVideoFrame
  ) -> RTCVideoFrame {
#if os(macOS) || targetEnvironment(macCatalyst)
    var rotation = RTCVideoRotation._0
#else
    var rotation = RTCVideoRotation._90
    switch sceneOrientation {
    case let .portrait(isUpsideDown):
      rotation = isUpsideDown ? ._270 : ._90
    case let .landscape(isLeft):
      switch (isLeft, currentCameraPosition == .front) {
      case (true, true):
        rotation = ._0
      case (true, false):
        rotation = ._180
      case (false, true):
        rotation = ._180
      case (false, false):
        rotation = ._0
      }
    }
#endif
    if rotation != frame.rotation, let _buffer = buffer ?? frame.buffer as? RTCCVPixelBuffer {
      return RTCVideoFrame(buffer: _buffer, rotation: rotation, timeStampNs: frame.timeStampNs)
    } else if rotation != frame.rotation, buffer == nil {
      return frame
    } else {
      return frame
    }
  }

  private func filter(
    image: CIImage,
    pixelBuffer: CVPixelBuffer
  ) async -> CIImage {
    await selectedFilter?.filter(
      VideoFilter.Input(
        originalImage: image,
        originalPixelBuffer: pixelBuffer,
        originalImageOrientation: sceneOrientation.cgOrientation
      )
    ) ?? CIImage()
  }
}


actor SerialActor {
  private var previousTask: Task<Void, Error>?

  func execute(_ block: @Sendable @escaping () async throws -> Void) async throws {
    let task = Task { [previousTask] in
      _ = await previousTask?.result
      return try await block()
    }

    previousTask = task

    try await task.value
  }
}

enum StreamDeviceOrientation: Equatable {
  case portrait(isUpsideDown: Bool)
  case landscape(isLeft: Bool)

  var isPortrait: Bool {
    switch self {
    case .landscape:
      return false
    case .portrait:
      return true
    }
  }

  var isLandscape: Bool {
    switch self {
    case .landscape:
      return true
    case .portrait:
      return false
    }
  }

  var cgOrientation: CGImagePropertyOrientation {
    switch self {
    case let .portrait(isUpsideDown):
      return isUpsideDown ?.right : .left
    case let .landscape(isLeft):
      return isLeft ? .up : .down
    }
  }
}
