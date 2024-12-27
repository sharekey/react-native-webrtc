import { NativeModules } from 'react-native';

const { WebRTCModule } = NativeModules;

export interface Constraints {
    enableBlurBackgroud?: boolean;
    backgroundImageBase64?: string | null;
    enableVirtualBackgroud?: boolean;
}

export default function changeBackgroundEffect(constraints: Constraints = {}): Promise<void> {
    return new Promise((resolve, reject) => {
        return WebRTCModule.changeBackgroundEffect(constraints, (data) => {                
            resolve(data);
        }, (error) => {
            reject(error);
        });
    });
};
