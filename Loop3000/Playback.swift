import Foundation
import AVFoundation
import UniformTypeIdentifiers

extension CueTime {
    func toSample(atRate rate: Int) -> Int {
        value * rate / Self.timescale
    }
}

extension CMTime {
    func toSample(atRate rate: Int) -> Int {
        Int(convertScale(Int32(rate), method: .default).value)
    }
}

protocol AudioDecoder {
    static var supportedTypes: [UTType] { get }

    init(track: Track) throws

    func nextSampleBuffer() throws -> CMSampleBuffer?
    func seek(to time: CMTime)
}

var audioDecoders: [AudioDecoder.Type] = [FLACDecoder.self, AVDecoder.self]

struct NoApplicableDecoder: Error {
    let url: URL
}

func makeAudioDecoder(for track: Track) throws -> any AudioDecoder {
    let type = UTType(filenameExtension: track.source.pathExtension)!
    guard let decoderType = audioDecoders.first(where: { decoder in
        decoder.supportedTypes.contains { type.conforms(to: $0) }
    }) else {
        throw NoApplicableDecoder(url: track.source)
    }
    return try decoderType.init(track: track)
}

class PlaybackScheduler {
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let playbackQueue = DispatchQueue(label: "PlaybackScheduler.playback", qos: .userInteractive)

    var requestNextHandler: @Sendable (Track?) -> Track? = { _ in nil }
    var errorHandler: @Sendable (Error) -> () = { fatalError("\($0)") }

    private var current: (Track, AudioDecoder)?
    private var next: (Track, AudioDecoder)?
    private var bufferedUntil = CMTime.zero
    private var trailingUntil = CMTime.invalid
    private var bufferedForCurrentTrack = CMTime.zero
    private var bufferedForNextTrack = CMTime.zero
    private var readahead = CMTime.zero

    var playing: Bool {
        if synchronizer.rate == 0 {
            return false
        }
        return synchronizer.currentTime() < bufferedUntil
    }

    var currentTrack: Track? {
        guard let current else { return nil }
        guard trailingUntil != .invalid else { return current.0 }
        if synchronizer.currentTime() >= trailingUntil {
            return next?.0
        } else {
            return current.0
        }
    }

    var currentTimestamp: CueTime {
        let currentTime = synchronizer.currentTime()
        var time = (trailingUntil != .invalid && currentTime >= trailingUntil
                    ? bufferedForNextTrack : bufferedForCurrentTrack)
        if bufferedUntil > currentTime {
            time = time + (currentTime - bufferedUntil)
        }
        return CueTime(from: max(time, .zero))
    }

    var bufferedSeconds: Double {
        if bufferedUntil == .zero {
            return 0
        } else {
            return (bufferedUntil - synchronizer.currentTime()).seconds
        }
    }

    init() {
        synchronizer.addRenderer(renderer)
    }

