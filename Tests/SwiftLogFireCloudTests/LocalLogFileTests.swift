import XCTest

@testable import SwiftLogFireCloud

class LocalLogFileTests: XCTestCase {

  let config = SwiftLogFireCloudConfig(
    logToCloud: false, localFileSizeThresholdToPushToCloud: 100, localFileBufferWriteInterval: 60,
    uniqueID: "TestClientID", minFileSystemFreeSpace: 20, logDirectoryName: "TestLogs",
    cloudUploader: nil)
  let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
  var testLogFile: LocalLogFile!
  var testFileSystemHelpers: TestFileSystemHelpers!
  let dummyLabel = "LocalLogFileDirectWriting"
  let localLogFileTestsQueue = DispatchQueue(label: "com.google.firebase.swiftlogfirecloud.locallogfiletests")

  override func setUpWithError() throws {
    
    testLogFile = LocalLogFile(label: dummyLabel, config: config, queue: localLogFileTestsQueue)
    testFileSystemHelpers = TestFileSystemHelpers(path: paths[0], config: config)
    testFileSystemHelpers.createLocalLogDirectory()

  }

  override func tearDownWithError() throws {
    testFileSystemHelpers.deleteAllLogFiles()
    testFileSystemHelpers.removeLogDirectory()
  }

  func testInit() {
    // sould set config, lablel, queue, fileURL should not be nil.
  }
  
  func testCreateFileNameWithUniqueIDGivenAndLogLabel() {
    // should create a unique containing unique bits
  }
  
  func testCreateFileNameWithDeviceIDAndLogLabel() {
    // should use the test device ID in the name.
  }
  
  func testCreateFileURLWithLogDirectory() {
    // should ensure the log directory name is in the path
    // should ensure the extension is .log
  }
  func testDeleteLocalLogFileWhenItExists() {

    let fileURL = testFileSystemHelpers.writeDummyLogFile(
      fileName: "TestLogFileName.log")
    testLogFile.fileURL = fileURL

    testLogFile.delete()

    var isDir: ObjCBool = false
    let testLogFileExists = FileManager.default.fileExists(
      atPath: fileURL.path, isDirectory: &isDir)
    XCTAssert(testLogFileExists == false && isDir.boolValue == false)
  }
  
  func testDeleteLocalLogFileWhenItDoesnExistShouldNoOp() {
    
  }

  func testTrimDiskImageIfNecessaryWithEmptyBufferShouldStillBeEmptyAndSameReference() {

    let originalTestLogFileReference = testLogFile
    testLogFile = testLogFile.trimDiskImageIfNecessary()

    XCTAssert(testLogFile.count() == 0)
    XCTAssertTrue(originalTestLogFileReference === testLogFile)
  }

  func testTrimImageIfNecessaryWithOverflowingBufferShouldResetBufferAndDeleteFiles() {
    print("Test Log File location: \(paths)")
    _ = testFileSystemHelpers.flood(localLogFile: testLogFile)
    _ = testFileSystemHelpers.flood(localLogFile: testLogFile)
    
    let originalTestLogFileReference = testLogFile
    let expectation = XCTestExpectation(description: "Wait for DispatchIO of impl to complete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 3)
    
    let newTestFileLogFileReference = testLogFile.trimDiskImageIfNecessary()

    XCTAssert(newTestFileLogFileReference == nil)
    XCTAssertFalse(originalTestLogFileReference === newTestFileLogFileReference)
    XCTAssert(testFileSystemHelpers.isLogFileDirectoryEmpty())
  }

  //  
  static var allTests = [
    ("testInit", testInit),
    ("testCreateFileNameWithUniqueIDGivenAndLogLabel", testCreateFileNameWithUniqueIDGivenAndLogLabel),
    ("testCreateFileNameWithDeviceIDAndLogLabel", testCreateFileNameWithDeviceIDAndLogLabel),
    ("testDeleteLocalLogFileWhenItExists", testDeleteLocalLogFileWhenItExists),
    ("testDeleteLocalLogFileWhenItDoesnExistShouldNoOp", testDeleteLocalLogFileWhenItDoesnExistShouldNoOp),
    ("testCreateFileURLWithLogDirectory", testCreateFileURLWithLogDirectory),
    (
      "testTrimDiskImageIfNecessaryWithEmptyBufferShouldStillBeEmptyAndSameReference",
      testTrimDiskImageIfNecessaryWithEmptyBufferShouldStillBeEmptyAndSameReference
    ),
    (
      "testTrimImageIfNecessaryWithOverflowingBufferShouldResetBufferAndDeleteFiles",
      testTrimImageIfNecessaryWithOverflowingBufferShouldResetBufferAndDeleteFiles
    ),
  ]
}
