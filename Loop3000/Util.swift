import Foundation
import Combine

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

protocol Unicorn: Identifiable, Hashable {}

extension Unicorn {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}

extension Array where Element: Identifiable {
    func get(by id: Element.ID) -> Element? {
        first { $0.id == id }
    }
}

extension Array where Element: Hashable {
    func dropDuplicates() -> Self {
        var r: Self = []
        var s: Set<Element> = []
        for elem in self {
            if s.contains(elem) { continue }
            r.append(elem)
            s.insert(elem)
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
}

extension Publisher {
    func `await`<T>(_ f: @escaping (Output) async -> T) -> some Publisher<T, Failure> {
        flatMap { value -> Future<T, Failure> in
            Future { promise in
                Task {
                    let result = await f(value)
                    promise(.success(result))
                }
            }
        }
    }
}

extension Publisher {
    func withPrevious() -> some Publisher<(previous: Output?, current: Output), Failure> {
        scan(Optional<(Output?, Output)>.none) { ($0?.1, $1) }
            .compactMap { $0 }
    }

    func withPrevious(_ initialPreviousValue: Output) -> some Publisher<(previous: Output, current: Output), Failure> {
        scan((initialPreviousValue, initialPreviousValue)) { ($0.1, $1) }
    }
}

actor AsyncQueue {
    func perform(_ operation: () async -> ()) async {
        await operation()
    }
}

struct InvalidFormat: Error, CustomStringConvertible {
    let url: URL
    private var pathDescription: String {
        url.isFileURL ? url.path : url.description
    }
    var description: String {
        "Invalid format: '\(pathDescription)'"
    }
}

struct FileNotFound: Error, CustomStringConvertible {
    let url: URL
    private var pathDescription: String {
        url.isFileURL ? url.path : url.description
    }
    var description: String {
        "File not found: '\(pathDescription)'"
    }
}
