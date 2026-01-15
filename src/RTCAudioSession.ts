import { NativeModules, Platform } from 'react-native';

const { WebRTCModule } = NativeModules;

export default class RTCAudioSession {
    /**
     * To be called when close peer connection to fix issue with no mic sound in group call when
     */
    static unlockPeerClosing() {
        // Only valid for iOS
        if (Platform.OS === 'ios') {
            WebRTCModule.unlockPeerClosing();
        }
    }

    /**
     * To be called when peer connection closed to fix issue with no mic sound in group call when
     */
    static lockPeerClosing() {
        // Only valid for iOS
        if (Platform.OS === 'ios') {
            WebRTCModule.lockPeerClosing();
        }
    }

    /**
     * To be called when CallKit activates the audio session.
     */
    static audioSessionDidActivate() {
        // Only valid for iOS
        if (Platform.OS === 'ios') {
            WebRTCModule.audioSessionDidActivate();
        }
    }

    /**
     * To be called when CallKit deactivates the audio session.
     */
    static audioSessionDidDeactivate() {
        // Only valid for iOS
        if (Platform.OS === 'ios') {
            WebRTCModule.audioSessionDidDeactivate();
        }
    }
}
