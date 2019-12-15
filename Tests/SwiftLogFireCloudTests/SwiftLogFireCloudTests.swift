import XCTest
import Logging
@testable import SwiftLogFireCloud

var loggerIsBootstrapped = false
var logger: Logger?

final class SwiftLogFireCloudTests: XCTestCase {
    
    let swiftLogFileCloudManager = SwfitLogFileCloudManager()
    
    override func setUp() {
        if !loggerIsBootstrapped {
            let config = SwiftLogFileCloudConfig(logToCloud: true, localFileBufferSize: nil, localFileBufferWriteInterval: nil, uniqueID: nil)
            LoggingSystem.bootstrap(swiftLogFileCloudManager.makeLogHandlerFactory(config: config))
            loggerIsBootstrapped = true
        }
        if logger == nil {
            logger = Logger(label: "testLogger")
        }
    }
    func testForNoCrashOnFirstLog() {
        logger?.log(level: .info, "I want this logger to do something")
    }

    func testForFlushingLogToCloud() {
        //because the client only knows it conforms to the Logger protocol, it is not visible.
        logger?.flushLogToCloudNow()
    }
    
    func testForManagerFlushingLogToCloud() {
        SwfitLogFileCloudManager.flushLogToCloudNow()
    }
    
    func testLogALotOfText() {
        for i in 1...8000000 {
            logger?.log(level: .info, "\(i) This is my long-ish test log statement.  It will be written many times to try to trigger the file flush")
        }
    }
    static var allTests = [
        ("testForNoCrashOnFirstLog", testForNoCrashOnFirstLog),
        ("testForFlushingLogToCloud", testForFlushingLogToCloud),
        ("testForManagerFlushingLogToCloud", testForManagerFlushingLogToCloud),
        ("testLogALotOfText", testLogALotOfText),
    ]
}
