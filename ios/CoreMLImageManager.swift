//
//  CoreMLImageManager.swift
//  ReactNativeCoremlTflite
//
//  Created by Faisal on 1/5/20.
//  Copyright © 2020 Facebook. All rights reserved.
//

import Foundation
@available(iOS 11.0, *)
@objc(CoreMLImageManager)
class CoreMLImageManager: RCTViewManager {
  
  override func view() -> UIView! {
    return CoreMLImage();
  }
  
  override static func requiresMainQueueSetup() -> Bool {
    return true
  }
  
}
