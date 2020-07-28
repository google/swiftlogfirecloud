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

final class SwiftLogManagerTests: XCTestCase {

  var localSwiftLogManager: SwiftLogManager!
  var fakeCloudLogFileManager: FakeCloudLogFileManager?
  let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
  let config = SwiftLogFireCloudConfig(
    logToCloud: false, localFileSizeThresholdToPushToCloud: 100, localFileBufferWriteInterval: 60,
    uniqueID: "TestClientID", minFileSystemFreeSpace: 20, logDirectoryName: "TestLogs",
    logToCloudOnSimulator: false, cloudUploader: nil)
  var testFileSystemHelpers: TestFileSystemHelpers!
  let dummyLabel = "ManagerWriting"
  let queue = DispatchQueue(label: "com.google.firebase.swiftlogfirecloud-swiftlogmanager")

  override func setUp() {

    fakeCloudLogFileManager = FakeCloudLogFileManager()
    guard let fakeCloudLogFileManager = fakeCloudLogFileManager else {
      XCTFail("fake cloud log file manager failed to initialize")
      return
    }
    localSwiftLogManager = SwiftLogManager(
      label: dummyLabel, config: config, cloudLogfileManager: fakeCloudLogFileManager)
    testFileSystemHelpers = TestFileSystemHelpers(path: paths[0], config: config)
    testFileSystemHelpers.createLocalLogDirectory()
  }

  override func tearDown() {
    testFileSystemHelpers.deleteAllLogFiles()
    testFileSystemHelpers.removeLogDirectory()
  }
  
  func testInit() {
    // should set config, label & cloudFileManager are set
    // should confirm observers are set?
    // should confirm that stranded files are pushed to queue
    //
  }
  
  func testAppWillResumeActiveWhenTimerStoppedShouldRestartWriteTimer() {

    if localSwiftLogManager.writeTimer?.isValid ?? false {
      localSwiftLogManager.writeTimer?.invalidate()
    }

    localSwiftLogManager.appWillResumeActive()

    XCTAssertTrue(localSwiftLogManager.writeTimer?.isValid ?? false)
  }

  func testAppWillResumeActiveWhenTimerActiveShouldStillHaveActiveTimer() {

    XCTAssertTrue(localSwiftLogManager.writeTimer?.isValid ?? false)

    localSwiftLogManager.appWillResumeActive()

    XCTAssertTrue(localSwiftLogManager.writeTimer?.isValid ?? false)
  }

  func testAppWillResignActiveShouldWriteFileToCloudAndStopTimer() {

    let config = SwiftLogFireCloudConfig(
      logToCloud: true, localFileSizeThresholdToPushToCloud: 100, uniqueID: "testDevice",
      logDirectoryName: "TestLogs", logToCloudOnSimulator: true, cloudUploader: nil)

    let fakeCloudLogFileManager = FakeCloudLogFileManager()
    let localLogFileManager = SwiftLogManager(
      label: dummyLabel, config: config, cloudLogfileManager: fakeCloudLogFileManager)

    localLogFileManager.localLogFile = LocalLogFile(label: "test", config: config, queue: queue)
    guard let localFileURL = localLogFileManager.localLogFile?.fileURL else {
      XCTFail("No local file created")
      return
    }
    _ = testFileSystemHelpers.flood(localLogFile: localLogFileManager.localLogFile!)

    let expectation = XCTestExpectation(
      description: "testAppWillResignActiveShouldWriteFileToCloudAndStopTimer")
    localLogFileManager.appWillResignActive {
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 5.0)
    XCTAssert(fakeCloudLogFileManager.recentWrittenFiles.contains(localFileURL))
    XCTAssertFalse(localLogFileManager.writeTimer?.isValid ?? false)
  }
  
  func testCreateLocalLogDirectorySuccessful() {
    //Setup creates the directory, remove it first
    testFileSystemHelpers.removeLogDirectory()

    localSwiftLogManager.createLocalLogDirectory()

    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    XCTAssert(paths.count > 0)
    var documentsDirectory = paths[0]
    documentsDirectory.appendPathComponent(config.logDirectoryName)

    var isDir: ObjCBool = false
    let logDirectoryExists = FileManager.default.fileExists(
      atPath: documentsDirectory.path, isDirectory: &isDir)

    XCTAssert(logDirectoryExists && isDir.boolValue)
  }

  func testRetreieveLocalLogFileListOnDiskWhenEmptyShouldFindDirectoryContentsNil() {

    localSwiftLogManager.createLocalLogDirectory()
    let urls = localSwiftLogManager.retrieveLocalLogFileListOnDisk()

    XCTAssert(urls.count == 0)
  }

