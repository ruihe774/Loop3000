import Accelerate
import CoreVideo
import CoreMedia
import CoreText
import CoreGraphics
import CoreImage
import SwiftUI
import Collections

struct SpectrumView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.displayScale) private var displayScale: CGFloat

    private static let numBands = 1024
    private let dsp = try! vDSP.DiscreteFourierTransform(
        count: Self.numBands,
        direction: .forward,
        transformType: .complexReal,
        ofType: DSPComplex.self
    )
    private let windowSequence = vDSP.window(
        ofType: Float.self,
        usingSequence: .hanningDenormalized,
        count: Self.numBands,
        isHalfWindow: false
    )
    @State private var sampleBuffers: Deque<CMSampleBuffer> = []
    @State private var sampleRate = 0
    @State private var spectrums: Deque<[[Float]]> = []
    @State private var images: [CGImage] = []
    @State private var geometrySize = CGSize()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ForEach(Array(images.enumerated()), id: \.offset) { (i, image) in
                    if i != 0 { Divider() }
                    Image(image, scale: displayScale, label: Text("Spectrum of channel \(i)"))
                }
            }
            .onReceive(model.audioBufferEnqueud) {
                sampleBuffers.append($0)
            }
            .onReceive(model.guiRefreshTimer) { _ in
                compute()
                redraw()
            }
            .onChange(of: geo.size) { size in
                geometrySize = size
                redraw()
            }
        }
    }

    private func compute() {
        let currentTime = model.currentPlayerTime
        guard let sampleBufferIndex =
               sampleBuffers.lastIndex(where: { $0.outputPresentationTimeStamp < currentTime }) else { return }
        var selectedSampleBuffers = sampleBuffers[...sampleBufferIndex].filter {
           $0.dataBuffer != nil && $0.formatDescription?.audioStreamBasicDescription != nil
        }
        guard let lastSampleBuffer = selectedSampleBuffers.last else { return }
        let format = lastSampleBuffer.formatDescription!
        selectedSampleBuffers = selectedSampleBuffers.filter { $0.formatDescription == format }
        let asbd = format.audioStreamBasicDescription!
        guard asbd.mFormatID == kAudioFormatLinearPCM
               && asbd.mFormatFlags & kAudioFormatFlagsNativeEndian == kAudioFormatFlagsNativeEndian
               && asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
               && 4 * asbd.mChannelsPerFrame  == asbd.mBytesPerFrame
        else { return }
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let channels = Int(asbd.mChannelsPerFrame)
        var blockBuffer = try! CMBlockBuffer()
        var numSamples = 0
        for sampleBuffer in selectedSampleBuffers {
           try! blockBuffer.append(bufferReference: sampleBuffer.dataBuffer!)
           numSamples += sampleBuffer.numSamples
        }
        var mergedSampleBuffer = try! CMSampleBuffer(
           dataBuffer: blockBuffer,
           formatDescription: format,
           numSamples: numSamples,
           presentationTimeStamp: .zero,
           packetDescriptions: []
        )
        let trimLast = max(0, Int(
           (lastSampleBuffer.outputPresentationTimeStamp + lastSampleBuffer.duration - currentTime)
               .convertScale(Int32(asbd.mSampleRate), method: .default).value
        ))
        numSamples = (numSamples - trimLast) / Self.numBands * Self.numBands
        guard numSamples != 0 else { return }
        mergedSampleBuffer = try! CMSampleBuffer(
           copying: mergedSampleBuffer,
           forRange: (mergedSampleBuffer.numSamples - trimLast - numSamples) ..< (mergedSampleBuffer.numSamples - trimLast)
        )
        blockBuffer = mergedSampleBuffer.dataBuffer!
        sampleBuffers.removeFirst(sampleBufferIndex + 1)
        if trimLast > 0 {
           sampleBuffers.prepend(try! CMSampleBuffer(
               copying: lastSampleBuffer,
               forRange: (lastSampleBuffer.numSamples - trimLast) ..< lastSampleBuffer.numSamples)
           )
        }
        let channelBuffers = try! blockBuffer.withContiguousStorage { ptr in
           if isFloat {
               let blockBuffer = ptr.assumingMemoryBound(to: Float.self)
               return (0 ..< channels).map { j in
                   (0 ..< blockBuffer.count / channels).map { i in
                       blockBuffer[i * channels + j]
                   }
               }
           } else {
               let blockBuffer = ptr.assumingMemoryBound(to: Int32.self)
               return (0 ..< channels).map { j in
                   (0 ..< blockBuffer.count / channels).map { i in
                       Float(blockBuffer[i * channels + j]) / Float(1 << (asbd.mBitsPerChannel - 1))
                   }
               }
           }
        }
        let freqBuffers = channelBuffers
           .map { channelBuffer in
               let freqBuffers = (0 ..< channelBuffer.count / Self.numBands)
                   .map { channelBuffer[$0 * Self.numBands ..< ($0 + 1) * Self.numBands] }
                   .map { vDSP.multiply($0, windowSequence) }
                   .map { $0.map { DSPComplex(real: $0, imag: 0) } }
                   .map { dsp.transform(input: $0) }
                   .map { freqBuffer in
                       let n2 = Float(Self.numBands * Self.numBands)
                       return freqBuffer[..<(Self.numBands / 2)].map {
                           10 * log10f(($0.real * $0.real + $0.imag * $0.imag) / n2)
                       }
                   }
               var mergedFreqBuffer = freqBuffers.first!
               for freqBuffer in freqBuffers[1...] {
                   mergedFreqBuffer = vDSP.add(mergedFreqBuffer, freqBuffer)
               }
               return vDSP.divide(mergedFreqBuffer, Float(freqBuffers.count))
           }
        sampleRate = Int(asbd.mSampleRate)
        spectrums.append(freqBuffers)
        while spectrums.count > Int(geometrySize.width) / 2 {
           let _ = spectrums.popFirst()
        }
        while spectrums.first?.count != freqBuffers.count {
           let _ = spectrums.popFirst()
        }
    }

    private func redraw() {
        guard let channels = spectrums.first?.count else { return }
        let width = Int(geometrySize.width) / 2
        let height = Self.numBands / 3
        let exp: Float = 2
        let corr = Float(Self.numBands / 2) / pow(Float(height), exp)
        let freqBin = Float(sampleRate) / Float(Self.numBands)
        let cictx = CIContext(options: [.workingColorSpace: nil as Any? as Any])
        images = (0 ..< channels)
        .map { j in
           var outPixelBuffer: CVPixelBuffer?
           CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCMPixelFormat_32BGRA, nil, &outPixelBuffer)
           let pixelBuffer = outPixelBuffer!
           CVPixelBufferLockBaseAddress(pixelBuffer, .init(rawValue: 0))
           defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .init(rawValue: 0)) }
           let ptr = CVPixelBufferGetBaseAddress(pixelBuffer)!
           let bytesPerRow = Int(CVPixelBufferGetBytesPerRow(pixelBuffer))
           memset(ptr, 0, bytesPerRow * height)
           for (i, freqBuffer) in spectrums.map({ $0[j] }).enumerated() {
               assert(i < width)
               for j in 0 ..< height {
                   let pixelPtr = (ptr + bytesPerRow * j).assumingMemoryBound(to: UInt32.self) + i
                   let db = freqBuffer[min(freqBuffer.count - 1, Int(round(corr * pow(Float(j), exp))))]
                   let level = max(0, db / 120 + 1)
                   let intLevel = UInt32(level * 255)
                   pixelPtr.pointee = intLevel << 16 | intLevel << 8 | intLevel | 0xff000000
               }
           }
           return CIImage(cvPixelBuffer: pixelBuffer)
        }
        .map { image in
           let targetW = geometrySize.width * displayScale
           let targetH = (geometrySize.height - CGFloat(channels) + 1) / CGFloat(channels) * displayScale
           let scaleX = targetW / image.extent.width
           let scaleY = targetH / image.extent.height
           let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
           let transformedImage = image
               .transformed(by: image.orientationTransform(for: .downMirrored).concatenating(scaleTransform))
               .applyingFilter("CIColorMap", parameters: ["inputGradientImage": soxColorMap])
           let cgctx = CGContext(
               data: nil,
               width: Int(targetW),
               height: Int(targetH),
               bitsPerComponent: 8,
               bytesPerRow: 0,
               space: CGColorSpace(name: CGColorSpace.sRGB)!,
               bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
           )!
           cictx.render(
               transformedImage,
               toBitmap: cgctx.data!,
               rowBytes: cgctx.bytesPerRow,
               bounds: transformedImage.extent,
               format: .BGRA8,
               colorSpace: nil
           )
           cgctx.setStrokeColor(.white)
           cgctx.setLineWidth(2)
           for freq in [100, 400, 1000, 2000, 5000, 10000, 15000, 20000] {
               let originalY = pow(Float(freq) / freqBin / corr, 1 / exp)
               let transformedY = CGPoint(x: 0, y: CGFloat(originalY)).applying(scaleTransform).y
               cgctx.strokeLineSegments(between: [
                   CGPoint(x: 50, y: transformedY),
                   CGPoint(x: 150, y: transformedY)
               ])
               cgctx.textPosition = CGPoint(x: 15, y: transformedY - 4)
               let labelString = CFAttributedStringCreate(
                   kCFAllocatorDefault,
                   (freq < 1000 ? "\(freq)" : "\(freq / 1000)k") as CFString,
                   [
                       kCTForegroundColorAttributeName: CGColor.white,
                       kCTFontWeightTrait: NSFont.Weight.bold
                   ] as CFDictionary
               )!
               let labelLine = CTLineCreateWithAttributedString(labelString)
               CTLineDraw(labelLine, cgctx)
           }
           return cgctx.makeImage()!
        }
    }
}

