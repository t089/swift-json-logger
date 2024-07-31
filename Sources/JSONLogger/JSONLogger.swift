import JSON
import JSONEncoding
import Logging
#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import CRT
#elseif canImport(Glibc)
#if compiler(>=6.0)
@preconcurrency import Glibc
#else
import Glibc
#endif
#elseif canImport(Musl)
import Musl
#elseif canImport(WASILibc)
import WASILibc
#else
#error("Unsupported runtime")
#endif


public struct JsonStreamLogHandler: LogHandler {
    public struct Configuration: Sendable {
        public var metadataKey: String
        public var timestampKey: String

        public init(metadataKey: String = "metadata", timestampKey: String = "timestamp") {
            self.metadataKey = metadataKey
            self.timestampKey = timestampKey
        }
    }

    /// Factory that makes a `StreamLogHandler` to directs its output to `stdout`
    public static func standardOutput(label: String, configuration: Configuration = .init()) -> JsonStreamLogHandler {
        return JsonStreamLogHandler(label: label, configuration: configuration, stream: StdioOutputStream.stdout)
    }

    /// Factory that makes a `StreamLogHandler` to directs its output to `stderr`
    public static func standardError(label: String, configuration: Configuration = .init()) -> JsonStreamLogHandler {
        return JsonStreamLogHandler(label: label, configuration: configuration, stream: StdioOutputStream.stderr)
    }

    private let stream: any TextOutputStream
    private let label: String
    private let config: Configuration

    public init(label: String, configuration: Configuration = .init(), stream: any TextOutputStream) {
        self.label = label
        self.stream = stream
        self.config = configuration
    }

    public var logLevel: Logger.Level = .info

    public var metadata = Logger.Metadata() {
        didSet {
            self.metadataJson = self.jsonfy(self.metadata)
        }
    }

    public var metadataProvider: Logger.MetadataProvider?
    
    private var metadataJson: JSON.Object?

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {
        var stream = self.stream
        
        var jsonObject : JSON.Object = [
            .init(rawValue: "\(self.config.timestampKey)"): .string(.init(self.timestamp())),
            "level": .string(.init("\(level)")),
            "message": .string(.init("\(message)")),
            "logger_label": .string(.init(self.label)),
            "source": .string(.init(source)),
            "file": .string(.init(file)),
            "function": .string(.init(function)),
            "line": .number(.init(line))
        ]

        let effectiveMetadata = Self.prepareMetadata(base: self.metadata, provider: self.metadataProvider, explicit: metadata)
        
        let jsonMetadata : JSON.Object?
        if let effectiveMetadata {
            jsonMetadata = self.jsonfy(effectiveMetadata)
        } else {
            jsonMetadata = self.metadataJson
        }
        
        if let meta = jsonMetadata {
            jsonObject[.init(rawValue: self.config.metadataKey)] = .object(meta)
        }
        
        stream.write("\(jsonObject)\n")
    }

    internal static func prepareMetadata(base: Logger.Metadata, provider: Logger.MetadataProvider?, explicit: Logger.Metadata?) -> Logger.Metadata? {
        var metadata = base

        let provided = provider?.get() ?? [:]

        guard !provided.isEmpty || !((explicit ?? [:]).isEmpty) else {
            // all per-log-statement values are empty
            return nil
        }

        if !provided.isEmpty {
            metadata.merge(provided, uniquingKeysWith: { _, provided in provided })
        }

        if let explicit = explicit, !explicit.isEmpty {
            metadata.merge(explicit, uniquingKeysWith: { _, explicit in explicit })
        }

        return metadata
    }
    
    private func jsonfy(_ metadata: Logger.Metadata) -> JSON.Object? {
        guard  !metadata.isEmpty else { return nil }
        
        return metadata.lazy.sorted(by: { $0.key < $1.key }).reduce(into: JSON.Object()) { json, meta in
            json.fields.append((key: .init(rawValue: "\(meta.key)"), value: meta.value.json))
        }
    }
    
    private func timestamp() -> String {
        var buffer = [Int8](repeating: 0, count: 255)
        #if os(Windows)
        var timestamp: __time64_t = __time64_t()
        _ = _time64(&timestamp)

        var localTime: tm = tm()
        _ = _localtime64_s(&localTime, &timestamp)

        _ = strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", &localTime)
        #else

        var tv = timeval()
        gettimeofday(&tv, nil)

        var localTime = tm()
        localtime_r(&tv.tv_sec, &localTime)

        let lengthOfPrefix = strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S", &localTime)
        precondition(lengthOfPrefix > 0, "strftime failed")

        let microseconds = tv.tv_usec
        let offset = localTime.tm_gmtoff
        let hours = offset / 3600
        let minutes = abs(offset % 3600 / 60)

        buffer.withUnsafeBufferPointer { 
            $0.withMemoryRebound(to: CChar.self) {
                let secondPartStart = $0.baseAddress!.advanced(by: lengthOfPrefix)
                let secondPartSize = buffer.count - lengthOfPrefix

                precondition(secondPartSize >= 0)

                withVaList([ microseconds, hours, minutes ]) { args in 
                    _ = vsnprintf(UnsafeMutablePointer(mutating: secondPartStart), secondPartSize, ".%06d%+03d%02d", args)
                }
            }
        }

        #endif
        return buffer.withUnsafeBufferPointer {
            $0.withMemoryRebound(to: CChar.self) {
                String(cString: $0.baseAddress!)
            }
        }
    }
}


extension Logger.MetadataValue {
    var json: JSON.Node {
        switch self {
        case .string(let v): return .string(.init(v))
        case .stringConvertible(let v): return .string(.init("\(v)"))
        case .array(let values): return .array(.init(values.map({ $0.json })))
        case .dictionary(let dict): return .object(.init(dict.map({(key: JSON.Key(rawValue: $0.key), value: $0.value.json)})))
        }
    }
}


extension JSON.Object {
    subscript(key: JSON.Key) -> JSON.Node? {
        get {
            if let idx = self.firstIndex(where: { $0.key == key.rawValue }) {
                return self.fields[idx].value
            } else {
                return nil
            }
        }
        set {
            if let idx = self.firstIndex(where: { $0.key == key.rawValue }) {
                if let newValue {
                    self.fields[idx].value = newValue
                } else {
                    self.fields.remove(at: idx)
                }
            } else {
                if let newValue {
                    self.fields.append((key: key, value: newValue))
                }
            }
        }
    }
}