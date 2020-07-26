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

class LocalLogFileTests: XCTestCase {

  let config = SwiftLogFireCloudConfig(
    logToCloud: false,
    localFileSizeThresholdToPushToCloud: 100,
    localFileBufferWriteInterval: 60,
    uniqueID: "TestClientID",
    minFileSystemFreeSpace: 20,
    logDirectoryName: "TestLogs",
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
    XCTAssert(testLogFile.fileURL.absoluteString.contains(dummyLabel))
    XCTAssert(testLogFile.fileURL.absoluteString.contains(config.uniqueIDString!))
    XCTAssertNil(testLogFile.firstFileWrite)
    XCTAssert(testLogFile.fileURL.absoluteString.contains(Bundle.main.bundleIdentifier!))
    XCTAssert(testLogFile.fileURL.pathExtension == "log")
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
    // not yet created, should not crash
    testLogFile.delete()
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

    ("testDeleteLocalLogFileWhenItExists", testDeleteLocalLogFileWhenItExists),
    ("testDeleteLocalLogFileWhenItDoesnExistShouldNoOp", testDeleteLocalLogFileWhenItDoesnExistShouldNoOp),
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
