import Foundation
import Combine
import SwiftUI
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
    return try Data(contentsOf: url)
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

fileprivate func errnoError() -> Error {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
}

class FileReader {
    private var file: UnsafeMutablePointer<FILE>

    func read(count: Int) -> Data? {
        guard count >= 0 else { return nil }
        var buffer = Data(count: count)
        let readCount = buffer.withUnsafeMutableBytes { ptr in
            fread(ptr.baseAddress, 1, count, file)
        }
        guard readCount == count else {
            if ferror(file) != 0 {
                fatalError(errnoError().localizedDescription)
            } else {
                return nil
            }
        }
        return buffer
    }

    func skip(count: Int) -> Bool {
        return fseek(file, count, SEEK_CUR) == 0
    }

    init(url: URL) throws {
        guard let file = url.withUnsafeFileSystemRepresentation({ ptr in
            fopen(ptr, "r")
        }) else {
            throw errnoError()
        }
        self.file = file
    }

    deinit {
        guard fclose(file) == 0 else {
            fatalError(errnoError().localizedDescription)
        }
    }
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

    func makeDictionary() -> [Element.ID: Element] {
        Dictionary(uniqueKeysWithValues: map { ($0.id, $0) })
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

    var normalizedURL: URL {
        isFileURL ? standardizedFileURL : absoluteURL
    }

    var normalizedString: String {
        normalizedURL.description
    }

    var pathDescription: String {
        isFileURL ? path(percentEncoded: false) : description
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

@MainActor
class SerialAsyncQueue {
    private var processing = false
    private var queue = Deque<() async -> ()>()

    private func processNext() {
        assert(!processing)
        guard let nextOperation = queue.popFirst() else { return }
        processing = true
        Task.detached {
            await nextOperation()
            DispatchQueue.main.async {
                self.processing = false
                self.processNext()
            }
        }
    }

    func enqueue(_ operation: @Sendable @escaping () async -> ()) {
        queue.append(operation)
        if !processing {
            processNext()
        }
    }
}

extension Color {
    static let labelColor = Color(nsColor: .labelColor)
    static let secondaryLabelColor = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabelColor = Color(nsColor: .tertiaryLabelColor)
    static let quaternaryLabelColor = Color(nsColor: .quaternaryLabelColor)

    static let textColor = Color(nsColor: .textColor)
    static let placeholderTextColor = Color(nsColor: .placeholderTextColor)
    static let selectedTextColor = Color(nsColor: .selectedTextColor)
    static let textBackgroundColor = Color(nsColor: .textBackgroundColor)
    static let selectedTextBackgroundColor = Color(nsColor: .selectedTextBackgroundColor)
    static let keyboardFocusIndicatorColor = Color(nsColor: .keyboardFocusIndicatorColor)
    static let unemphasizedSelectedTextColor = Color(nsColor: .unemphasizedSelectedTextColor)
    static let unemphasizedSelectedTextBackgroundColor = Color(nsColor: .unemphasizedSelectedTextBackgroundColor)

    static let linkColor = Color(nsColor: .linkColor)
    static let separatorColor = Color(nsColor: .separatorColor)
    static let selectedContentBackgroundColor = Color(nsColor: .selectedContentBackgroundColor)
    static let unemphasizedSelectedContentBackgroundColor = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)

    static let selectedMenuItemTextColor = Color(nsColor: .selectedMenuItemTextColor)

    static let gridColor = Color(nsColor: .gridColor)
    static let headerTextColor = Color(nsColor: .headerTextColor)
    static let alternatingContentBackgroundColors = NSColor.alternatingContentBackgroundColors.map { Color(nsColor: $0) }

    static let controlAccentColor = Color(nsColor: .controlAccentColor)
    static let controlColor = Color(nsColor: .controlColor)
    static let controlBackgroundColor = Color(nsColor: .controlBackgroundColor)
    static let controlTextColor = Color(nsColor: .controlTextColor)
    static let disabledControlTextColor = Color(nsColor: .disabledControlTextColor)

    static let selectedControlColor = Color(nsColor: .selectedControlColor)
    static let selectedControlTextColor = Color(nsColor: .selectedControlTextColor)
    static let alternateSelectedControlTextColor = Color(nsColor: .alternateSelectedControlTextColor)
    static let scrubberTexturedBackground = Color(nsColor: .scrubberTexturedBackground)

    static let windowBackgroundColor = Color(nsColor: .windowBackgroundColor)
    static let windowFrameTextColor = Color(nsColor: .windowFrameTextColor)
    static let underPageBackgroundColor = Color(nsColor: .underPageBackgroundColor)

    static let findHighlightColor = Color(nsColor: .findHighlightColor)
    static let highlightColor = Color(nsColor: .highlightColor)
    static let shadowColor = Color(nsColor: .shadowColor)
}

extension Color {
    static let selectedBackgroundColor = Color.quaternaryLabelColor
    static let interactiveBackgroundColor = Color.selectedBackgroundColor.opacity(0.5)
}

extension View {
    func onAnimatedValue<T: Equatable>(of value: T, onAppear: Bool = true, perform: @escaping (T) -> ()) -> some View {
        self
            .onChange(of: value) { value in
                withAnimation { perform(value) }
            }
            .onAppear {
                if onAppear {
                    perform(value)
                }
            }
    }
}
