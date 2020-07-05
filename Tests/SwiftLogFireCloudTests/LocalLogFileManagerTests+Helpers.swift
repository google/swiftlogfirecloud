//
//  LocalLogFileManagerTests+Helpers.swift
//  SwiftLogFireCloud
//
//  Created by Timothy Wise on 3/24/20.
//

import XCTest

@testable import SwiftLogFireCloud

//TODO:  this is mostly duplicated across test classes, prolly worth collapsing
extension LocalLogFileManagerTests {

  internal func floodLocalLogFileBuffer() -> String? {
    let sampleLogString = "This is a sample log string\n"
    for _ in 0...20 {
      localLogFileManager.localLogFile.buffer.append(sampleLogString.data(using: .utf8)!)
    }
    return String(bytes: localLogFileManager.localLogFile.buffer, encoding: .utf8)
  }

  internal func removeLogDirectory() {
    XCTAssert(paths.count > 0)
    var documentsDirectory = paths[0]
    documentsDirectory.appendPathComponent(config.logDirectoryName)

    var isDir: ObjCBool = false
    let logDirectoryExists = FileManager.default.fileExists(
      atPath: documentsDirectory.path, isDirectory: &isDir)

    if logDirectoryExists {
      do {
        try FileManager.default.removeItem(at: documentsDirectory)
      } catch {
        XCTFail("Unable to delete log file directory")
      }
    }
  }

  internal func writeDummyLogFile(fileName: String) -> URL {
    let data = "I am test data for a about to be deleted file".data(using: .utf8)
    let fileURL = paths[0].appendingPathComponent(config.logDirectoryName).appendingPathComponent(
      fileName)

    localLogFileManager?.createLocalLogDirectory()
    do {
      try data?.write(to: fileURL)
    } catch {
      XCTFail("Unable to write test file in testDeleteLocalLogFile")
    }
    return fileURL
  }

  internal func isLogFileDirectoryEmpty() -> Bool {
    return logFileDirectoryFileCount() == 0
  }

  internal func logFileDirectoryFileCount() -> Int {
    let pathURL = paths[0].appendingPathComponent(config.logDirectoryName)
    do {
      let files = try FileManager.default.contentsOfDirectory(
        at: pathURL, includingPropertiesForKeys: nil)
      return files.count
    } catch {

    }
    XCTFail("Unable to determine how many files in the test log directory")
    return 0
  }

  internal func deleteAllLogFiles() {
    var isDir: ObjCBool = false
    let directoryFileURL = paths[0].appendingPathComponent(config.logDirectoryName)
    guard FileManager.default.fileExists(atPath: directoryFileURL.path, isDirectory: &isDir) else {
      return
    }
    do {
      let files = try FileManager.default.contentsOfDirectory(
        at: directoryFileURL, includingPropertiesForKeys: nil)
      for file in files {
        try FileManager.default.removeItem(at: file)
      }
    } catch let error {
      XCTFail("Unable to delete file during deleteAllLogFiles \(error.localizedDescription)")
    }
  }
}
