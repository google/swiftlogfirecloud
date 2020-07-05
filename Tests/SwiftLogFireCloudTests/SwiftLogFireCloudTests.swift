import Logging
import XCTest

@testable import SwiftLogFireCloud

var loggerIsBootstrapped = false
var logger: Logger?

final class SwiftLogFireCloudTests: XCTestCase {

  let config = SwiftLogFileCloudConfig(
    logToCloud: true, localFileSizeThresholdToPushToCloud: 100,
    localFileBufferWriteInterval: nil, uniqueID: nil)
  let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
  let swiftLogFileCloudManager = SwfitLogFileCloudManager()
  var testFileSystemHelpers: TestFileSystemHelpers!

  override func setUp() {
    if !loggerIsBootstrapped {
      LoggingSystem.bootstrap(swiftLogFileCloudManager.makeLogHandlerFactory(config: config))
      loggerIsBootstrapped = true
    }
    if logger == nil {
      logger = Logger(label: "testLogger")
    }
    testFileSystemHelpers = TestFileSystemHelpers(path: paths[0], config: config)
    testFileSystemHelpers.createLocalLogDirectory()
  }

  override func tearDown() {
    testFileSystemHelpers.deleteAllLogFiles()
    testFileSystemHelpers.removeLogDirectory()
  }

  func testForNoCrashOnFirstLog() {
    // if the logging system is bootstrapped correctly, this should silently just log
    // otherwise it will crash, which is a test failuree
    logger?.log(level: .info, "I want this logger to do something")
  }

  func testForWriteOfLocalFile() {
    testFileSystemHelpers.flood(logger: logger!)

    // all log writes happen asynchronously in a fire and forget manner, so no
    // means to ensure completion besides waiting
    let expectation = XCTestExpectation(description: "oneLocalFileWrite")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 3)
    let resultingLogFileCount = testFileSystemHelpers.logFileDirectoryFileCount()
    XCTAssertTrue(resultingLogFileCount == 1)
  }

  func testForMultipleLoggersNotCollidingOnDisk() {
    testFileSystemHelpers.flood(logger: logger!)
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
    ("testForNoCrashOnFirstLog", testForNoCrashOnFirstLog)
  ]
}
