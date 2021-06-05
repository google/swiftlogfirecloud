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

import XCTest
@testable import SwiftLogFireCloud

class CloudLogFileManagerTests: XCTestCase {

  var config: SwiftLogFireCloudConfig!
  var cloudManager: CloudLogFileManager!
  var fakeClientCloudUploader: FakeClientCloudUploader!
  var localLogFile: LocalLogFile!
  var testFileHelpers: TestFileSystemHelpers!
  
  override func setUpWithError() throws {
    fakeClientCloudUploader = FakeClientCloudUploader()
    config = SwiftLogFireCloudConfig(logToCloud: false,
                                         localFileSizeThresholdToPushToCloud: 100,
                                         localFileBufferWriteInterval: 60,
                                         uniqueID: "SwiftLogFireCloud",
                                         minFileSystemFreeSpace: 20,
                                         logDirectoryName: "TestLogs",
                                         logToCloudOnSimulator: true,
                                         cloudUploader: fakeClientCloudUploader)

    cloudManager = CloudLogFileManager(label: "SwiftLogFireCloud", config: config)
    testFileHelpers = TestFileSystemHelpers(config: config)
    localLogFile = LocalLogFile(label: "SwiftLogFireCloud",
                                config: config,
                                queue: DispatchQueue(label: "TestQueue"),
                                tempURL: testFileHelpers.tempDirPath)
  }

  override func tearDownWithError() throws {
    cloudManager = nil
  }
  