  func testRetrieveLocalLogFileListOnDiskWhenNotEmptyShouldFindFiles() {

    let fileURL1 = testFileSystemHelpers.writeDummyLogFile(fileName: "ManagerWritingTestLogFileName1.log")
    let fileURL2 = testFileSystemHelpers.writeDummyLogFile(fileName: "ManagerWritingTestLogFileName2.log")

    let logFiles = localSwiftLogManager.retrieveLocalLogFileListOnDisk()

    var logFileURLs = Set<URL>()
    for logFile in logFiles {
      logFileURLs.insert(logFile.fileURL)
    }

    XCTAssert(logFileURLs.contains(fileURL1))
    XCTAssert(logFileURLs.contains(fileURL2))
    XCTAssert(logFileURLs.count == 2)
  }

  func testProcessStrandedFilesAtStartupWhenNotLoggingToCloudShouldDeleteLocalFiles() {

    let fileURL1 = testFileSystemHelpers.writeDummyLogFile(fileName: "ManagerWritingTestLogFileName1.log")
    let fileURL2 = testFileSystemHelpers.writeDummyLogFile(fileName: "ManagerWritingTestLogFileName2.log")
    
    let calendar = Calendar.current
    let dateBeforeLaunch = calendar.date(byAdding: .second, value: -32, to:  Date())
    
    do {
      try FileManager.default.setAttributes([FileAttributeKey.creationDate:dateBeforeLaunch!], ofItemAtPath: fileURL1.path)
      try FileManager.default.setAttributes([FileAttributeKey.creationDate:dateBeforeLaunch!], ofItemAtPath: fileURL2.path)
    } catch {
      XCTFail()
    }

    let expectation = XCTestExpectation(description: "testProcessStrandedFilesAtStartup")

    // the logger init is setup to not log to cloud, so it should just delete files.
    localSwiftLogManager.processStrandedFilesAtStartup {
      XCTAssertTrue(self.testFileSystemHelpers.isLogFileDirectoryEmpty())
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 5.0)
  }

  func testProcessStrandedFilesAtStartupWheLoggingToCloudShouldPutFilesOnQueue() {
    var config = self.config
    config.logToCloud = true

    // create a special localLogFileManager with an updated config
    let fakeCloudLogFileManager = FakeCloudLogFileManager()
    let localLogFileManager = SwiftLogManager(
      label: dummyLabel, config: config, cloudLogfileManager: fakeCloudLogFileManager)

    let fileURL1 = testFileSystemHelpers.writeDummyLogFile(fileName: "ManagerWritingTestLogFileName1.log")
    let fileURL2 = testFileSystemHelpers.writeDummyLogFile(fileName: "ManagerWritingTestLogFileName2.log")
    
    let calendar = Calendar.current
    let dateBeforeLaunch = calendar.date(byAdding: .second, value: -32, to:  Date())
    
    do {
      try FileManager.default.setAttributes([FileAttributeKey.creationDate:dateBeforeLaunch!], ofItemAtPath: fileURL1.path)
      try FileManager.default.setAttributes([FileAttributeKey.creationDate:dateBeforeLaunch!], ofItemAtPath: fileURL2.path)
    } catch {
      XCTFail()
    }

    let expectation = XCTestExpectation(description: "testProcessStrandedFilesAtStartup")

    // the logger init is setup to not log to cloud, so it should just delete files.
    localLogFileManager.processStrandedFilesAtStartup {
      XCTAssertTrue(fakeCloudLogFileManager.cloudPushQueue.contains(fileURL1))
      XCTAssertTrue(fakeCloudLogFileManager.cloudPushQueue.contains(fileURL2))
      XCTAssertTrue(fakeCloudLogFileManager.cloudPushQueue.count == 2)

      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 5.0)

  }
  
  func testAssessLocalLogabilityWhenDiskSpaceInsufficientShouldBeImpaired() {
    var config = self.config
    // FLAKY: this will fail when devices and simulators ship with 10PB.
    config.minFileSystemFreeSpace = SwiftLogFireCloudConfig.megabyte * 10_000_000_000

    let fakeCloudLogFileManager = FakeCloudLogFileManager()
    let localLogFileManager = SwiftLogManager(
      label: dummyLabel, config: config, cloudLogfileManager: fakeCloudLogFileManager)
    localLogFileManager.localLogFile = LocalLogFile(label: "test", config: config, queue: queue)
    let logability = localLogFileManager.assessLocalLogability()

    XCTAssert(logability == .impaired)
  }

