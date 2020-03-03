import React, { Component } from 'react';
import {
  StyleSheet,
  Text,
  requireNativeComponent,
  Dimensions,
  View
} from 'react-native';

const CoreMLImageNative = requireNativeComponent('CoreMLImage', null);

export default class CoreMLImageView extends Component {
  onClassification(evt) {
    const { onClassification } = this.props;
    if (onClassification) {
      onClassification(evt.nativeEvent.Classification);
    }
  }

  render() {
    const { modelFile, isquant, inputDimension } = this.props;
    return (
      <CoreMLImageNative
        modelFile={modelFile}
        isquant={isquant}
        inputDimension={inputDimension}
        onClassification={evt => this.onClassification(evt)}
        style={{
          width: Dimensions.get('window').width,
          height: Dimensions.get('window').height
        }}
      >
        <View style={localStyles.overlay}>{this.props.children}</View>
      </CoreMLImageNative>
    );
  }
}

const localStyles = StyleSheet.create({
  overlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 999,
    backgroundColor: 'transparent'
  }
});