fileprivate func soxPalette(level: Float) -> (r: Float, g: Float, b: Float){
    var r: Float = 0.0;
    if level >= 0.13 && level < 0.73 {
        r = sin((level - 0.13) / 0.60 * Float.pi / 2.0);
    } else if level >= 0.73 {
        r = 1.0;
    }

    var g: Float = 0.0;
    if level >= 0.6 && level < 0.91 {
        g = sin((level - 0.6) / 0.31 * Float.pi / 2.0);
    } else if level >= 0.91 {
        g = 1.0;
    }

    var b: Float = 0.0;
    if level < 0.60 {
        b = 0.5 * sin(level / 0.6 * Float.pi);
    } else if level >= 0.78 {
        b = (level - 0.78) / 0.22;
    }

    return (r: r, g: g, b: b)
}

fileprivate let soxColorMap = {
    var outPixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 256, 1, kCMPixelFormat_32BGRA, nil, &outPixelBuffer)
    let pixelBuffer = outPixelBuffer!
    CVPixelBufferLockBaseAddress(pixelBuffer, .init(rawValue: 0))
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .init(rawValue: 0)) }
    let ptr = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt32.self)
    for i in 0 ... 255 {
        let (r, g, b) = soxPalette(level: Float(i) / 255)
        let intR = UInt32(r * 255)
        let intG = UInt32(g * 255)
        let intB = UInt32(b * 255)
        (ptr + i).pointee = intR << 16 | intG << 8 | intB | 0xff000000
    }
    return CIImage(cvPixelBuffer: pixelBuffer)
}()
