import XCTest
import Logging
@testable import SwiftLogFireCloud

final class SwiftLogFireCloudTests: XCTestCase {
    
    var loggerIsBootstrapped = false
    let swiftLogFileCloudManager = SwfitLogFileCloudManager()
    
    override func setUp() {
        if !loggerIsBootstrapped {
            LoggingSystem.bootstrap(swiftLogFileCloudManager.makeLogHandlerFactory(config: SwiftLogFileCloudConfig()))
        }
    }
    func testForNoCrashOnFirstLog() {
        let logger = Logger(label: "testLogger")
        logger.log(level: .info, "I want this logger to do something")
    }

    static var allTests = [
        ("testForNoCrashOnFirstLog", testForNoCrashOnFirstLog),
    ]
}
