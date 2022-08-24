import CoreImage
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

    init(device dev: MTLDevice) {
        device = dev
        cmdQueue = device.makeCommandQueue()!
        cictx = CIContext(mtlDevice: device)
    }

    convenience init() {
        self.init(device: MTLCreateSystemDefaultDevice()!)
    }

    func scale(images: [CIImage], to sizes: [Resolution]) async -> [CIImage] {
        return await withCheckedContinuation { continuation in
            var scalers: [MTLFXSpatialScalerDescriptor: MTLFXSpatialScaler] = [:]
            func getSpatialScaler(for desc: MTLFXSpatialScalerDescriptor) -> MTLFXSpatialScaler {
                let scaler = scalers[desc] ?? desc.makeSpatialScaler(device: device)!
                scalers[desc] = scaler
                return scaler
            }
            let cmdBuffer = cmdQueue.makeCommandBuffer()!
            let outputTextures = zip(images, sizes).map { (image, size) in
                let inputTextureDesc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba16Float,
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
                    colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
                )
                let scaleDesc = makeSpatialScalerDescriptor(for: inputTexture, to: size)
                let outputTextureDesc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: scaleDesc.outputTextureFormat,
                    width: scaleDesc.outputWidth,
                    height: scaleDesc.outputHeight,
                    mipmapped: false
                )
                outputTextureDesc.usage = [.renderTarget, .shaderRead]
                let outputTexture = device.makeTexture(descriptor: outputTextureDesc)!
                let scaler = getSpatialScaler(for: scaleDesc)
                scaler.colorTexture = inputTexture
                scaler.outputTexture = outputTexture
                scaler.encode(commandBuffer: cmdBuffer)
                return outputTexture
            }
            cmdBuffer.addCompletedHandler { _ in
                continuation.resume(returning: outputTextures)
            }
            cmdBuffer.commit()
        }.map { texture in
            CIImage(mtlTexture: texture, options: [
                .colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            ])!
        }
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
    desc.colorProcessingMode = .linear
    return desc
}
