/*
Copyright 2020 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import Logging
import XCTest

@testable import SwiftLogFireCloud

var loggerIsBootstrapped = false

// Note that these tests use the actual file system, which does create some state interaction
// between tests, but I've tried to minimize this by cleaning the file system in tear down and using
// unique log file directory names for each test. However, this is not entirely determnistic tho,
// as the library is async fire and forget for logging, so there are time dependencies on library behaviour
// and the tests try to respect these without any call backs (fire and forget, remember).  For example,
// the processing of stranded files test shortens the delay of recouping these files to 5s, and has
// expectations in the test to wait for this processing to happen.  However, shortening this would then have
// the stranded file processing recoup files that are written as the tests and checked for validity if they
// don't complete before that stranded file processing.  So the expectation wait times here are configured to
// work but are admittedly in a narrow time window.  I do however find the tests having value utilizing the
// DispatchIO methods as they do to in production which is why I have not abastracted away the file system
// for testing.

final class SwiftLogFireCloudTests: XCTestCase {

  let fakeClientUploader = FakeClientCloudUploader()
  var config: SwiftLogFireCloudConfig!
  let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
  let swiftLogFileCloudManager = SwiftLogFileCloudManager()
  var testFileSystemHelpers: TestFileSystemHelpers!
  var handler: SwiftLogFireCloud!
//  var logger: Logger!

  override func setUp() {
    config = SwiftLogFireCloudConfig(logToCloud: true,
                                     localFileSizeThresholdToPushToCloud: 100,
                                     logDirectoryName: UUID().uuidString,
                                     logToCloudOnSimulator: true,
                                     cloudUploader: fakeClientUploader)

    handler = SwiftLogFireCloud(label: "TestSwiftLogFireCloud", config: config)

    swiftLogFileCloudManager.setLogToCloud(true)
    testFileSystemHelpers = TestFileSystemHelpers(path: paths[0], config: config)
    testFileSystemHelpers.createLocalLogDirectory()
  }

  override func tearDown() {
    testFileSystemHelpers.deleteAllLogFiles()
    testFileSystemHelpers.removeLogDirectory()
  }
  

  func testForNoCrashOnFirstLogAndContentsContainedAndForcedToCloud() {
    // this technically is two integration tests, one to write a log message and ensure its
    // on disk, and 2nd to confirm it was forced to the cloud.  This is due to the fact
    // the logger bootstrapping can only happen once.  If separated, with only one config
    // sent to the single bootstrap, the tests of the handlers with background processing
    // will disrupt a subsequent test.
    
    if !loggerIsBootstrapped {
      LoggingSystem.bootstrap(swiftLogFileCloudManager.makeLogHandlerFactory(config: config))
      loggerIsBootstrapped = true
    }
    fakeClientUploader.mimicSuccessUpload = true
    let previousSuccessfulUploads = fakeClientUploader.successUploadCount
    let logger = Logger(label: "testLogger")
    let writeString = "I want this logger to do something"

    logger.info("\(writeString)")

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
    
    swiftLogFileCloudManager.flushLoggersToCloud()
    
    let cloudWriteExpectation = XCTestExpectation(description: "Wait for flushCloud to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      cloudWriteExpectation.fulfill()
    }

    wait(for: [cloudWriteExpectation], timeout: 3)
    
    XCTAssert(fakeClientUploader.successUploadCount == previousSuccessfulUploads + 1)
  }
  
  func testFlushToCloud() {
    fakeClientUploader.mimicSuccessUpload = true
    let previousSuccessfulUploads = fakeClientUploader.successUploadCount
    let writeString = "I want this logger to do something"

    handler.log(level: .info, message: "\("\(writeString)")", metadata: nil)

    let expectation = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 2)
    
    handler.localFileLogManager.forceFlushLogToCloud()
    
    let cloudWriteExpectation = XCTestExpectation(description: "Wait for flushCloud to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      cloudWriteExpectation.fulfill()
    }

    wait(for: [cloudWriteExpectation], timeout: 2)
    
    XCTAssert(fakeClientUploader.successUploadCount == previousSuccessfulUploads + 1)
  }
  
  func testForNoLogWrittenWhenDisabled() {

    handler.config.logToCloud = false
    let writeString = "I want this logger to do something"

    handler.log(level: .info, message: "\("\(writeString)")", metadata: nil)

    let expectation = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 3)
    let directoryContents = testFileSystemHelpers.logFileDirectoryContents()
    XCTAssert(directoryContents.count == 0)
  }
  
  func testForLoggingResumptionWhenReEnabled() {
    handler.config.logToCloud = false
    let writeString = "I want this logger to do something"

    handler.log(level: .info, message: "\(writeString)", metadata: nil)

    let expectationWithLoggingOff = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectationWithLoggingOff.fulfill()
    }

    wait(for: [expectationWithLoggingOff], timeout: 3)
    XCTAssert(testFileSystemHelpers.logFileDirectoryContents().count == 0)

    handler.config.logToCloud = true
    handler.log(level: .info, message: "\(writeString)", metadata: nil)

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
    
    handler.log(level: .info, message: "\("This is a testLogger1 message")", metadata: nil)
    let secondHandler = SwiftLogFireCloud(label: "testLogger2", config: config)
    secondHandler.log(level: .info, message: "\("This is a testLogger2 message")", metadata: nil)

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
    let fakeClientUploader = config.cloudUploader as! FakeClientCloudUploader
    fakeClientUploader.mimicSuccessUpload = true

    testFileSystemHelpers.flood(handler: handler)

    let localWriteExpectation = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      localWriteExpectation.fulfill()
    }

    wait(for: [localWriteExpectation], timeout: 3)
    handler.log(level: .info, message: "\("I'm a message that should trigger the cloud upload")", metadata: nil)

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
    //DISABLED:  passes individually, but running with other tests they interfere with their longer
    // running tasks that pollute the file system that I have not abstracted.
    
    let fileURL1 = testFileSystemHelpers.writeDummyLogFile(fileName: "TestSwiftLogFireCloudStrandedFile1.log")
    let fileURL2 = testFileSystemHelpers.writeDummyLogFile(fileName: "TestSwiftLogFireCloudStrandedFile2.log")
    let fakeClientUploader = config.cloudUploader as! FakeClientCloudUploader
    fakeClientUploader.mimicSuccessUpload = true

    let calendar = Calendar.current
    let dateBeforeLaunch = calendar.date(byAdding: .second, value: -32, to:  Date())
    
    do {
      try FileManager.default.setAttributes([FileAttributeKey.creationDate:dateBeforeLaunch!], ofItemAtPath: fileURL1.path)
      try FileManager.default.setAttributes([FileAttributeKey.creationDate:dateBeforeLaunch!], ofItemAtPath: fileURL2.path)
    } catch {
      XCTFail()
    }
    
    // the library delays for 5s then will look for log files in the directory, and attempt to upload them once per second

    let expectation = XCTestExpectation(description: "Wait for stranded file processing to start & complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 9)
    XCTAssert(fakeClientUploader.successUploadURLs.contains(fileURL1))
    XCTAssert(fakeClientUploader.successUploadURLs.contains(fileURL2))
  }
  
  func testForLoggerNotProcessingSecondLoggersFiles() {

    let secondHandler = SwiftLogFireCloud(label: "testLogger2", config: config)
    
    handler.log(level: .info, message: "\("This is a testLogger1 message")", metadata: nil)
    secondHandler.log(level: .info, message: "\("This is a testLogger2 message")", metadata: nil)
    
    let expectation = XCTestExpectation(description: "Wait for stranded file processing to start & complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 7)
    print(testFileSystemHelpers.logFileDirectoryFileCount())
    XCTAssert(testFileSystemHelpers.logFileDirectoryFileCount() == 2)
    
  }

  static var allTests = [
    ("testForNoCrashOnFirstLogAndContentsContainedAndForcedToCloud", testForNoCrashOnFirstLogAndContentsContainedAndForcedToCloud),
    ("testFlushToCloud", testFlushToCloud),
    ("testForNoLogWrittenWhenDisabled", testForNoLogWrittenWhenDisabled),
    ("testForLoggingResumptionWhenReEnabled", testForLoggingResumptionWhenReEnabled),
    ("testForMultipleLoggersNotCollidingOnDisk", testForMultipleLoggersNotCollidingOnDisk),
    ("testForCloudUploadAndFileDeleted", testForCloudUploadAndFileDeleted),
    ("testForQueingOfStrandedFiles", testForQueingOfStrandedFiles),
    ("testForLoggerNotProcessingSecondLoggersFiles", testForLoggerNotProcessingSecondLoggersFiles)
  ]
}
