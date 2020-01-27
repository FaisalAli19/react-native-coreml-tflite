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
    console.log(CoreMLImageNative);
    return (
      <CoreMLImageNative
        modelFile={this.props.modelFile}
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
