import Foundation
import Combine
import UniformTypeIdentifiers
import Collections

func stringEncoding(for data: Data) -> String.Encoding? {
    let encodingValue = NSString.stringEncoding(for: data, convertedString: nil, usedLossyConversion: nil)
    if encodingValue == 0 {
        return nil
    } else {
        return String.Encoding(rawValue: encodingValue)
    }
}

func readData(from url: URL) throws -> Data {
    return try Data(contentsOf: url, options: [.alwaysMapped])
}

struct FileDecodingError: Error {
    let url: URL
}

func readString(from url: URL) throws -> String {
    let data = try readData(from: url)
    let encoding = stringEncoding(for: data) ?? .utf8
    guard let string = String(data: data, encoding: encoding) else {
        throw FileDecodingError(url: url)
    }
    return string
}

fileprivate extension UInt64 {
    init(bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) {
        self =
            UInt64(bytes.0) << 56 |
            UInt64(bytes.1) << 48 |
            UInt64(bytes.2) << 40 |
            UInt64(bytes.3) << 32 |
            UInt64(bytes.4) << 24 |
            UInt64(bytes.5) << 16 |
            UInt64(bytes.6) << 8 |
            UInt64(bytes.7)
    }
}

extension UUID: Comparable {
    public static func < (lhs: UUID, rhs: UUID) -> Bool {
        let lu = lhs.uuid
        let ru = rhs.uuid
        let lh = UInt64(bytes: (lu.0, lu.1, lu.2, lu.3, lu.4, lu.5, lu.6, lu.7))
        let rh = UInt64(bytes: (ru.0, ru.1, ru.2, ru.3, ru.4, ru.5, ru.6, ru.7))
        let ll = UInt64(bytes: (lu.8, lu.9, lu.10, lu.11, lu.12, lu.13, lu.14, lu.15))
        let rl = UInt64(bytes: (ru.8, ru.9, ru.10, ru.11, ru.12, ru.13, ru.14, ru.15))
        if lh != rh {
            return lh < rh
        } else {
            return ll < rl
        }
    }
}

protocol EquatableIdentifiable: Identifiable, Equatable {}

extension EquatableIdentifiable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }
}

extension Array where Element: Identifiable {
    func get(by id: Element.ID) -> Element? {
        first { $0.id == id }
    }
}

extension Array where Element: Identifiable {
    func dropDuplicates() -> Self {
        var r: Self = []
        var s: Set<Element.ID> = []
        for elem in self {
            if s.contains(elem.id) { continue }
            r.append(elem)
            s.insert(elem.id)
        }
        return r
    }
}

extension URL {
    mutating func replacePathExtension(_ pathExtension: String) {
        deletePathExtension()
        appendPathExtension(pathExtension)
    }

    func replacingPathExtension(_ pathExtension: String) -> Self {
        deletingPathExtension().appendingPathExtension(pathExtension)
    }

    var pathDescription: String {
        isFileURL ? path : description
    }

    var isDirectory: Bool? {
        try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory
    }

    var type: UTType? {
        UTType(filenameExtension: pathExtension)
    }

    func conforms(to type: UTType) -> Bool {
        guard let thisType = self.type else { return false }
        return thisType.conforms(to: type)
    }

    func conformsAny(to types: [UTType]) -> Bool {
        guard let thisType = self.type else { return false }
        return types.contains { thisType.conforms(to: $0) }
    }
}

extension Publisher {
    func withPrevious() -> some Publisher<(previous: Output?, current: Output), Failure> {
        scan(Optional<(Output?, Output)>.none) { ($0?.1, $1) }
            .compactMap { $0 }
    }

    func receiveOnMain() -> some Publisher<Output, Failure> {
        receive(on: RunLoop.main)
    }
}

protocol FileError: Error, CustomStringConvertible {
    var url: URL { get }
    static var prompt: String { get }
}

extension FileError {
    var description: String {
        "\(Self.prompt): \(url.pathDescription)"
    }
}

struct InvalidFormat: FileError {
    let url: URL
    static let prompt = "Invalid format"
}

struct FileNotFound: FileError {
    let url: URL
    static let prompt = "File not found"
}

func makeMonotonicUUID() -> UUID {
    let time = UInt64(Date.timeIntervalSinceReferenceDate * 1_000_000)
    let random = UInt64.random(in: 0 ... UInt64.max)
    var data = Data(count: 16)
    let uuid = data.withUnsafeMutableBytes { ptr in
        let array = ptr.assumingMemoryBound(to: UInt64.self)
        array[0] = time.bigEndian
        array[1] = random
        return NSUUID(uuidBytes: ptr.baseAddress)
    }
    return uuid as UUID
}

fileprivate let universalSeparators = CharacterSet(charactersIn: ",;，；、\r\n")

func universalSplit(_ s: String) -> [String] {
    s
        .components(separatedBy: universalSeparators)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

struct BookmarkDataDecodingError: Error {}

func dumpURLToBookmark(_ url: URL) throws -> Data {
    return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
}

func loadURLFromBookmark(_ bookmark: Data) throws -> URL {
    var isStale = false
    let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
    guard !isStale && url.startAccessingSecurityScopedResource() else {
        throw BookmarkDataDecodingError()
    }
    return url
}

actor SerialAsyncQueue {
    private var processing = false
    private var queue = Deque<() async -> ()>()

    private func process() async {
        guard !processing else { return }
        processing = true
        while let operation = queue.popFirst() {
            let _ = await Task.detached {
                await operation()
            }.result
        }
        processing = false
    }

    func enqueue(_ operation: @Sendable @escaping () async -> ()) {
        queue.append(operation)
        Task {
            await process()
        }
    }
}
