import XCTest
import JSON
@testable import JSONLogger

class CollectingTextOutputStream: TextOutputStream {
    var collected = ""
    
    func write(_ string: String) {
        collected += string
    }

    var lastLineAsJson: JSON.ObjectDecoder<JSON.Key>? {
        guard let lastLine = self.collected.split(separator: "\n").last else { return nil }
        return try? .init(indexing: JSON.Object(parsing: lastLine))
    }
}

final class JSONLoggerTests: XCTestCase {
    func testSimpleLogMessage() throws {
        let output = CollectingTextOutputStream()
        let logger = JsonStreamLogHandler(label: "Test", stream: output)
        logger.log(level: .warning, message: "Test message", metadata: nil, source: "source", file: "file", function: "function", line: 1337)
        let object = try JSON.Object(parsing: output.collected)
        let json = try JSON.ObjectDecoder<JSON.Key>(indexing: object)
        XCTAssertEqual("warning",      json["level"]?.value.as(String.self))
        XCTAssertEqual("Test message", json["message"]?.value.as(String.self))
        XCTAssertEqual("source", json["source"]?.value.as(String.self))
        XCTAssertEqual("file", json["file"]?.value.as(String.self))
        XCTAssertEqual("function", json["function"]?.value.as(String.self))
        XCTAssertEqual(1337, try? json["line"]?.value.as(UInt.self))
    }

    func testMultipleLogMessages() throws {
        let output = CollectingTextOutputStream()
        let logger = JsonStreamLogHandler(label: "Test", stream: output)

        for i in 0 ..< 10 {
            logger.log(level: .warning, message: "Test message \(i)", metadata: nil, source: "source \(i)", file: "file \(i)", function: "function \(i)", line: .init(i))
        }

        let timestampRegex = try Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}\\+[0-9]{4}")

        for (idx, line) in output.collected.split(separator: "\n").enumerated() {
            let object = try JSON.Object(parsing: line)
            let json = try JSON.ObjectDecoder<JSON.Key>(indexing: object)
            XCTAssertEqual("warning",      json["level"]?.value.as(String.self))
            XCTAssertEqual("Test message \(idx)", json["message"]?.value.as(String.self))
            XCTAssertEqual("source \(idx)", json["source"]?.value.as(String.self))
            XCTAssertEqual("file \(idx)", json["file"]?.value.as(String.self))
            XCTAssertEqual("function \(idx)", json["function"]?.value.as(String.self))
            XCTAssertEqual(idx, try? json["line"]?.value.as(Int.self))
            
            let timestamp = json["timestamp"]?.value.as(String.self) ?? ""
            XCTAssertNotNil(try! timestampRegex.firstMatch(in: timestamp))   
        }
    }

    func testLogMessageWithNewLine() {
        let output = CollectingTextOutputStream()
        let logger = JsonStreamLogHandler(label: "Test", stream: output)
        logger.log(level: .warning,
        message: """
        Test message
           That contains
           a lot of 

           newlines

           !!!
        """, metadata: nil, source: "source", file: "file", function: "function", line: 1337)
        
    }

    func testLogMessageWithMetadata() {
        let output = CollectingTextOutputStream()
        var logger = JsonStreamLogHandler(label: "Test", stream: output)
        logger[metadataKey: "test-key"] = "test value"

        logger.log(level: .info, message: "message", metadata: nil, source: "source", file: #file, function: #function, line: #line)

        let json = output.lastLineAsJson!

        XCTAssertEqual("test value", json["metadata"]?.value.object?["test-key"]?.as(String.self))
    }

    func testLogMessageWithMetadataAndExplicityMetadata() {
        let output = CollectingTextOutputStream()
        var logger = JsonStreamLogHandler(label: "Test", stream: output)
        logger[metadataKey: "test-key"] = "test value"

        logger.log(level: .info, message: "message", metadata: ["explicit_key": "explicit value"], source: "source", file: #file, function: #function, line: #line)

        let json = output.lastLineAsJson!

        XCTAssertEqual("test value", json["metadata"]?.value.object?["test-key"]?.as(String.self))
        XCTAssertEqual("explicit value", json["metadata"]?.value.object?["explicit_key"]?.as(String.self))
    }

    func testLogMessageWithMetadataAndExplicityMetadataAndProvider() {
        let output = CollectingTextOutputStream()
        var logger = JsonStreamLogHandler(label: "Test", stream: output)
        logger[metadataKey: "test-key"] = "test value"

        logger.metadataProvider = .init {
            ["provided": .string("provided value")]
        }

        logger.log(level: .info, message: "message", metadata: ["explicit_key": "explicit value"], source: "source", file: #file, function: #function, line: #line)

        let json = output.lastLineAsJson!

        XCTAssertEqual("test value", json["metadata"]?.value.object?["test-key"]?.as(String.self))
        XCTAssertEqual("explicit value", json["metadata"]?.value.object?["explicit_key"]?.as(String.self))
        XCTAssertEqual("provided value", json["metadata"]?.value.object?["provided"]?.as(String.self))
    }
}




