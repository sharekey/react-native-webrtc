#import <objc/runtime.h>

#import <React/RCTBridge.h>
#import <React/RCTBridgeModule.h>

#import "WebRTCModule.h"
#import "WebRTCAudioSession.h"

@implementation WebRTCModule (RTCAudioSession)
RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(unlockPeerClosing) {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    WebRTCAudioSession* session = [WebRTCAudioSession shared];
    [session setAudioSessionEnabled:NO];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"dev_menu_logs" object:@{
      @"append": @YES,
      @"log": [NSString stringWithFormat:@"unlockPeerClosing: time %.3f ms", (CFAbsoluteTimeGetCurrent() - start) * 1000],
      @"key": @"Call End Time Elapsed"
    }];
    return nil;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(lockPeerClosing) {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();

    WebRTCAudioSession* session = [WebRTCAudioSession shared];
    [session setAudioSessionEnabled:YES];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"dev_menu_logs" object:@{
      @"append": @YES,
      @"log": [NSString stringWithFormat:@"lockPeerClosing: time %.3f ms", (CFAbsoluteTimeGetCurrent() - start) * 1000],
      @"key": @"Call End Time Elapsed"
    }];
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