    private func playbackLoop() {
        do {
            var currentTime = synchronizer.currentTime()
            let initial = bufferedUntil == .zero
            var readheadAdjusted = false
            while renderer.isReadyForMoreMediaData || bufferedUntil - currentTime < readahead {
                currentTime = synchronizer.currentTime()
                var freshStart = false
                var useCurrent = false
                if trailingUntil != .invalid {
                    if next == nil {
                        guard let track = requestNextHandler(current?.0) else {
                            renderer.stopRequestingMediaData()
                            return
                        }
                        let decoder = try makeAudioDecoder(for: track)
                        next = (track, decoder)
                    }
                    if currentTime >= trailingUntil {
                        current = next
                        next = nil
                        trailingUntil = .invalid
                        bufferedForCurrentTrack = bufferedForNextTrack
                        bufferedForNextTrack = .zero
                        useCurrent = true
                    }
                } else {
                    if current == nil {
                        if next != nil {
                            current = next
                            next = nil
                            bufferedForCurrentTrack = bufferedForNextTrack
                            bufferedForNextTrack = .zero
                        } else {
                            guard let track = requestNextHandler(nil) else {
                                renderer.stopRequestingMediaData()
                                return
                            }
                            let decoder = try makeAudioDecoder(for: track)
                            current = (track, decoder)
                            freshStart = true
                        }
                    }
                    useCurrent = true
                }
                let decoder = useCurrent ? current!.1 : next!.1
                let buffer = try decoder.nextSampleBuffer()
                currentTime = synchronizer.currentTime()
                let newUntil = max(bufferedUntil, currentTime + (freshStart ? CMTime(value: 1, timescale: 3) : CMTime(value: 1, timescale: 100)))
                if !initial && !readheadAdjusted {
                    let runOutDistance = newUntil - currentTime
                    if runOutDistance < CMTime(value: 1, timescale: 1) {
                        readahead = readahead + CMTime(value: 1, timescale: 1)
                    }
                    if runOutDistance < CMTime(value: 1, timescale: 2) {
                        readahead = readahead + readahead
                    }
                    readahead = max(readahead, (newUntil - bufferedUntil) + (newUntil - bufferedUntil))
                    readahead = min(CMTime(value: 60, timescale: 1), readahead)
                    readheadAdjusted = true
                }
                bufferedUntil = newUntil
                if let buffer {
                    let duration = buffer.duration
                    CMSampleBufferSetOutputPresentationTimeStamp(buffer, newValue: bufferedUntil)
                    renderer.enqueue(buffer)
                    bufferedUntil = bufferedUntil + duration
                    if useCurrent {
                        bufferedForCurrentTrack = bufferedForCurrentTrack + duration
                    } else {
                        bufferedForNextTrack = bufferedForNextTrack + duration
                    }
                } else if trailingUntil == .invalid {
                    trailingUntil = bufferedUntil
                } else {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            readahead = readahead + CMTime(value: 1, timescale: 1000000000)
            readahead.value = readahead.value * 4999 / 5000
        } catch let error {
            renderer.stopRequestingMediaData()
            errorHandler(error)
        }
    }

    func play() {
        playbackQueue.sync {
            self.synchronizer.rate = 1
            self.renderer.stopRequestingMediaData()
            let timer = DispatchSource.makeTimerSource(queue: playbackQueue)
            timer.setEventHandler { [unowned self] in
                self.playbackLoop()
            }
            timer.schedule(deadline: DispatchTime.now(), repeating: .milliseconds(100))
            timer.activate()
            class Canceller {
                let timer: DispatchSourceTimer
                deinit {
                    timer.cancel()
                }
                init(timer: DispatchSourceTimer) {
                    self.timer = timer
                }
            }
            let canceller = Canceller(timer: timer)
            self.renderer.requestMediaDataWhenReady(on: playbackQueue) { [unowned self] in
                let _ = canceller
                self.playbackLoop()
            }
        }
    }

    func pause() {
        playbackQueue.sync {
            self.synchronizer.rate = 0
        }
    }

    func stop() {
        playbackQueue.sync {
            self.renderer.stopRequestingMediaData()
            self.renderer.flush()
            self.synchronizer.rate = 0
            self.current = nil
            self.next = nil
            self.bufferedUntil = .zero
            self.trailingUntil = .invalid
            self.bufferedForCurrentTrack = .zero
            self.bufferedForNextTrack = .zero
        }
    }

    func seek(to time: CueTime) {
        playbackQueue.sync {
            self.renderer.flush()
            current!.1.seek(to: CMTime(from: time))
            next?.1.seek(to: .zero)
            self.bufferedUntil = .zero
            self.trailingUntil = .invalid
            self.bufferedForCurrentTrack = CMTime(from: time)
            self.bufferedForNextTrack = .zero
        }
    }
}

class AVDecoder: AudioDecoder {
    static let supportedTypes = [UTType.audio]

    private let file: AVAudioFile
    private let startSample: Int
    private let endSample: Int

    static let maxFrameCount = 0x1000

    required init(track: Track) throws {
        file = try AVAudioFile(forReading: track.source, commonFormat: .pcmFormatFloat32, interleaved: true)
        let sampleRate = Int(exactly: file.processingFormat.sampleRate)!
        startSample = track.start.toSample(atRate: sampleRate)
        endSample = min(track.end.toSample(atRate: sampleRate), Int(file.length))
        seek(to: .zero)
    }

    func seek(to time: CMTime) {
        var targetSample = time.toSample(atRate: sampleRate)
        targetSample += startSample
        targetSample = min(targetSample, endSample)
        file.framePosition = AVAudioFramePosition(targetSample)
    }

    func nextSampleBuffer() throws -> CMSampleBuffer? {
        let remainingFrames = endSample - Int(file.framePosition)
        let requestingFrames = min(remainingFrames, Self.maxFrameCount)
        guard requestingFrames > 0 else { return nil }
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(requestingFrames))!
        try file.read(into: buffer)
        let blockListBuffer = try CMBlockBuffer()
        for audioBuffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList)) {
            let dataByteSize = Int(audioBuffer.mDataByteSize)
            let blockBuffer = try CMBlockBuffer(length: dataByteSize)
            try blockBuffer.replaceDataBytes(
                with: UnsafeRawBufferPointer(start: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
            )
            try blockListBuffer.append(bufferReference: blockBuffer)
        }
        return try CMSampleBuffer(
            dataBuffer: blockListBuffer,
            formatDescription: buffer.format.formatDescription,
            numSamples: CMItemCount(buffer.frameLength),
            presentationTimeStamp: .zero,
            packetDescriptions: []
        )
    }