  func testAssessLocalLogabilityWhenNoWritesAttemptedShouldBeNormal() {
    guard let localLogFileManager = localSwiftLogManager else {
      XCTFail()
      return
    }

    let logability = localLogFileManager.assessLocalLogability()

    XCTAssert(logability == .normal)
  }

  func testAssessLocalLogabilityWhenLastWriteIsAllCasesShouldReturnAllLogabilities() {
    guard let localSwiftLogManager = localSwiftLogManager else {
      XCTFail()
      return
    }
    localSwiftLogManager.localLogFile = LocalLogFile(label: "test", config: config, queue: queue)
    localSwiftLogManager.lastFileWriteAttempt = Date()

    localSwiftLogManager.lastFileWrite = Date(timeInterval: -900, since: Date())
    let unFunctionalLogability = localSwiftLogManager.assessLocalLogability()
    XCTAssert(unFunctionalLogability == .unfunctional)

    localSwiftLogManager.lastFileWrite = Date(timeInterval: -300, since: Date())
    let impairedLogability = localSwiftLogManager.assessLocalLogability()
    XCTAssert(impairedLogability == .impaired)

    localSwiftLogManager.lastFileWrite = Date(timeInterval: -60, since: Date())
    let normalLogability = localSwiftLogManager.assessLocalLogability()
    XCTAssert(normalLogability == .normal)

  }

  func testAssessLocalLogabilityWhenSuccessiveFailuresAllCasesShouldReturnAllLogabilites() {
    guard let localSwiftLogManager = localSwiftLogManager else {
      XCTFail()
      return
    }
    localSwiftLogManager.localLogFile = LocalLogFile(label: "test", config: config, queue: queue)
    localSwiftLogManager.lastFileWriteAttempt = Date()

    localSwiftLogManager.successiveWriteFailures = 120
    let unFunctionalLogability = localSwiftLogManager.assessLocalLogability()
    XCTAssert(unFunctionalLogability == .unfunctional)

    localSwiftLogManager.successiveWriteFailures = 16
    let impairedLogability = localSwiftLogManager.assessLocalLogability()
    XCTAssert(impairedLogability == .impaired)

    localSwiftLogManager.successiveWriteFailures = 2
    let normalLogability = localSwiftLogManager.assessLocalLogability()
    XCTAssert(normalLogability == .normal)
  }

  // MARK: testIsFileSystemFreeSpaceSufficient()
  func testIsFileSystemFreeSpaceSufficent() {

    guard
      let totalDiskSpaceInBytes = try? FileManager.default.attributesOfFileSystem(
        forPath: NSHomeDirectory())[FileAttributeKey.systemFreeSize] as? Int64
    else {
      XCTFail()
      return
    }

    XCTAssert(
      (totalDiskSpaceInBytes > 20 * 1_048_576
        && localSwiftLogManager.isFileSystemFreeSpaceSufficient())
        || (totalDiskSpaceInBytes < 20 * 1_048_576
          && !localSwiftLogManager.isFileSystemFreeSpaceSufficient())
    )
  }

  func testIsFileSystemFreeSpaceSufficeintWhenNot() {
    var config = self.config
    // FLAKY: this will fail when devices and simulators ship with 10PB. But I'm ok with the risk for now...
    config.minFileSystemFreeSpace = SwiftLogFireCloudConfig.megabyte * 10_000_000_000

    let fakeCloudLogFileManager = FakeCloudLogFileManager()
    let localLogFileManager = SwiftLogManager(
      label: dummyLabel, config: config, cloudLogfileManager: fakeCloudLogFileManager)
    XCTAssertFalse(localLogFileManager.isFileSystemFreeSpaceSufficient())
  }
  
  func testForNoDroppedMessagesBetweenLogFileRotation() {
    // DISABLED:  This is an inherently flaky test, because when the logging manager will roll to a
    // new file is based on performance of the machine its running on and the frequency of log messages
    // being sent to it.  For example, before writing a new message the logging system checks to see
    // if the bytes written is over a threshold size and then creates a new file.  But this threshold
    // is not a hard limit because there is asynchronous latency between when bytes are written and when
    // they are requested to be written.  For example, if the threshold is 60 bytes, it could easily
    // occur that there are 50 bytes written and 40 bytes pending to write so the file won't roll when
    // new messages come in until some more pending writes complete. So some amount of messages will be
    // written above the threshold that were pending whne the threshold was met. That delay between
    // threshold being met and how many pending writes are still outstanding
    // is dependant on the performace processing capability of the test taget.  So the constats of 20000
    // messages, threshold of 60 bytes and delay for writes to complete of 6s are all device specific.
    // As such, this test is currently disabled.  But, its still a valuable test to confirm that
    // messages are not dropped on file rotation.  As long as at least 2 files are created the the test
    // should be a valid test so only run when necessary and on consistent hardware for the settings.
    // Run the test individually and break just before completion to ensure enough files are created.
    // There is arguably too much logic in this test too, but not dropping messages is important to
    // test for, IMHO.
    fakeCloudLogFileManager?.isNowTheRightTimeClosure = { bytesWritten in return bytesWritten > 60 }
    for i in 1...20000 {
      localSwiftLogManager.log(msg: "*\(i)*")
    }
    
    // let all the writes complete in fire and forget...
    let expectation = XCTestExpectation(
      description: "testForNoDroppedMessagesBetweenFileRotation")
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
      expectation.fulfill()
    }
    wait(for: [expectation], timeout: 6.0)
    
