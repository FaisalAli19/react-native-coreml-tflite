//
//  ReactNativeCoremlTflite.swift
//  ReactNativeCoremlTflite
//
//  Created by Faisal on 1/5/20.
//  Copyright © 2020 Facebook. All rights reserved.
//

import Foundation
import UIKit
import CoreML
import AVFoundation
import TensorFlowLite
import Accelerate

/// Stores results for a particular frame that was successfully run through the `Interpreter`.
struct Result {
  let inferenceTime: Double
  let inferences: [Inference]
}

/// Stores one formatted inference.
struct Inference {
  let confidence: Float
  let className: String
  let rect: CGRect
  let displayColor: UIColor
}

@available(iOS 11.0, *)
@objc(CoreMLImage)
public class CoreMLImage: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
  
    
  var bridge: RCTEventDispatcher!
  var captureSession: AVCaptureSession?
  var videoPreviewLayer: AVCaptureVideoPreviewLayer?
  var lastClassification: String = ""
  var onClassification: RCTBubblingEventBlock?
    
    var threadCount: Int = 3
    let threadCountLimit = 10
    
  // MARK: Model parameters
   let batchSize = 1
   let inputChannels = 3
   private var inputWidth = 300
   private var inputHeight = 300
    let threshold: Float = 0.5
//    var model: String;
//
    private var interpreter: Interpreter?
    // MARK: Private properties
    private var labels: [String] = []
    private var isQuant: Bool = false

    private let bgraPixel = (channels: 4, alphaComponent: 3, lastBgrComponent: 2)
    private let rgbPixelChannels = 3
    private let colorStrideValue = 10
    private let colors = [
      UIColor.red,
      UIColor(displayP3Red: 90.0/255.0, green: 200.0/255.0, blue: 250.0/255.0, alpha: 1.0),
      UIColor.green,
      UIColor.orange,
      UIColor.blue,
      UIColor.purple,
      UIColor.magenta,
      UIColor.yellow,
      UIColor.cyan,
      UIColor.brown
    ]
    
    required public init(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)!
  }
    
  override init(frame: CGRect) {
    super.init(frame: frame)
    self.frame = frame;
  }
    
  @objc(setModelFile:) public func setModelFile(modelFile: String) {
    
      print("Setting model file to: " + modelFile)
      
      guard let modelPath = Bundle.main.path(
        forResource: modelFile,
        ofType: nil
      ) else {
        print("Failed to load the model file with name: \(modelFile).")
        return
      }
    
    guard let labelFileUrl = Bundle.main.url(forResource: "label", withExtension: "txt") else {
      fatalError("Labels file not found in bundle. Please add a labels file with name label.txt")
    }
    
    do {
      let contents = try String(contentsOf: labelFileUrl, encoding: .utf8)
      labels = contents.components(separatedBy: .newlines)
    } catch {
      fatalError("Labels file named label.txt cannot be read. Please add a valid labels file and try again.")
    }
      
      // Specify the options for the `Interpreter`.
      self.threadCount = 3
      var options = InterpreterOptions()
      options.threadCount = threadCount
      do {
        // Create the `Interpreter`.
        interpreter = try Interpreter(modelPath: modelPath, options: options)
        // Allocate memory for the model's input `Tensor`s.
        try interpreter?.allocateTensors()
      } catch let error {
        print("Failed to create the interpreter with error: \(error.localizedDescription)")
      }
    
    }
    
    @objc(setIsquant:) public func setIsquant(isquant: Bool) {
        print("Is quantisized is: \(isquant)")
        self.isQuant = isquant;
    }
    
    @objc(setInputDimension:) public func setInputDimension(inputDimension: Int) {
        print("Input dimension: \(inputDimension)")
        self.inputWidth = inputDimension
        self.inputHeight = inputDimension
    }
  
  func capture(_ captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAt fileURL: URL!, fromConnections connections: [Any]!) {
  }
  
  public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    // Converts the CMSampleBuffer to a CVPixelBuffer.
    let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!

    let imagePixelBuffer = pixelBuffer

    // Delegates the pixel buffer to the ViewController.
    runMachineLearning(pixelBuffer: imagePixelBuffer)