    private var sampleRate: Int {
        Int(exactly: file.processingFormat.sampleRate)!
    }
}

class FLACDecoder: AudioDecoder {
    static let supportedTypes = [UTType("org.xiph.flac")!]

    private let decoder: UnsafeMutablePointer<FLAC__StreamDecoder>
    private let source: URL
    private var error: Error?
    private var buffer: CMSampleBuffer?
    private var sampleRate: Int
    private var startSample: Int
    private var endSample: Int
    private var currentSample: Int
    private var seeking = false
    private var formatDescription: CMAudioFormatDescription?
    private var streamInfo: FLAC__StreamMetadata_StreamInfo?

    struct AudioDecodingError: Error {
        let url: URL
    }

    required init(track: Track) throws {
        source = track.source
        startSample = 0
        endSample = 0
        currentSample = 0
        sampleRate = 0
        let error = AudioDecodingError(url: source)
        decoder = FLAC__stream_decoder_new()!
        if try track.source.withUnsafeFileSystemRepresentation({
            guard let filename = $0 else { throw FileNotFound(url: track.source) }
            return FLAC__stream_decoder_init_file(decoder, filename, { decoder, frame, buffer, client in
                let this = Unmanaged<FLACDecoder>.fromOpaque(client!).takeUnretainedValue()
                if !this.seeking {
                    do {
                        try this.writeCallback(frame: frame!.pointee, buffer: buffer!)
                    } catch let error {
                        this.error = error
                        return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT
                    }
                }
                return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE
            }, { decoder, metadata, client in
                let this = Unmanaged<FLACDecoder>.fromOpaque(client!).takeUnretainedValue()
                let streamInfo = metadata!.pointee.data.stream_info
                this.endSample = Int(streamInfo.total_samples)
                this.sampleRate = Int(streamInfo.sample_rate)
                var asbd = AudioStreamBasicDescription(
                    mSampleRate: Float64(streamInfo.sample_rate),
                    mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsSignedInteger,
                    mBytesPerPacket: 4 * streamInfo.channels,
                    mFramesPerPacket: 1,
                    mBytesPerFrame: 4 * streamInfo.channels,
                    mChannelsPerFrame: streamInfo.channels,
                    mBitsPerChannel: streamInfo.bits_per_sample,
                    mReserved: 0
                )
                var layout = AudioChannelLayout()
                switch streamInfo.channels {
                case 1:
                    layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
                case 2:
                    layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
                case 3:
                    layout.mChannelLayoutTag = kAudioChannelLayoutTag_WAVE_3_0
                case 4:
                    layout.mChannelLayoutTag = kAudioChannelLayoutTag_WAVE_4_0_B
                case 5:
                    layout.mChannelLayoutTag = kAudioChannelLayoutTag_WAVE_5_0_A
                case 6:
                    layout.mChannelLayoutTag = kAudioChannelLayoutTag_WAVE_5_1_A
                case 7:
                    layout.mChannelLayoutTag = kAudioChannelLayoutTag_WAVE_6_1
                case 8:
                    layout.mChannelLayoutTag = kAudioChannelLayoutTag_WAVE_7_1
                default:
                    fatalError("Unsupported channel layout.")
                }
                let status = CMAudioFormatDescriptionCreate(
                    allocator: kCFAllocatorDefault,
                    asbd: &asbd,
                    layoutSize: 1,
                    layout: &layout,
                    magicCookieSize: 0,
                    magicCookie: nil,
                    extensions: nil,
                    formatDescriptionOut: &this.formatDescription
                )
                guard status == noErr else {
                    fatalError()
                }
                this.streamInfo = streamInfo
            }, { decoder, status, client in
                let this = Unmanaged<FLACDecoder>.fromOpaque(client!).takeUnretainedValue()
                this.errorCallback()
            }, Unmanaged<FLACDecoder>.passUnretained(self).toOpaque())
        }) != FLAC__STREAM_DECODER_INIT_STATUS_OK {
            throw error
        }
        guard FLAC__stream_decoder_process_until_end_of_metadata(decoder) != 0 else {
            throw self.error ?? error
        }
        startSample = track.start.toSample(atRate: sampleRate)
        endSample = min(endSample, track.end.toSample(atRate: sampleRate))
        seek(to: .zero)
    }

