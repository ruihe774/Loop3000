//
// DRUNetColor.swift
//
// This file was automatically generated and should not be edited.
//

import CoreML


/// Model Prediction Input Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
class DRUNetColorInput : MLFeatureProvider {

    /// inputImage as color (kCVPixelFormatType_32BGRA) image buffer, 600 pixels wide by 600 pixels high
    var inputImage: CVPixelBuffer

    /// noiseLevel as 1 element vector of floats
    var noiseLevel: MLMultiArray

    var featureNames: Set<String> {
        get {
            return ["inputImage", "noiseLevel"]
        }
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        if (featureName == "inputImage") {
            return MLFeatureValue(pixelBuffer: inputImage)
        }
        if (featureName == "noiseLevel") {
            return MLFeatureValue(multiArray: noiseLevel)
        }
        return nil
    }
    
    init(inputImage: CVPixelBuffer, noiseLevel: MLMultiArray) {
        self.inputImage = inputImage
        self.noiseLevel = noiseLevel
    }

    convenience init(inputImage: CVPixelBuffer, noiseLevel: MLShapedArray<Float>) {
        self.init(inputImage: inputImage, noiseLevel: MLMultiArray(noiseLevel))
    }

    convenience init(inputImageWith inputImage: CGImage, noiseLevel: MLMultiArray) throws {
        self.init(inputImage: try MLFeatureValue(cgImage: inputImage, pixelsWide: 600, pixelsHigh: 600, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, noiseLevel: noiseLevel)
    }

    convenience init(inputImageWith inputImage: CGImage, noiseLevel: MLShapedArray<Float>) throws {
        self.init(inputImage: try MLFeatureValue(cgImage: inputImage, pixelsWide: 600, pixelsHigh: 600, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, noiseLevel: MLMultiArray(noiseLevel))
    }

    convenience init(inputImageAt inputImage: URL, noiseLevel: MLMultiArray) throws {
        self.init(inputImage: try MLFeatureValue(imageAt: inputImage, pixelsWide: 600, pixelsHigh: 600, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, noiseLevel: noiseLevel)
    }

    convenience init(inputImageAt inputImage: URL, noiseLevel: MLShapedArray<Float>) throws {
        self.init(inputImage: try MLFeatureValue(imageAt: inputImage, pixelsWide: 600, pixelsHigh: 600, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!, noiseLevel: MLMultiArray(noiseLevel))
    }

    func setInputImage(with inputImage: CGImage) throws  {
        self.inputImage = try MLFeatureValue(cgImage: inputImage, pixelsWide: 600, pixelsHigh: 600, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

    func setInputImage(with inputImage: URL) throws  {
        self.inputImage = try MLFeatureValue(imageAt: inputImage, pixelsWide: 600, pixelsHigh: 600, pixelFormatType: kCVPixelFormatType_32ARGB, options: nil).imageBufferValue!
    }

}


/// Model Prediction Output Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
class DRUNetColorOutput : MLFeatureProvider {

    /// Source provided by CoreML
    private let provider : MLFeatureProvider

    /// outputImage as color (kCVPixelFormatType_32BGRA) image buffer, 600 pixels wide by 600 pixels high
    var outputImage: CVPixelBuffer {
        return self.provider.featureValue(for: "outputImage")!.imageBufferValue!
    }

    var featureNames: Set<String> {
        return self.provider.featureNames
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        return self.provider.featureValue(for: featureName)
    }

    init(outputImage: CVPixelBuffer) {
        self.provider = try! MLDictionaryFeatureProvider(dictionary: ["outputImage" : MLFeatureValue(pixelBuffer: outputImage)])
    }

    init(features: MLFeatureProvider) {
        self.provider = features
    }
}


/// Class for model loading and prediction
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
class DRUNetColor {
    let model: MLModel

    /// URL of model assuming it was installed in the same bundle as this class
    class var urlOfModelInThisBundle : URL {
        let bundle = Bundle(for: self)
        return bundle.url(forResource: "DRUNetColor", withExtension:"mlmodelc")!
    }

    /**
        Construct DRUNetColor instance with an existing MLModel object.

        Usually the application does not use this initializer unless it makes a subclass of DRUNetColor.
        Such application may want to use `MLModel(contentsOfURL:configuration:)` and `DRUNetColor.urlOfModelInThisBundle` to create a MLModel object to pass-in.

        - parameters:
          - model: MLModel object
    */
    init(model: MLModel) {
        self.model = model
    }

    /**
        Construct a model with configuration

        - parameters:
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        try self.init(contentsOf: type(of:self).urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct DRUNetColor instance with explicit path to mlmodelc file
        - parameters:
           - modelURL: the file url of the model

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL) throws {
        try self.init(model: MLModel(contentsOf: modelURL))
    }

    /**
        Construct a model with URL of the .mlmodelc directory and configuration

        - parameters:
           - modelURL: the file url of the model
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /**
        Construct DRUNetColor instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<DRUNetColor, Error>) -> Void) {
        return self.load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
    }

    /**
        Construct DRUNetColor instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> DRUNetColor {
        return try await self.load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct DRUNetColor instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<DRUNetColor, Error>) -> Void) {
        MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
            switch result {
            case .failure(let error):
                handler(.failure(error))
            case .success(let model):
                handler(.success(DRUNetColor(model: model)))
            }
        }
    }

    /**
        Construct DRUNetColor instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> DRUNetColor {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return DRUNetColor(model: model)
    }

    /**
        Make a prediction using the structured interface

        - parameters:
           - input: the input to the prediction as DRUNetColorInput

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as DRUNetColorOutput
    */
    func prediction(input: DRUNetColorInput) throws -> DRUNetColorOutput {
        return try self.prediction(input: input, options: MLPredictionOptions())
    }

    /**
        Make a prediction using the structured interface

        - parameters:
           - input: the input to the prediction as DRUNetColorInput
           - options: prediction options 

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as DRUNetColorOutput
    */
    func prediction(input: DRUNetColorInput, options: MLPredictionOptions) throws -> DRUNetColorOutput {
        let outFeatures = try model.prediction(from: input, options:options)
        return DRUNetColorOutput(features: outFeatures)
    }

    /**
        Make a prediction using the convenience interface

        - parameters:
            - inputImage as color (kCVPixelFormatType_32BGRA) image buffer, 600 pixels wide by 600 pixels high
            - noiseLevel as 1 element vector of floats

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as DRUNetColorOutput
    */
    func prediction(inputImage: CVPixelBuffer, noiseLevel: MLMultiArray) throws -> DRUNetColorOutput {
        let input_ = DRUNetColorInput(inputImage: inputImage, noiseLevel: noiseLevel)
        return try self.prediction(input: input_)
    }

    /**
        Make a prediction using the convenience interface

        - parameters:
            - inputImage as color (kCVPixelFormatType_32BGRA) image buffer, 600 pixels wide by 600 pixels high
            - noiseLevel as 1 element vector of floats

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as DRUNetColorOutput
    */

    func prediction(inputImage: CVPixelBuffer, noiseLevel: MLShapedArray<Float>) throws -> DRUNetColorOutput {
        let input_ = DRUNetColorInput(inputImage: inputImage, noiseLevel: noiseLevel)
        return try self.prediction(input: input_)
    }

    /**
        Make a batch prediction using the structured interface

        - parameters:
           - inputs: the inputs to the prediction as [DRUNetColorInput]
           - options: prediction options 

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as [DRUNetColorOutput]
    */
    func predictions(inputs: [DRUNetColorInput], options: MLPredictionOptions = MLPredictionOptions()) throws -> [DRUNetColorOutput] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results : [DRUNetColorOutput] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result =  DRUNetColorOutput(features: outProvider)
            results.append(result)
        }
        return results
    }
}
