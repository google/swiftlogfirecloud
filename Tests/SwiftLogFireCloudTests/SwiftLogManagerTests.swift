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

    let fileURL1 = testFileSystemHelpers.writeDummyLogFile(fileName: "TestLogFileName1.log")
    let fileURL2 = testFileSystemHelpers.writeDummyLogFile(fileName: "TestLogFileName2.log")

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

    _ = testFileSystemHelpers.writeDummyLogFile(fileName: "TestLogFileName1.log")
    _ = testFileSystemHelpers.writeDummyLogFile(fileName: "TestLogFileName2.log")

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

    let fileURL1 = testFileSystemHelpers.writeDummyLogFile(fileName: "TestLogFileName1.log")
    let fileURL2 = testFileSystemHelpers.writeDummyLogFile(fileName: "TestLogFileName2.log")

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
