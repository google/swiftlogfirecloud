import XCTest
import Logging
@testable import SwiftLogFireCloud

var loggerIsBootstrapped = false
var logger: Logger?

final class SwiftLogFireCloudTests: XCTestCase {
    
    let swiftLogFileCloudManager = SwfitLogFileCloudManager()
    
    override func setUp() {
        if !loggerIsBootstrapped {
            LoggingSystem.bootstrap(swiftLogFileCloudManager.makeLogHandlerFactory(config: SwiftLogFileCloudConfig()))
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
    static var allTests = [
        ("testForNoCrashOnFirstLog", testForNoCrashOnFirstLog),
        ("testForFlushingLogToCloud", testForFlushingLogToCloud),
        ("testForManagerFlushingLogToCloud", testForManagerFlushingLogToCloud),
    ]
}