    deinit {
        FLAC__stream_decoder_delete(decoder)
    }

    private func writeCallback(frame: FLAC__Frame, buffer: UnsafePointer<UnsafePointer<Int32>?>) throws {
        guard let streamInfo,
                frame.header.bits_per_sample == streamInfo.bits_per_sample &&
                frame.header.channels == streamInfo.channels &&
                frame.header.sample_rate == streamInfo.sample_rate else {
            fatalError()
        }
        let blocksize = Int(frame.header.blocksize)
        let channels = Int(frame.header.channels)
        let totalLength = blocksize * 4 * channels
        let dataBuffer = CFAllocatorAllocate(kCFAllocatorDefault, totalLength, 0)!
        let dataArray = dataBuffer.assumingMemoryBound(to: Int32.self)
        for j in 0 ..< channels {
            let channelBuffer = buffer[j]!
            for i in 0 ..< blocksize {
                dataArray[i * channels + j] = channelBuffer[i]
            }
        }
        let blockBuffer = try CMBlockBuffer(buffer: UnsafeMutableRawBufferPointer(start: dataBuffer, count: totalLength))
        let sampleBuffer = try CMSampleBuffer(
            dataBuffer: blockBuffer,
            formatDescription: formatDescription!,
            numSamples: blocksize,
            presentationTimeStamp: .zero,
            packetDescriptions: []
        )
        self.buffer = sampleBuffer
        let previousSample = Int(frame.header.number.sample_number)
        self.currentSample = previousSample + blocksize
    }

    private func errorCallback() {
        error = AudioDecodingError(url: source)
    }

    func nextSampleBuffer() throws -> CMSampleBuffer? {
        defer {
            buffer = nil
            error = nil
        }
        let remainingSample = endSample - currentSample
        guard remainingSample > 0 else {
            return nil
        }
        guard FLAC__stream_decoder_process_single(decoder) != 0 else {
            throw error ?? AudioDecodingError(url: source)
        }
        let gotSample = buffer!.numSamples
        if gotSample > remainingSample {
            buffer = try CMSampleBuffer(copying: buffer!, forRange: 0 ..< remainingSample)
        }
        return buffer!
    }

    func seek(to time: CMTime) {
        var targetSample = Int(time.convertScale(Int32(sampleRate), method: .default).value)
        targetSample += startSample
        targetSample = min(targetSample, endSample)
        seeking = true
        FLAC__stream_decoder_seek_absolute(decoder, UInt64(targetSample))
        seeking = false
        currentSample = targetSample
    }
}
