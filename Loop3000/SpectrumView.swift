import Accelerate
import CoreMedia
import SwiftUI
import Charts
import Combine

struct SpectrumView: View {
    @EnvironmentObject private var model: AppModel

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
    @State private var sampleBuffers: [CMSampleBuffer] = []
    @State private var freqDB: [[Float]] = []

    var body: some View {
        VStack {
            ForEach(Array(freqDB.enumerated()), id: \.offset) { (_, freq) in
                Chart(Array(freq.enumerated()), id: \.offset) { (offset, db) in
                    LineMark(x: .value("Offset", offset), y: .value("dB", db))
                }
            }
        }
        .onReceive(model.audioBufferEnqueud) { sampleBuffers.append($0) }
        .onReceive(model.guiRefreshTimer) { _ in
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
            let originalSampleBuffers = sampleBuffers
            sampleBuffers = []
            if trimLast > 0 {
                sampleBuffers.append(try! CMSampleBuffer(
                    copying: lastSampleBuffer,
                    forRange: (lastSampleBuffer.numSamples - trimLast) ..< lastSampleBuffer.numSamples)
                )
            }
            sampleBuffers.append(contentsOf: originalSampleBuffers[(sampleBufferIndex + 1)...])
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
            freqDB = freqBuffers
        }
    }
}
