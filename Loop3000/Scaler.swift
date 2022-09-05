import CoreImage
import CoreVideo
import CoreML
import Metal
import MetalFX

class Scaler {
    struct Resolution {
        var width: Int
        var height: Int
    }

    private let device: MTLDevice
    private let cmdQueue: MTLCommandQueue
    let cictx: CIContext
    private let denoiser = try! DRUNetColor()

    private static let sharedScaler = Scaler()

    static func shared() -> Scaler {
        sharedScaler
    }

    init(device dev: MTLDevice) {
        device = dev
        cmdQueue = device.makeCommandQueue()!
        cictx = CIContext(mtlDevice: device)
    }

    convenience init() {
        self.init(device: MTLCreateSystemDefaultDevice()!)
    }

    func scaleAndDenoise(images: [CIImage], to sizes: [Resolution]) async -> [CIImage] {
        guard !images.isEmpty else { return [] }
        let scaledBuffers = await withCheckedContinuation { continuation in
            var scalers: [MTLFXSpatialScalerDescriptor: MTLFXSpatialScaler] = [:]
            func getSpatialScaler(for desc: MTLFXSpatialScalerDescriptor) -> MTLFXSpatialScaler {
                let scaler = scalers[desc] ?? desc.makeSpatialScaler(device: device)!
                scalers[desc] = scaler
                return scaler
            }
            let cmdBuffer = cmdQueue.makeCommandBuffer()!
            var outCache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(
                kCFAllocatorDefault,
                [kCVMetalTextureUsage: MTLTextureUsage([.renderTarget, .shaderRead]).rawValue] as CFDictionary,
                device,
                nil,
                &outCache
            )
            let cache = outCache!
            let outputTextures = zip(images, sizes).map { (image, size) in
                let inputTextureDesc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: Int(image.extent.width),
                    height: Int(image.extent.height),
                    mipmapped: false
                )
                inputTextureDesc.usage = [.shaderWrite, .shaderRead]
                let inputTexture = device.makeTexture(descriptor: inputTextureDesc)!
                cictx.render(
                    image,
                    to: inputTexture,
                    commandBuffer: cmdBuffer,
                    bounds: image.extent,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
                )
                let scaleDesc = makeSpatialScalerDescriptor(for: inputTexture, to: size)
                var outPixelBuffer: CVPixelBuffer?
                CVPixelBufferCreate(
                    kCFAllocatorDefault,
                    scaleDesc.outputWidth,
                    scaleDesc.outputHeight,
                    kCVPixelFormatType_32BGRA,
                    [kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue] as CFDictionary,
                    &outPixelBuffer
                )
                let pixelBuffer = outPixelBuffer!
                var outCVTexture: CVMetalTexture?
                CVMetalTextureCacheCreateTextureFromImage(
                    kCFAllocatorDefault,
                    cache,
                    pixelBuffer,
                    nil,
                    .bgra8Unorm,
                    scaleDesc.outputWidth,
                    scaleDesc.outputHeight,
                    0,
                    &outCVTexture
                )
                let cvTexture = outCVTexture!
                let outputTexture = CVMetalTextureGetTexture(cvTexture)
                let scaler = getSpatialScaler(for: scaleDesc)
                scaler.colorTexture = inputTexture
                scaler.outputTexture = outputTexture
                scaler.encode(commandBuffer: cmdBuffer)
                return pixelBuffer
            }
            cmdBuffer.addCompletedHandler { _ in
                continuation.resume(returning: outputTextures)
            }
            cmdBuffer.commit()
        }
        let constraint = denoiser.model.modelDescription.inputDescriptionsByName["inputImage"]!.imageConstraint!
        var denoisedBuffers = scaledBuffers
        let canDenoise = scaledBuffers
            .enumerated()
            .filter {
                let width = CVPixelBufferGetWidth($1)
                let height = CVPixelBufferGetHeight($1)
                return width == constraint.pixelsWide && height == constraint.pixelsHigh
            }
        if !canDenoise.isEmpty {
            for (i, buffer) in zip(
                canDenoise.map { $0.0 },
                await withCheckedContinuation { continuation in DispatchQueue.global().async {
                    continuation.resume(returning: try! self.denoiser.predictions(
                        inputs: canDenoise.map { DRUNetColorInput(inputImage: $1, noiseLevel: try! MLMultiArray([Float(8)])) }
                    ))
                }}.map { $0.outputImage }
            ) {
                denoisedBuffers[i] = buffer
            }
        }
        let outputImages = denoisedBuffers.map { buffer in
            CIImage(cvPixelBuffer: buffer, options: [.colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
                .oriented(.downMirrored)
        }
        return outputImages
    }
}

fileprivate func makeSpatialScalerDescriptor(for inputTexture: MTLTexture,
                                             to size: Scaler.Resolution) -> MTLFXSpatialScalerDescriptor
{
    let desc = MTLFXSpatialScalerDescriptor()
    desc.inputWidth = inputTexture.width
    desc.inputHeight = inputTexture.height
    desc.colorTextureFormat = inputTexture.pixelFormat
    desc.outputWidth = size.width
    desc.outputHeight = size.height
    desc.outputTextureFormat = inputTexture.pixelFormat
    desc.colorProcessingMode = .perceptual
    return desc
}
