//
//  LocalLogFileTests-Helpers.swift
//  SwiftLogFireCloud
//
//  Created by Timothy Wise on 7/4/20.
//

import XCTest

@testable import SwiftLogFireCloud

extension LocalLogFileTests {

  internal func floodLocalLogFileBuffer() -> String? {
    let sampleLogString = "This is a sample log string\n"
    for _ in 0...20 {
      testLogFile.buffer.append(sampleLogString.data(using: .utf8)!)
    }
    return String(bytes: testLogFile.buffer, encoding: .utf8)
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

  internal func createLocalLogDirectory() {
    guard config.logDirectoryName.count > 0 else { return }
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)

    let pathURL = paths[0].appendingPathComponent(config.logDirectoryName)
    do {
      try FileManager.default.createDirectory(
        at: pathURL, withIntermediateDirectories: true, attributes: nil)
    } catch {
      XCTFail("Unable to create test log directory")
    }
  }

  internal func writeDummyLogFile(fileName: String) -> URL {
    let data = "I am test data for a about to be deleted file".data(using: .utf8)
    let fileURL = paths[0].appendingPathComponent(config.logDirectoryName).appendingPathComponent(
      fileName)

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