  func testRightTimetoWriteToCloudWhenLogabilityNormalAndEnoughBytesWritten() {
    cloudManager.lastWriteSuccess = Date(timeIntervalSinceNow: -30)
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -31)
    let localLogFile = LocalLogFile(label: "SwiftLogFireCloud",
                                   config: config,
                                   queue: DispatchQueue(label: "TestQueue"),
                                   tempURL: testFileHelpers.tempDirPath)
    localLogFile.bytesWritten = config.localFileSizeThresholdToPushToCloud + 10
    let result = cloudManager.isNowTheRightTimeToWriteToCloud(localLogFile)
    XCTAssert(result)
  }
  
  func testRightTimetoWriteToCloudWhenLogabilityNormalAndNotEnoughBytesWritten() {
    cloudManager.lastWriteSuccess = Date(timeIntervalSinceNow: -30)
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -31)
    let localLogFile = LocalLogFile(label: "SwiftLogFireCloud",
                                   config: config,
                                   queue: DispatchQueue(label: "TestQueue"),
                                   tempURL: testFileHelpers.tempDirPath)
    localLogFile.bytesWritten = config.localFileSizeThresholdToPushToCloud - 10
    let result = cloudManager.isNowTheRightTimeToWriteToCloud(localLogFile)
    XCTAssertFalse(result)
  }
  
  func testRightTimeToWriteTOCloudWhenLogabilityImpairedAndOutsideRetryInterval() {
    cloudManager.lastWriteSuccess = Date()
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -190)
    let localLogFile = LocalLogFile(label: "SwiftLogFireCloud",
                                   config: config,
                                   queue: DispatchQueue(label: "TestQueue"),
                                   tempURL: testFileHelpers.tempDirPath)
    localLogFile.bytesWritten = config.localFileSizeThresholdToPushToCloud + 10
    let result = cloudManager.isNowTheRightTimeToWriteToCloud(localLogFile)
    XCTAssert(result)
  }
  
  func testRightTimeToWriteTOCloudWhenLogabilityImpairedAndInsideRetryInterval() {
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -10)
    cloudManager.successiveFails = 5
    let localLogFile = LocalLogFile(label: "SwiftLogFireCloud",
                                   config: config,
                                   queue: DispatchQueue(label: "TestQueue"),
                                   tempURL: testFileHelpers.tempDirPath)
    localLogFile.bytesWritten = config.localFileSizeThresholdToPushToCloud + 10
    let result = cloudManager.isNowTheRightTimeToWriteToCloud(localLogFile)
    XCTAssertFalse(result)
  }
  
  func testRightTimeToWriteTOCloudWhenLogabilityUnfunctionalAndInsideRetryInterval() {
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -500)
    cloudManager.successiveFails = 12
    let localLogFile = LocalLogFile(label: "SwiftLogFireCloud",
                                   config: config,
                                   queue: DispatchQueue(label: "TestQueue"),
                                   tempURL: testFileHelpers.tempDirPath)
    localLogFile.bytesWritten = config.localFileSizeThresholdToPushToCloud + 10
    let result = cloudManager.isNowTheRightTimeToWriteToCloud(localLogFile)
    XCTAssertFalse(result)
  }
  
  func testRightTimeToWriteTOCloudWhenLogabilityUnfunctionalAndOutsideRetryInterval() {
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -700)
    cloudManager.successiveFails = 12
    let localLogFile = LocalLogFile(label: "SwiftLogFireCloud",
                                   config: config,
                                   queue: DispatchQueue(label: "TestQueue"),
                                   tempURL: testFileHelpers.tempDirPath)
    localLogFile.bytesWritten = config.localFileSizeThresholdToPushToCloud + 10
    let result = cloudManager.isNowTheRightTimeToWriteToCloud(localLogFile)
    XCTAssert(result)
  }
  
  func testWriteLogFileTCloudWithNoPendingWrites() {
    localLogFile.bytesWritten = config.localFileSizeThresholdToPushToCloud + 10
    localLogFile.pendingWriteCount = 0
    cloudManager.writeLogFileToCloud(localLogFile: localLogFile)
    
    let expectation = XCTestExpectation(description: "Wait for async upload")
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 3.0)
    
    XCTAssert(fakeClientCloudUploader.successUploadURLs.contains(localLogFile.fileURL))
  }
  
  func testWriteLogFileToCloudWithResolvedPendingWrites() {
    localLogFile.bytesWritten = config.localFileSizeThresholdToPushToCloud + 10
    localLogFile.pendingWriteCount = 10
    localLogFile.pendingWriteWaitCount = 0
    cloudManager.writeLogFileToCloud(localLogFile: localLogFile)
    localLogFile.pendingWriteCount = 0
    
    let expectation = XCTestExpectation(description: "Wait for async upload")
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 4.0)
    
    XCTAssert(fakeClientCloudUploader.successUploadURLs.contains(localLogFile.fileURL))
    
  }
  
  func testWriteLogFileToCloudAfterPendingWritesTimeout() {
    localLogFile.bytesWritten = config.localFileSizeThresholdToPushToCloud + 10
    localLogFile.pendingWriteCount = 10
    localLogFile.pendingWriteWaitCount = 0
    cloudManager.writeLogFileToCloud(localLogFile: localLogFile)
    
    let expectation = XCTestExpectation(description: "Wait for async upload")
    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 7.0)
    
    XCTAssert(fakeClientCloudUploader.successUploadURLs.isEmpty)
    
  }

  func testAddingFirstFileToCloudPushQueue() {
    
    cloudManager.addFileToCloudPushQueue(localLogFile: localLogFile)
    
    let expectation = XCTestExpectation(description: "Wait for async timer start")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 0.5)
    
    XCTAssert(cloudManager.strandedFilesToPush?.count == 1)
    XCTAssert(cloudManager.strandedFileTimer!.isValid)
  }
  
  func testAddingAdditionalFilesToCloudPushQueue() {
    
    cloudManager.addFileToCloudPushQueue(localLogFile: localLogFile)
    cloudManager.addFileToCloudPushQueue(localLogFile: localLogFile)
    
    let expectation = XCTestExpectation(description: "Wait for async timer start")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 0.5)
    
    XCTAssert(cloudManager.strandedFilesToPush?.count == 2)
    XCTAssert(cloudManager.strandedFileTimer!.isValid)
  }
  
  func testReportUploadStatusOnSuccess() {
    
    XCTAssertNil(cloudManager.lastWriteSuccess)
    cloudManager.reportUploadStatus(.success(localLogFile))
    
    let expectation = XCTestExpectation(description: "Wait for async timer start")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 0.5)
    
    XCTAssertNotNil(cloudManager.lastWriteSuccess)
    XCTAssert(cloudManager.successiveFails == 0)
    
  }
  
  func testReportUploadStatusOnFailure() {
    
    let previousSuccessiveFails = cloudManager.successiveFails
    cloudManager.reportUploadStatus(.failure(CloudUploadError.failedToUpload(localLogFile)))
    
    let expectation = XCTestExpectation(description: "Wait for async timer start")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 0.5)
    
    let strandedURLs = cloudManager.strandedFilesToPush!.map { $0.fileURL }
    XCTAssert(strandedURLs.contains(localLogFile.fileURL))
    XCTAssert(cloudManager.successiveFails == previousSuccessiveFails + 1)
    
  }
  
  func testCloudLogabilityWhenNormalAndNoWritesAttempted() {
    cloudManager.successiveFails = 1
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -31)
    let logability = cloudManager.assessLogability()
    XCTAssert(logability == .normal)
  }
  
  func testCloudLogabilityWhenNormalAndWritesAttempted() {
    cloudManager.lastWriteSuccess = Date(timeIntervalSinceNow: -30)
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -31)
    let logability = cloudManager.assessLogability()
    XCTAssert(logability == .normal)
  }
  
  func testCloudLogabilityWhenImpairedFromFailedWrite() {
    cloudManager.successiveFails = 5
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -31)
    let logability = cloudManager.assessLogability()
    XCTAssert(logability == .impaired)
  }
  
  func testCloudLogabilityWhenImpairedFromDelaysBetweenAttemptAndSucces() {
    cloudManager.lastWriteSuccess = Date()
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -190)
    let logability = cloudManager.assessLogability()
    XCTAssert(logability == .impaired)
  }
  
  func testCloudLogabilityWhenUnfunctionalFromDelayBetweenAttempAndSuccess() {
    cloudManager.lastWriteSuccess = Date()
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -900)
    let logability = cloudManager.assessLogability()
    XCTAssert(logability == .unfunctional)
  }
  
  func testCloudLogabilityWhenUnfunctionalFromFailedWrites() {
    cloudManager.successiveFails = 12
    cloudManager.lastWriteAttempt = Date(timeIntervalSinceNow: -31)
    let logability = cloudManager.assessLogability()
    XCTAssert(logability == .unfunctional)
  }
}
