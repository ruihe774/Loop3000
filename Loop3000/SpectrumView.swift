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
        .onReceive(model.audioBufferEnqueud.collect(.byTime(RunLoop.main, .milliseconds(100)))) { newSampleBuffers in
            sampleBuffers.append(contentsOf: newSampleBuffers)
            let currentTime = model.currentPlayerTime
            guard let sampleBufferIndex =
                    sampleBuffers.lastIndex(where: { $0.outputPresentationTimeStamp < currentTime }) else { return }
            let sampleBuffer = sampleBuffers[sampleBufferIndex]
            sampleBuffers = Array(sampleBuffers[(sampleBufferIndex + 1)...])
            guard let blockBuffer = sampleBuffer.dataBuffer else { return }
            guard let format = sampleBuffer.formatDescription else { return }
            guard let asbd = format.audioStreamBasicDescription else { return }
            guard asbd.mFormatID == kAudioFormatLinearPCM
                    && asbd.mFormatFlags & kAudioFormatFlagsNativeEndian == kAudioFormatFlagsNativeEndian
                    && asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
                    && 4 * asbd.mChannelsPerFrame  == asbd.mBytesPerFrame
            else { return }
            let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
            let channels = Int(asbd.mChannelsPerFrame)
            let channelBuffers = try! blockBuffer.withContiguousStorage { ptr -> [[Float]]? in
                guard ptr.count >= Self.numBands else { return nil }
                if isFloat {
                    let blockBuffer = ptr.assumingMemoryBound(to: Float.self)
                    return (0 ..< channels).map { j in
                        (0 ..< Self.numBands).map { i in
                            blockBuffer[i * channels + j]
                        }
                    }
                } else {
                    let blockBuffer = ptr.assumingMemoryBound(to: Int32.self)
                    return (0 ..< channels).map { j in
                        (0 ..< Self.numBands).map { i in
                            Float(blockBuffer[i * channels + j]) / Float(1 << (asbd.mBitsPerChannel - 1))
                        }
                    }
                }
            }
            guard let channelBuffers else { return }
            freqDB = channelBuffers
                .map { vDSP.multiply($0, windowSequence) }
                .map { $0.map { DSPComplex(real: $0, imag: 0) } }
                .map { dsp.transform(input: $0) }
                .map { freqBuffer in
                    let n2 = Float(Self.numBands * Self.numBands)
                    return freqBuffer[..<(Self.numBands / 2)].map {
                        10 * log10f(($0.real * $0.real + $0.imag * $0.imag) / n2)
                    }
                }
        }
    }
}
