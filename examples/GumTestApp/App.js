/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 * @flow strict-local
 */

import React, {useState, useCallback} from 'react';
import {
  Button,
  SafeAreaView,
  StyleSheet,
  ScrollView,
  View,
  Text,
  Switch,
  TextInput,
  StatusBar,
} from 'react-native';
import { Colors } from 'react-native/Libraries/NewAppScreen';
import { mediaDevices, RTCView } from 'react-native-webrtc';

const App: () => React$Node = () => {
  const [stream, setStream] = useState(null);
  const [frameRate, setFramerate] = useState('30');
  const [qualityWidth, setQualityWidth] = useState('1280');
  const [qualityHeight, setQualityHeght] = useState('720');
  const [enableBlurBackgroud, setEnableBlurBackground] = useState(false);

  const start = useCallback(async () => {
    console.log('start');
    if (!stream) {
      let s;
      try {
        s = await mediaDevices.getUserMedia({ video: { 
            width: +qualityWidth,
            height: +qualityHeight,
            frameRate: +frameRate,
            ...enableBlurBackgroud && {
                enableBlurBackgroud: true,
            },
            ...!enableBlurBackgroud && {
                enableVirtualBackgroud: true,
            },
        } });
        setStream(s);
      } catch(e) {
        console.error(e);
      }
    }
  }, [stream, frameRate, qualityWidth, qualityHeight, enableBlurBackgroud]);
  const stop = useCallback(() => {
    console.log('stop');
    if (stream) {
      stream.release();
      setStream(null);
    }
  }, [stream]);

  return (
    <>
      <StatusBar barStyle="dark-content" />
      <SafeAreaView style={styles.body}>
      {
        stream &&
          <RTCView
            streamURL={stream.toURL()}
            style={styles.stream} />
      }
        <View
          style={styles.footer}>
            <View style={styles.controlls}>
                <TextInput
                // placeholder='frameRate'
                keyboardType='numeric'
                value={frameRate}
                onChangeText={setFramerate}
                />
                <TextInput
                // placeholder='width'
                keyboardType='numeric'
                value={qualityWidth}
                onChangeText={setQualityWidth}
                />
                <TextInput
                // placeholder='height'
                keyboardType='numeric'
                value={qualityHeight}
                onChangeText={setQualityHeght}
                />
                <Switch
                value={enableBlurBackgroud}
                onValueChange={setEnableBlurBackground}
                />
            </View>
          <Button
            title = "Start"
            onPress = {start} />
          <Button
            title = "Stop"
            onPress = {stop} />
        </View>
      </SafeAreaView>
    </>
  );
};

const styles = StyleSheet.create({
  body: {
    backgroundColor: Colors.white,
    ...StyleSheet.absoluteFill
  },
  stream: {
    flex: 1
  },
  footer: {
    backgroundColor: Colors.lighter,
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0
  },
  controlls: {
    flexDirection: 'row',
    paddingHorizontal: 30,
    width: '100%',
    justifyContent: 'space-between',
  },
});

export default App;
