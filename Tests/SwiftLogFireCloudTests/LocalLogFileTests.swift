//
//  LocalLogFileTests.swift
//  SwiftLogFireCloudTests
//
//  Created by Timothy Wise on 7/4/20.
//

import XCTest
@testable import SwiftLogFireCloud

class LocalLogFileTests: XCTestCase {

    let config = SwiftLogFileCloudConfig(logToCloud: false, localFileSizeThresholdToPushToCloud: 100, localFileBufferWriteInterval: 60, uniqueID: "TestClientID", minFileSystemFreeSpace: 20, logDirectoryName: "TestLogs")
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    var testLogFile: LocalLogFile!
  
    override func setUpWithError() throws {
        testLogFile = LocalLogFile(config: config)
        createLocalLogDirectory()
    }

    override func tearDownWithError() throws {
        deleteAllLogFiles()
        removeLogDirectory()
    }
  
  func testDeleteLocalLogFile() {
      
      let fileURL = writeDummyLogFile(fileName: "TestLogFileName.log")
      testLogFile.fileURL = fileURL
      
      testLogFile.delete()
    
      var isDir: ObjCBool = false
      let testLogFileExists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
      XCTAssert(testLogFileExists == false && isDir.boolValue == false)
  }
  
  // MARK: testTrimBufferIfNecessary
  func testTrimBufferIfNecessaryWithEmptyBufferShouldStillBeEmptyAndSameReference() {
    
    let originalTestLogFileReference = testLogFile
    testLogFile = testLogFile.trimBufferIfNecessary()
      
    XCTAssert(testLogFile.buffer.count == 0)
    XCTAssertTrue(originalTestLogFileReference === testLogFile)
  }
  
  func testTrimBufferIfNecessaryWithOverflowingBufferShouldResetBufferAndDeleteFiles() {
      _ = floodLocalLogFileBuffer()
      let originalTestLogFileReference = testLogFile
      let newTestFileLogFileReference = testLogFile.trimBufferIfNecessary()
      
      XCTAssert(newTestFileLogFileReference.buffer.count == 0)
      XCTAssertFalse(originalTestLogFileReference === newTestFileLogFileReference)
      XCTAssert(isLogFileDirectoryEmpty())
  }
  
  func testAppendToExistingLocalLogFileShouldAppendFile() {
      guard let fileURL = testLogFile.fileURL else { XCTFail(); return }

      guard let sampleLoggedString = floodLocalLogFileBuffer() else {
        XCTFail("Faild to initialize buffer in testAppendToExistingLocalLogFileShouldAppendFile")
        return
      }
      testLogFile.writeLogFileToDisk()
      guard let appendedLoggedString = floodLocalLogFileBuffer() else {
        XCTFail("Faild to appended buffer in testAppendToExistingLocalLogFileShouldAppendFile")
        return
      }
      testLogFile.writeLogFileToDisk()
  
      do {
          let textRead = try String(contentsOf: fileURL)
          XCTAssert(textRead == sampleLoggedString + appendedLoggedString)
      } catch {
          XCTFail("Unable to read the written text file in testtFirstWriteOfLocalFileShouldWriteFileData()")
      }
  }

      func testtFirstWriteOfLocalFileShouldWriteFileData() {
          guard let fileURL = testLogFile.fileURL else { XCTFail(); return }

          let sampleLoggedString = floodLocalLogFileBuffer()
          testLogFile.writeLogFileToDisk()
        
        guard sampleLoggedString != nil else {
          XCTFail("Faild to initialize buffer in testtFirstWriteOfLocalFileShouldWriteFileData")
          return
        }
        do {
            let textRead = try String(contentsOf: fileURL)
            XCTAssert(textRead == sampleLoggedString)
        } catch {
            XCTFail("Unable to read the written text file in testtFirstWriteOfLocalFileShouldWriteFileData()")
        }
      }
//  
  static var allTests = [
    ("testDeleteLocalLogFile", testDeleteLocalLogFile),
    ("testTrimBufferIfNecessaryWithEmptyBufferShouldStillBeEmptyAndSameReference", testTrimBufferIfNecessaryWithEmptyBufferShouldStillBeEmptyAndSameReference),
    ("testTrimBufferIfNecessaryWithOverflowingBufferShouldResetBufferAndDeleteFiles", testTrimBufferIfNecessaryWithOverflowingBufferShouldResetBufferAndDeleteFiles),
    ("testtFirstWriteOfLocalFileShouldWriteFileData", testtFirstWriteOfLocalFileShouldWriteFileData),
    ("testAppendToExistingLocalLogFileShouldAppendFile", testAppendToExistingLocalLogFileShouldAppendFile),
  ]
}
