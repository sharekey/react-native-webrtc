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

    outgoingVoicePublisher.removeDuplicates(by: { $0.0?.reactTag == $1.0?.reactTag && $0.1 == $1.1 }).sink { (peer, isSpeaking, audioLevel) in
      guard let peer else { return }
      voiceClosure(peer, true, isSpeaking, audioLevel)
    }.store(in: &disposeBag)

    incomingVoicePublisher.removeDuplicates(by: { $0.0?.reactTag == $1.0?.reactTag && $0.1 == $1.1 }).sink { (peer, isSpeaking, audioLevel) in
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
    let checkInterval: Double = 0.3

    var silenceIncomingCount: [NSNumber: Double] = [:]
    var silenceOutgoingCount: Double = 0

    peerConnections.forEach {
      silenceIncomingCount[$0.reactTag] = 0
    }

    while !Task.isCancelled {
      do {
        peerConnections.forEach { [weak self] peerConnection in
          guard let self = self else { return }

          if peerConnection.connectionState == .connected {
            peerConnection.receivers.forEach {
              if $0.track?.kind == "audio" {
                peerConnection.statistics(for: $0) { stats in
                  for statistic in stats.statistics.values {
                    if statistic.type == "inbound-rtp" {
                      guard let audioLevel = statistic.values["audioLevel"] as? Double else { return }

                      if audioLevel > 0.025 {
                        silenceIncomingCount[peerConnection.reactTag] = 0
                        self.incomingVoicePublisher.send((peerConnection, true, audioLevel))
                      } else {
                        let count = silenceIncomingCount[peerConnection.reactTag] ?? 0
                        silenceIncomingCount[peerConnection.reactTag] = count + 1

                        if count > 4 {
                          self.incomingVoicePublisher.send((peerConnection, false, audioLevel))
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }

        if let peerConnection = peerConnections.first(where: { $0.connectionState == .connected }) {
          peerConnection.senders.forEach {
            if $0.track?.kind == "audio" {
              peerConnection.statistics(for: $0) { stats in
                for statistic in stats.statistics.values {
                  if statistic.type == "media-source" {
                    guard let audioLevel = statistic.values["audioLevel"] as? Double else { return }
                    if audioLevel > 0.01 {
                      silenceOutgoingCount = 0
                      self.outgoingVoicePublisher.send((peerConnection, true, audioLevel))
                    } else {
                      silenceOutgoingCount += 1

                      if silenceOutgoingCount > 4 {
                        self.outgoingVoicePublisher.send((peerConnection, false, audioLevel))
                      }
                    }
                  }
                }
              }
            }
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
  private let source: RTCVideoCapturerDelegate
  private let context = CIContext(options: [.useSoftwareRenderer: false])
  private let colorSpace = CGColorSpaceCreateDeviceRGB()
  private let processingQueue = DispatchQueue(label: "com.sharekey.webrtc.background-effect", qos: .userInitiated)
  private let frameGate = CaptureFrameGate()
  private let filterLock = NSLock()
  private var selectedFilter: VideoFilter?
  private var pixelBufferPool: CVPixelBufferPool?
  private var poolWidth = 0
  private var poolHeight = 0

  @objc
  public init(source: RTCVideoCapturerDelegate, backgroundImageData: Data?) {
    self.source = source
    super.init()
    enable(blur: false, backgroundImageData: backgroundImageData)
  }

  @objc
  public func enable(blur: Bool, backgroundImageData: Data?) {
    let filter: VideoFilter?
    if let data = backgroundImageData, let image = CIImage(data: data) {
      filter = .imageBackground(image)
    } else {
      filter = blur ? .blurredBackground : nil
    }
    filterLock.lock()
    selectedFilter = filter
    filterLock.unlock()
  }

  public func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
    filterLock.lock()
    let filter = selectedFilter
    filterLock.unlock()

    guard frameGate.tryBegin(
      timestampNs: frame.timeStampNs,
      minimumIntervalNs: filter == nil ? 0 : CaptureFrameGate.effectFrameIntervalNs
    ) else { return }

    processingQueue.async { [self] in
      defer { frameGate.finish() }
      autoreleasepool {
        let output = filter.map { process(frame, filter: $0) } ?? frame
        source.capturer(capturer, didCapture: output)
      }
    }
  }

  private func process(_ frame: RTCVideoFrame, filter: VideoFilter) -> RTCVideoFrame {
    guard let buffer = frame.buffer as? RTCCVPixelBuffer else { return frame }
    let pixelBuffer = buffer.pixelBuffer
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    guard let outputBuffer = makeOutputBuffer(width: width, height: height) else { return frame }

    let image = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: colorSpace])
    let result = filter.apply(to: image, rotationDegrees: frame.rotation.rawValue)
    // Rendering in place aliases the input CIImage and may corrupt the camera's shared buffer.
    context.render(result, to: outputBuffer, bounds: image.extent, colorSpace: colorSpace)
    let output = RTCCVPixelBuffer(
      pixelBuffer: outputBuffer,
      adaptedWidth: buffer.width,
      adaptedHeight: buffer.height,
      cropWidth: buffer.cropWidth,
      cropHeight: buffer.cropHeight,
      cropX: buffer.cropX,
      cropY: buffer.cropY
    )
    return RTCVideoFrame(buffer: output, rotation: frame.rotation, timeStampNs: frame.timeStampNs)
  }

  private func makeOutputBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    if pixelBufferPool == nil || poolWidth != width || poolHeight != height {
      pixelBufferPool = nil
      let attributes: [String: Any] = [
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ]
      guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pixelBufferPool) == kCVReturnSuccess else {
        return nil
      }
      poolWidth = width
      poolHeight = height
    }
    guard let pool = pixelBufferPool else { return nil }
    var output: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess else { return nil }
    return output
  }
}