//    let img = self.imageFromSampleBuffer(sampleBuffer: sampleBuffer)
//    runMachineLearning(img: img)
  }
    
    
  
  func runMachineLearning(pixelBuffer: CVPixelBuffer) {
    let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
    let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
     let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
      assert(sourcePixelFormat == kCVPixelFormatType_32ARGB ||
               sourcePixelFormat == kCVPixelFormatType_32BGRA ||
                 sourcePixelFormat == kCVPixelFormatType_32RGBA)
    let imageChannels = 4
    assert(imageChannels >= inputChannels)
    
    // Crops the image to the biggest square in the center and scales it down to model dimensions.
     let scaledSize = CGSize(width: inputWidth, height: inputHeight)
    guard let scaledPixelBuffer = pixelBuffer.resized(to: scaledSize) else {
        fatalError("Unable to resize the image")
     }
    
    let interval: TimeInterval
    let outputBoundingBox: Tensor
    let outputClasses: Tensor
    let outputScores: Tensor
    let outputCount: Tensor
    
    do {
        let inputTensor = try interpreter?.input(at: 0)

      // Remove the alpha component from the image buffer to get the RGB data.
      guard let rgbData = rgbDataFromBuffer(
        scaledPixelBuffer,
        byteCount: batchSize * inputWidth * inputHeight * inputChannels,
        isModelQuantized: isQuant
      ) else {
        print("Failed to convert the image buffer to RGB data.")
        return
      }

      // Copy the RGB data to the input `Tensor`.
        try interpreter?.copy(rgbData, toInputAt: 0)

      // Run inference by invoking the `Interpreter`.
      let startDate = Date()
        try interpreter?.invoke()
      interval = Date().timeIntervalSince(startDate) * 1000

      outputBoundingBox = try (interpreter?.output(at: 0))!
        outputClasses = try (interpreter?.output(at: 1))!
        outputScores = try (interpreter?.output(at: 2))!
        outputCount = try (interpreter?.output(at: 3))!
        
        // Formats the results
           let resultArray = formatResults(
            boundingBox: [Float](unsafeData: outputBoundingBox.data) ?? [],
            outputClasses: [Float](unsafeData: outputClasses.data) ?? [],
             outputScores: [Float](unsafeData: outputScores.data) ?? [],
             outputCount: Int(([Float](unsafeData: outputCount.data) ?? [0])[0]),
             width: CGFloat(imageWidth),
             height: CGFloat(imageHeight)
           )
        var classificationArray = [Dictionary<String, Any>]()
           // Returns the inference time and inferences
    resultArray.forEach{classification in
        classificationArray.append(["confidence": classification.confidence, "className": classification.className, "rect": classification.rect, "displayColor": classification.displayColor])
    
    }
             self.onClassification!(["Classification": classificationArray])
    } catch let error {
      print("Failed to invoke the interpreter with error: \(error.localizedDescription)")
    }

  }
    
    func formatResults(boundingBox: [Float], outputClasses: [Float], outputScores: [Float], outputCount: Int, width: CGFloat, height: CGFloat) -> [Inference]{
      var resultsArray: [Inference] = []
      if (outputCount == 0) {
        return resultsArray
      }
      for i in 0...outputCount - 1 {

        let score = outputScores[i]

        // Filters results with confidence < threshold.
        guard score >= threshold else {
          continue
        }
        
        let outputClassIndex = Int(outputClasses[i])
        let outputClass = labels[outputClassIndex + 1]
        
        var rect: CGRect = CGRect.zero
        
        // Translates the detected bounding box to CGRect.
        rect.origin.y = CGFloat(boundingBox[4*i])
        rect.origin.x = CGFloat(boundingBox[4*i+1])
        rect.size.height = CGFloat(boundingBox[4*i+2]) - rect.origin.y
        rect.size.width = CGFloat(boundingBox[4*i+3]) - rect.origin.x
        
         let newRect = rect.applying(CGAffineTransform(scaleX: width, y: height))
        
        let colorToAssign = colorForClass(withIndex: outputClassIndex + 1)
        
        let inference = Inference(confidence: score,
        className: outputClass,
        rect: newRect,
        displayColor: colorToAssign)
        resultsArray.append(inference)
      }

      // Sort results in descending order of confidence.
      resultsArray.sort { (first, second) -> Bool in
        return first.confidence  > second.confidence
      }

      return resultsArray
    }
  
//  func processClassifications(for request: VNRequest, error: Error?) {
//    DispatchQueue.main.async {
//        guard let results = request.results else {
//          print("Unable to classify image")
//          print(error!.localizedDescription)
//          return
//        }
//
//        let classifications = results as! [VNClassificationObservation]
//
//        var classificationArray = [Dictionary<String, Any>]()
//
//        classifications.forEach{classification in
//          classificationArray.append(["identifier": classification.identifier, "confidence": classification.confidence])
//
//        }
//
//        self.onClassification!(["classifications": classificationArray])
//
//      }
//
//  }
  
