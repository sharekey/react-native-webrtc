//
//  VideoSourceInterceptor.h
//  RCTWebRTC
//
//  Created by Vasil' on 26.12.22.
//

#import <Foundation/Foundation.h>
#import <WebRTC/RTCVideoSource.h>

NS_ASSUME_NONNULL_BEGIN

@interface VideoSourceInterceptor : NSObject<RTCVideoCapturerDelegate>

@property(nonatomic, strong) RTCVideoSource *videoSource;

- (instancetype)initWithVideoSource: (RTCVideoSource*) videoSource;

@end

NS_ASSUME_NONNULL_END
