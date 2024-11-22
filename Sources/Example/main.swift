import JSONLogger
import Logging

LoggingSystem.bootstrap { label in 
    JsonStreamLogHandler.standardOutput(label: label)
}

let logger = Logger(label: "test")

logger.info("test message")