import Foundation

struct AsyncReader<T: AsyncSequence> where T.Element == UInt8
{
    var seq: T
    var iter: T.AsyncIterator

    struct ContentInsufficient: Error {}

    init(_ seq: T) {
        self.seq = seq
        self.iter = seq.makeAsyncIterator()
    }

    mutating func read(count: Int) async throws -> Data {
        var buffer = Data(capacity: count)
        for _ in 0 ..< count {
            guard let byte = try await self.iter.next() else { break }
            buffer.append(contentsOf: [byte])
        }
        return buffer
    }

    mutating func readEnough(count: Int) async throws -> Data {
        let buffer = try await read(count: count)
        if buffer.count != count {
            throw ContentInsufficient()
        }
        return buffer
    }
}