//  func imageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> CIImage
//  {
//    let imageBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
//
//    let ciimage : CIImage = CIImage(cvPixelBuffer: imageBuffer)
//    return ciimage
//  }
  
  override public func layoutSubviews() {
    super.layoutSubviews()
    let view = UIView(frame: CGRect(x: 0, y: 0, width: self.frame.width,
                                    height: self.frame.height))
    
    let captureDevice = AVCaptureDevice.default(for: .video)
    
    do {
      if (captureDevice != nil) {
        let input = try AVCaptureDeviceInput(device: captureDevice!)
        self.captureSession = AVCaptureSession()
        self.captureSession?.addInput(input)
        
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession!)
        videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        videoPreviewLayer?.frame = view.layer.bounds
        
        view.layer.addSublayer(videoPreviewLayer!)
        self.addSubview(view)
        
        let videoDataOutput = AVCaptureVideoDataOutput()
        let queue = DispatchQueue(label: "xyz.jigswaw.ml.queue")
        videoDataOutput.setSampleBufferDelegate(self, queue: queue)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
    videoDataOutput.videoSettings = [ String(kCVPixelBufferPixelFormatTypeKey) : kCMPixelFormat_32BGRA]
        guard (self.captureSession?.canAddOutput(videoDataOutput))! else {
          fatalError()
        }
        self.captureSession?.addOutput(videoDataOutput)
        self.captureSession?.startRunning()
      }
      
    } catch {
      print(error)
    }
    
  }
  
  
  @objc(setOnClassification:) public func setOnClassification(onClassification: @escaping RCTBubblingEventBlock) {
    self.onClassification = onClassification
  }
    
    private func rgbDataFromBuffer(
       _ buffer: CVPixelBuffer,
       byteCount: Int,
       isModelQuantized: Bool
     ) -> Data? {
       CVPixelBufferLockBaseAddress(buffer, .readOnly)
       defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
       guard let sourceData = CVPixelBufferGetBaseAddress(buffer) else {
         return nil
       }
        assert(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA)
//        let count = CVPixelBufferGetDataSize(buffer)
//        let bufferData = Data(bytesNoCopy: sourceData, count: count, deallocator: .none)
//        var rgbBytes = [UInt8](repeating: 0, count: byteCount)
//        var pixelIndex = 0
//
//        for component in bufferData.enumerated() {
//          let bgraComponent = component.offset % bgraPixel.channels;
//          let isAlphaComponent = bgraComponent == bgraPixel.alphaComponent;
//          guard !isAlphaComponent else {
//            pixelIndex += 1
//            continue
//          }
//          // Swizzle BGR -> RGB.
//
//          let rgbIndex = pixelIndex * rgbPixelChannels + (bgraPixel.lastBgrComponent - bgraComponent)
//          if(rgbIndex >= 0 && rgbIndex < byteCount){
//          rgbBytes[rgbIndex] = component.element
//          }
//        }
//
//        if isModelQuantized { return Data(bytes: rgbBytes) }
//        return Data(copyingBufferOf: rgbBytes.map { Float($0) / 255.0 })
        
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let destinationChannelCount = 3
        let destinationBytesPerRow = destinationChannelCount * width
//
        var sourceBuffer = vImage_Buffer(data: sourceData,
             height: vImagePixelCount(height),
             width: vImagePixelCount(width),
             rowBytes: sourceBytesPerRow)
//
        guard let destinationData = malloc(height * destinationBytesPerRow) else {
          print("Error: out of memory")
          return nil
        }
//
        defer {
          free(destinationData)
        }
//
        var destinationBuffer = vImage_Buffer(data: destinationData,
        height: vImagePixelCount(height),
        width: vImagePixelCount(width),
        rowBytes: destinationBytesPerRow)
//
        if (CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA){
          vImageConvert_BGRA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
        } else if (CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32ARGB) {
          vImageConvert_ARGB8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
        }
//
        let byteData = Data(bytes: destinationBuffer.data, count: destinationBuffer.rowBytes * height)
        if isModelQuantized {
          return byteData
        }
//
        // Not quantized, convert to floats
        let bytes = Array<UInt8>(unsafeData: byteData)!
        var floats = [Float]()
        for i in 0..<bytes.count {
          floats.append(Float(bytes[i]) / 255.0)
        }
        return Data(copyingBufferOf: floats)
//
     }
    
    private func colorForClass(withIndex index: Int) -> UIColor {

      // We have a set of colors and the depending upon a stride, it assigns variations to of the base
      // colors to each object based on its index.
      let baseColor = colors[index % colors.count]

      var colorToAssign = baseColor

      let percentage = CGFloat((colorStrideValue / 2 - index / colors.count) * colorStrideValue)

      if let modifiedColor = baseColor.getModified(byPercentage: percentage) {
        colorToAssign = modifiedColor
      }

      return colorToAssign
    }
  
    /// This assigns color for a particular class.
//    private func colorForClass(withIndex index: Int) -> UIColor {
//
//      // We have a set of colors and the depending upon a stride, it assigns variations to of the base
//      // colors to each object based on its index.
//      let baseColor = colors[index % colors.count]
//
//      var colorToAssign = baseColor
//
//      let percentage = CGFloat((colorStrideValue / 2 - index / colors.count) * colorStrideValue)
//
//      if let modifiedColor = baseColor.getModified(byPercentage: percentage) {
//        colorToAssign = modifiedColor
//      }
//
//      return colorToAssign
//    }
  
}

