import Logging
import XCTest

@testable import SwiftLogFireCloud

var loggerIsBootstrapped = false


final class SwiftLogFireCloudTests: XCTestCase {

  let config = SwiftLogFireCloudConfig(
    logToCloud: true,
    localFileSizeThresholdToPushToCloud: 100,
    cloudUploader: nil)
  let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
  let swiftLogFileCloudManager = SwiftLogFileCloudManager()
  var testFileSystemHelpers: TestFileSystemHelpers!
  var logger: Logger!

  override func setUp() {
    
    if !loggerIsBootstrapped {
      LoggingSystem.bootstrap(swiftLogFileCloudManager.makeLogHandlerFactory(config: config))
      loggerIsBootstrapped = true
    }
    logger = Logger(label: "testLogger")
    testFileSystemHelpers = TestFileSystemHelpers(path: paths[0], config: config)
    testFileSystemHelpers.createLocalLogDirectory()
  }

  override func tearDown() {
    testFileSystemHelpers.deleteAllLogFiles()
    testFileSystemHelpers.removeLogDirectory()
  }

  func testForNoCrashOnFirstLog() {
    // if the logging system is bootstrapped correctly, this should silently just log
    // otherwise it will crash, which is a test failure
    let writeString = "I want this logger to do something"

    logger.log(level: .info, "\(writeString)")
    
    let expectation = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 3)
    let directoryContents = testFileSystemHelpers.logFileDirectoryContents()
    var readString = ""
    if directoryContents.count >= 1 {
      readString = testFileSystemHelpers.readDummyLogFile(url: directoryContents[0])!
    }
    XCTAssert(directoryContents.count == 1)
    XCTAssert(readString.contains(writeString))
  }

  func testForMultipleLoggersNotCollidingOnDisk() {
    testFileSystemHelpers.flood(logger: logger)
    let secondLogger = Logger(label: "testLogger2")
    //secondLogger.info("This is a testLogger2 message")
    testFileSystemHelpers.flood(logger: secondLogger)

    // all log writes happen asynchronously in a fire and forget manner, so no
    // means to ensure completion besides waiting
    let expectation = XCTestExpectation(description: "oneLocalFileWrite")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 3)

    let resultingLogFileCount = testFileSystemHelpers.logFileDirectoryFileCount()
    XCTAssertTrue(resultingLogFileCount == 2)
  }

  static var allTests = [
    ("testForNoCrashOnFirstLog", testForNoCrashOnFirstLog),
    ("testForMultipleLoggersNotCollidingOnDisk", testForMultipleLoggersNotCollidingOnDisk)
  ]
}
