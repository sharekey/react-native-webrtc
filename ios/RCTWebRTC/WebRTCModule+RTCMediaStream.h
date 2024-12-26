#import "CaptureController.h"
#import "WebRTCModule.h"
#import "react_native_webrtc-Swift.h"

@interface WebRTCModule (RTCMediaStream)
- (RTCVideoTrack *)createVideoTrackWithCaptureController:
    (CaptureController * (^)(RTCVideoSource *))captureControllerCreator;
- (NSArray *)createMediaStream:(NSArray<RTCMediaStreamTrack *> *)tracks;
@end
