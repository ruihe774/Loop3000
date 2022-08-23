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
    private let cmdBuffer: MTLCommandBuffer
    private var scalers: [MTLFXSpatialScalerDescriptor: MTLFXSpatialScaler] = [:]
    private let cictx: CIContext

    init(device dev: MTLDevice) {
        device = dev
        cmdQueue = device.makeCommandQueue()!
        cmdBuffer = cmdQueue.makeCommandBuffer()!
        cictx = CIContext(mtlDevice: device)
    }

    convenience init() {
        self.init(device: MTLCreateSystemDefaultDevice()!)
    }

    private func makeSpatialScalerDescriptor(for inputTexture: MTLTexture,
                                             to size: Resolution) -> MTLFXSpatialScalerDescriptor
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

    private func getSpatialScaler(for desc: MTLFXSpatialScalerDescriptor) -> MTLFXSpatialScaler {
        let scaler = scalers[desc] ?? desc.makeSpatialScaler(device: device)!
        scalers[desc] = scaler
        return scaler
    }

    func scale(textures: [MTLTexture], to sizes: [Resolution]) -> [MTLTexture] {
        let descs = zip(textures, sizes).map { makeSpatialScalerDescriptor(for: $0, to: $1) }
        let outputs = zip(textures, descs).map { inputTexture, desc in
            let outputTextureDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: desc.outputTextureFormat,
                width: desc.outputWidth,
                height: desc.outputHeight,
                mipmapped: false
            )
            outputTextureDesc.usage = [.renderTarget, .shaderRead]
            let outputTexture = device.makeTexture(descriptor: outputTextureDesc)!
            let scaler = getSpatialScaler(for: desc)
            scaler.colorTexture = inputTexture
            scaler.outputTexture = outputTexture
            scaler.encode(commandBuffer: cmdBuffer)
            scaler.colorTexture = nil
            scaler.outputTexture = nil
            return outputTexture
        }
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        return outputs
    }

    func scale(images: [CIImage], to sizes: [Resolution]) -> [CIImage] {
        let inputTextures = images.map { ciimg in
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: Int(ciimg.extent.width),
                height: Int(ciimg.extent.height),
                mipmapped: false
            )
            desc.usage = [.shaderWrite, .shaderRead]
            let tex = device.makeTexture(descriptor: desc)!
            cictx.render(
                ciimg,
                to: tex,
                commandBuffer: cmdBuffer,
                bounds: ciimg.extent,
                colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!
            )
            return tex
        }
        let outputTextures = scale(textures: inputTextures, to: sizes)
        return outputTextures.map { texture in
            let image = CIImage(mtlTexture: texture, options: [
                .colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
            ])!
            return image
        }
    }
}
