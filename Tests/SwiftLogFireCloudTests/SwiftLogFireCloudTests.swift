import XCTest
import Logging
@testable import SwiftLogFireCloud

var loggerIsBootstrapped = false
var logger: Logger?

final class SwiftLogFireCloudTests: XCTestCase {
    
    let swiftLogFileCloudManager = SwfitLogFileCloudManager()
    
    override func setUp() {
        if !loggerIsBootstrapped {
            let config = SwiftLogFileCloudConfig(logToCloud: true, localFileSizeThresholdToPushToCloud: nil, localFileBufferWriteInterval: nil, uniqueID: nil)
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
    
    static var allTests = [
        ("testForNoCrashOnFirstLog", testForNoCrashOnFirstLog),
    ]
}
