#import <objc/runtime.h>

#import <React/RCTBridge.h>
#import <React/RCTBridgeModule.h>

#import "WebRTCModule.h"
#import "WebRTCAudioSession.h"

@implementation WebRTCModule (RTCAudioSession)
RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(unlockPeerClosing) {
    WebRTCAudioSession* session = [WebRTCAudioSession shared];
    [session setAudioSessionEnabled:NO];
    return nil;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(lockPeerClosing) {
    WebRTCAudioSession* session = [WebRTCAudioSession shared];
    [session setAudioSessionEnabled:YES];
    return nil;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(audioSessionDidActivate) {
    [[RTCAudioSession sharedInstance] audioSessionDidActivate:[AVAudioSession sharedInstance]];
    return nil;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(audioSessionDidDeactivate) {
    [[RTCAudioSession sharedInstance] audioSessionDidDeactivate:[AVAudioSession sharedInstance]];
    return nil;
}

@end