// MARK: - Extensions

extension Data {
  /// Creates a new buffer by copying the buffer pointer of the given array.
  ///
  /// - Warning: The given array's element type `T` must be trivial in that it can be copied bit
  ///     for bit with no indirection or reference-counting operations; otherwise, reinterpreting
  ///     data from the resulting buffer has undefined behavior.
  /// - Parameter array: An array with elements of type `T`.
  init<T>(copyingBufferOf array: [T]) {
    self = array.withUnsafeBufferPointer(Data.init)
  }
}

extension Array {
  /// Creates a new array from the bytes of the given unsafe data.
  ///
  /// - Warning: The array's `Element` type must be trivial in that it can be copied bit for bit
  ///     with no indirection or reference-counting operations; otherwise, copying the raw bytes in
  ///     the `unsafeData`'s buffer to a new array returns an unsafe copy.
  /// - Note: Returns `nil` if `unsafeData.count` is not a multiple of
  ///     `MemoryLayout<Element>.stride`.
  /// - Parameter unsafeData: The data containing the bytes to turn into an array.
  init?(unsafeData: Data) {
    guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
    #if swift(>=5.0)
    self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
    #else
    self = unsafeData.withUnsafeBytes {
      .init(UnsafeBufferPointer<Element>(
        start: $0,
        count: unsafeData.count / MemoryLayout<Element>.stride
      ))
    }
    #endif  // swift(>=5.0)
  }
}

@available(iOS 10.0, *)
extension UIColor {

  /**
 This method returns colors modified by percentage value of color represented by the current object.
 */
  func getModified(byPercentage percent: CGFloat) -> UIColor? {

    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat = 0.0

    guard self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return nil
    }

    // Returns the color comprised by percentage r g b values of the original color.
    let colorToReturn = UIColor(displayP3Red: min(red + percent / 100.0, 1.0), green: min(green + percent / 100.0, 1.0), blue: min(blue + percent / 100.0, 1.0), alpha: 1.0)

    return colorToReturn
  }
}

extension CVPixelBuffer {
  /// Returns thumbnail by cropping pixel buffer to biggest square and scaling the cropped image
  /// to model dimensions.
  func resized(to size: CGSize ) -> CVPixelBuffer? {

    let imageWidth = CVPixelBufferGetWidth(self)
    let imageHeight = CVPixelBufferGetHeight(self)

    let pixelBufferType = CVPixelBufferGetPixelFormatType(self)

    assert(pixelBufferType == kCVPixelFormatType_32BGRA)

    let inputImageRowBytes = CVPixelBufferGetBytesPerRow(self)
    let imageChannels = 4

    CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))

    // Finds the biggest square in the pixel buffer and advances rows based on it.
    guard let inputBaseAddress = CVPixelBufferGetBaseAddress(self) else {
      return nil
    }

    // Gets vImage Buffer from input image
    var inputVImageBuffer = vImage_Buffer(data: inputBaseAddress, height: UInt(imageHeight), width: UInt(imageWidth), rowBytes: inputImageRowBytes)

    let scaledImageRowBytes = Int(size.width) * imageChannels
    guard  let scaledImageBytes = malloc(Int(size.height) * scaledImageRowBytes) else {
      return nil
    }

    // Allocates a vImage buffer for scaled image.
    var scaledVImageBuffer = vImage_Buffer(data: scaledImageBytes, height: UInt(size.height), width: UInt(size.width), rowBytes: scaledImageRowBytes)

    // Performs the scale operation on input image buffer and stores it in scaled image buffer.
    let scaleError = vImageScale_ARGB8888(&inputVImageBuffer, &scaledVImageBuffer, nil, vImage_Flags(0))

    CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))

    guard scaleError == kvImageNoError else {
      return nil
    }

    let releaseCallBack: CVPixelBufferReleaseBytesCallback = {mutablePointer, pointer in

      if let pointer = pointer {
        free(UnsafeMutableRawPointer(mutating: pointer))
      }
    }

    var scaledPixelBuffer: CVPixelBuffer?

    // Converts the scaled vImage buffer to CVPixelBuffer
    let conversionStatus = CVPixelBufferCreateWithBytes(nil, Int(size.width), Int(size.height), pixelBufferType, scaledImageBytes, scaledImageRowBytes, releaseCallBack, nil, nil, &scaledPixelBuffer)

    guard conversionStatus == kCVReturnSuccess else {

      free(scaledImageBytes)
      return nil
    }

    return scaledPixelBuffer
  }

}
