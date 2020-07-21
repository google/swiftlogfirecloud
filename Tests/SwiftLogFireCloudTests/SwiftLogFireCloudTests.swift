import Logging
import XCTest

@testable import SwiftLogFireCloud

var loggerIsBootstrapped = false

// Note that these tests use the actual file system, which does create some state interaction
// between tests, but I've tried to minimize this by cleanign the file system in tear down.
// However, this is not entire determnistic tho, as the library is async fire and forget for logging,
// so there are time dependencies on library behaviour and the tests try to respect these without
// any call backs (fire and forget, remember?).  For example, the processing of stranded files test
// shortens the delay of recouping these files to 5s, and has expectations in the test to wait
// for this processing to happen.  However, shortenign this would then have the stranded file processing'
// recoup files that are written as the tests and checked for validity if they don't complete before
// that stranded file processing.  So the expectation wait times here are configured to work but are
// admittedly in a narrow time window.  I do however find the test for value utilizing the DispatchIO
// methods as they do to in production which is why I have not abastracted away the file system for testing.

final class SwiftLogFireCloudTests: XCTestCase {

  let fakeClientUploader = FakeClientCloudUploader()
  var config = SwiftLogFireCloudConfig(
    logToCloud: true,
    localFileSizeThresholdToPushToCloud: 100,
    logToCloudOnSimulator: true,
    cloudUploader: nil)
  let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
  let swiftLogFileCloudManager = SwiftLogFileCloudManager()
  var testFileSystemHelpers: TestFileSystemHelpers!
  var logger: Logger!

  override func setUp() {
    
    config.cloudUploader = fakeClientUploader
    if !loggerIsBootstrapped {
      LoggingSystem.bootstrap(swiftLogFileCloudManager.makeLogHandlerFactory(config: config))
      loggerIsBootstrapped = true
    }

    swiftLogFileCloudManager.setLogToCloud(true)
    testFileSystemHelpers = TestFileSystemHelpers(path: paths[0], config: config)
    testFileSystemHelpers.createLocalLogDirectory()
  }

  override func tearDown() {
    testFileSystemHelpers.deleteAllLogFiles()
    testFileSystemHelpers.removeLogDirectory()
    logger = nil
  }

  func testForNoCrashOnFirstLogAndContentsContained() {
    // if the logging system is bootstrapped correctly, this should silently just log
    // otherwise it will crash, which is a test failure
    config.cloudUploader = nil
    logger = Logger(label: "testLogger")
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
  
  func testForNoLogWrittenWhenDisabled() {
    logger = Logger(label: "testLogger")
    swiftLogFileCloudManager.setLogToCloud(false)
    let writeString = "I want this logger to do something"

    logger.log(level: .info, "\(writeString)")

    let expectation = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 3)
    let directoryContents = testFileSystemHelpers.logFileDirectoryContents()
    XCTAssert(directoryContents.count == 0)
  }
  
  func testForLoggingResumptionWhenReEnabled() {
    logger = Logger(label: "testLogger")
    swiftLogFileCloudManager.setLogToCloud(false)
    let writeString = "I want this logger to do something"

    logger.log(level: .info, "\(writeString)")

    let expectationWithLoggingOff = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectationWithLoggingOff.fulfill()
    }

    wait(for: [expectationWithLoggingOff], timeout: 3)
    XCTAssert(testFileSystemHelpers.logFileDirectoryContents().count == 0)

    swiftLogFileCloudManager.setLogToCloud(true)
    logger.log(level: .info, "\(writeString)")

    let expectationWithLoggingOn = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectationWithLoggingOn.fulfill()
    }

    wait(for: [expectationWithLoggingOn], timeout: 3)
    let directoryContents = testFileSystemHelpers.logFileDirectoryContents()
    var readString = ""
    if directoryContents.count >= 1 {
      readString = testFileSystemHelpers.readDummyLogFile(url: directoryContents[0])!
    }
    XCTAssert(directoryContents.count == 1)
    XCTAssert(readString.contains(writeString))
  }

  func testForMultipleLoggersNotCollidingOnDisk() {
    config.cloudUploader = nil
    logger = Logger(label: "testLogger")
    logger.info("This is a testLogger1 message")
    let secondLogger = Logger(label: "testLogger2")
    secondLogger.info("This is a testLogger2 message")

    // all log writes happen asynchronously in a fire and forget manner, so no
    // means to ensure completion besides waiting
    let expectation = XCTestExpectation(description: "oneLocalFileWrite")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 2)

    let resultingLogFileCount = testFileSystemHelpers.logFileDirectoryFileCount()
    XCTAssertTrue(resultingLogFileCount == 2)
  }
  
  func testForCloudUploadAndFileDeleted() {
    logger = Logger(label: "testLogger")
    let fakeClientUploader = config.cloudUploader as! FakeClientCloudUploader
    fakeClientUploader.mimicSuccessUpload = true

    testFileSystemHelpers.flood(logger: logger)

    let localWriteExpectation = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      localWriteExpectation.fulfill()
    }

    wait(for: [localWriteExpectation], timeout: 3)
    logger.info("I'm a message that should trigger the cloud upload")

    let cloudWriteExpectation = XCTestExpectation(description: "Wait for Cloud write of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      cloudWriteExpectation.fulfill()
    }
    wait(for: [cloudWriteExpectation], timeout: 3)
    XCTAssert(fakeClientUploader.successUploadCount == 1)
    XCTAssertFalse(testFileSystemHelpers.logFileDirectoryContents().contains(fakeClientUploader.successUploadURLs[0]))
    //Note that there is still a log file in the directory, the one created by the 2nd log which triggers the cloud check.
  }
  
  func testForQueingOfStrandedFiles() {
    _ = testFileSystemHelpers.writeDummyLogFile(fileName: "StrandedFile1.log")
    _ = testFileSystemHelpers.writeDummyLogFile(fileName: "StrandedFile2.log")
    logger = Logger(label: "EmptyLogger")
    let fakeClientUploader = config.cloudUploader as! FakeClientCloudUploader
    fakeClientUploader.mimicSuccessUpload = true

    // the library delays for 5s then will look for log files in the directory, and attempt to upload them once per second

    let expectation = XCTestExpectation(description: "Wait for stranded file processing to start & complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 15)
    XCTAssert(testFileSystemHelpers.logFileDirectoryFileCount() == 0)

  }

  static var allTests = [
    ("testForNoCrashOnFirstLogAndContentsContained", testForNoCrashOnFirstLogAndContentsContained),
    ("testForNoLogWrittenWhenDisabled", testForNoLogWrittenWhenDisabled),
    ("testForLoggingResumptionWhenReEnabled", testForLoggingResumptionWhenReEnabled),
    ("testForMultipleLoggersNotCollidingOnDisk", testForMultipleLoggersNotCollidingOnDisk)
  ]
}
