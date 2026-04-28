package com.oney.WebRTCModule;

import android.util.Base64;

import androidx.annotation.Nullable;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.WritableMap;

import org.webrtc.DataChannel;

import java.nio.charset.StandardCharsets;

class DataChannelWrapper implements DataChannel.Observer {
    private final String reactTag;
    private final DataChannel mDataChannel;
    private final int peerConnectionId;
    private final WebRTCModule webRTCModule;

    DataChannelWrapper(WebRTCModule webRTCModule, int peerConnectionId, String reactTag, DataChannel dataChannel) {
        this.webRTCModule = webRTCModule;
        this.peerConnectionId = peerConnectionId;
        this.reactTag = reactTag;
        mDataChannel = dataChannel;
    }

    public DataChannel getDataChannel() {
        return mDataChannel;
    }

    public String getReactTag() {
        return reactTag;
    }

    @Nullable
    public String dataChannelStateString(DataChannel.State dataChannelState) {
        switch (dataChannelState) {
            case CONNECTING:
                return "connecting";
            case OPEN:
                return "open";
            case CLOSING:
                return "closing";
            case CLOSED:
                return "closed";
        }
        return null;
    }

    @Override
    public void onBufferedAmountChange(long amount) {
        WritableMap params = Arguments.createMap();
        params.putString("reactTag", reactTag);
        params.putInt("peerConnectionId", peerConnectionId);
        params.putDouble("bufferedAmount", Long.valueOf(amount).doubleValue());

        webRTCModule.sendEvent("dataChannelDidChangeBufferedAmount", params);
    }

    @Override
    public void onMessage(DataChannel.Buffer buffer) {
        final byte[] copiedBytes;
        try {
            if (buffer.data.hasArray()) {
                int offset = buffer.data.arrayOffset() + buffer.data.position();
                int length = buffer.data.remaining();
                copiedBytes = new byte[length];
                System.arraycopy(buffer.data.array(), offset, copiedBytes, 0, length);
            } else {
                copiedBytes = new byte[buffer.data.remaining()];
                buffer.data.get(copiedBytes);
            }
        } finally {
            buffer.data.rewind();
        }

        ThreadUtils.runOnExecutor(() -> {
            WritableMap params = Arguments.createMap();
            params.putString("reactTag", reactTag);
            params.putInt("peerConnectionId", peerConnectionId);

            String type = "text";
            String data = new String(copiedBytes, StandardCharsets.UTF_8);
            params.putString("type", type);
            params.putString("data", data);

            webRTCModule.sendEvent("dataChannelReceiveMessage", params);
        });
    }

    @Override
    public void onStateChange() {
        WritableMap params = Arguments.createMap();
        params.putString("reactTag", reactTag);
        params.putInt("peerConnectionId", peerConnectionId);
        params.putInt("id", mDataChannel.id());
        params.putString("state", dataChannelStateString(mDataChannel.state()));

        webRTCModule.sendEvent("dataChannelStateChanged", params);
    }
}