    var lastLineNumber: Int? = nil
    var firstLineNumber: Int? = nil
    for fileURL in testFileSystemHelpers.logFileDirectoryContents() {  // assumes a oldest first sort order, which seems to hold
      let logFileContents = testFileSystemHelpers.readDummyLogFile(url: fileURL)
      let lines = logFileContents?.split(separator: "\n")
      if let firstLine = lines?.first {
        let firstLineNumberStrList = firstLine.split(separator: "*")
        let firstLineNumberStr = String(firstLineNumberStrList.first!)
        firstLineNumber = Int(firstLineNumberStr)
      }
      switch (firstLineNumber, lastLineNumber) {
      case (.some(_), .none): // Only one file read at this point.
        continue
      case (.some(let firstLineNumber), .some(let lastLineNumber)): // you're in the 2nd through last file
        XCTAssert(lastLineNumber + 1 == firstLineNumber)
      case (.none, _):
        XCTFail("Logic error in test")
      }
      if let lastLine = lines?.last {
        let lastLineNumberStrList = lastLine.split(separator: "*")
        let lastLineNumberStr = String(lastLineNumberStrList.first!)
        lastLineNumber = Int(lastLineNumberStr)
      }
    }
    
  }

  static var allTests = [
    ("testCreateLocalLogDirectorySuccessful", testCreateLocalLogDirectorySuccessful),
    (
      "testRetreieveLocalLogFileListOnDiskWhenEmptyShouldFindDirectoryContentsNil",
      testRetreieveLocalLogFileListOnDiskWhenEmptyShouldFindDirectoryContentsNil
    ),
    (
      "testRetrieveLocalLogFileListOnDiskWhenNotEmptyShouldFindFiles",
      testRetrieveLocalLogFileListOnDiskWhenNotEmptyShouldFindFiles
    ),
    (
      "testProcessStrandedFilesAtStartupWhenNotLoggingToCloudShouldDeleteLocalFiles",
      testProcessStrandedFilesAtStartupWhenNotLoggingToCloudShouldDeleteLocalFiles
    ),
    (
      "testProcessStrandedFilesAtStartupWheLoggingToCloudShouldPutFilesOnQueue",
      testProcessStrandedFilesAtStartupWheLoggingToCloudShouldPutFilesOnQueue
    ),
    ("testIsFileSystemFreeSpaceSufficent", testIsFileSystemFreeSpaceSufficent),
    ("testIsFileSystemFreeSpaceSufficeintWhenNot", testIsFileSystemFreeSpaceSufficeintWhenNot),
    (
      "testAppWillResumeActiveWhenTimerStoppedShouldRestartWriteTimer",
      testAppWillResumeActiveWhenTimerStoppedShouldRestartWriteTimer
    ),
    (
      "testAppWillResumeActiveWhenTimerActiveShouldStillHaveActiveTimer",
      testAppWillResumeActiveWhenTimerActiveShouldStillHaveActiveTimer
    ),
    (
      "testAppWillResignActiveShouldWriteFileToCloudAndStopTimer",
      testAppWillResignActiveShouldWriteFileToCloudAndStopTimer
    ),
    (
      "testAssessLocalLogabilityWhenDiskSpaceInsufficientShouldBeImpaired",
      testAssessLocalLogabilityWhenDiskSpaceInsufficientShouldBeImpaired
    ),
    (
      "testAssessLocalLogabilityWhenNoWritesAttemptedShouldBeNormal",
      testAssessLocalLogabilityWhenNoWritesAttemptedShouldBeNormal
    ),
    (
      "testAssessLocalLogabilityWhenLastWriteIsAllCasesShouldReturnAllLogabilities",
      testAssessLocalLogabilityWhenLastWriteIsAllCasesShouldReturnAllLogabilities
    ),
  ]
}
