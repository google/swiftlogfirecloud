//
//  TestFileSystemHelpers.swift
//  SwiftLogFireCloudTests
//
//  Created by Timothy Wise on 7/5/20.
//

import Logging
import XCTest

@testable import SwiftLogFireCloud

class TestFileSystemHelpers {

  let path: URL
  let config: SwiftLogFileCloudConfig

  init(path: URL, config: SwiftLogFileCloudConfig) {
    self.path = path
    self.config = config
  }
  internal func flood(localLogFile: LocalLogFile) -> String? {
    let sampleLogString = "This is a sample log string\n"
    for _ in 0...20 {
      localLogFile.append(sampleLogString.data(using: .utf8)!)
    }
    return String(bytes: localLogFile.buffer, encoding: .utf8)
  }

  internal func flood(logger: Logger) {
    let sampleLogString = "This is a sample log string"
    for _ in 0...3 {
      logger.info("\(sampleLogString)")
    }
    return
  }

  internal func removeLogDirectory() {
    var documentsDirectory = path
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

  internal func writeDummyLogFile(fileName: String)
    -> URL
  {
    let data = "I am test data for a about to be deleted file".data(using: .utf8)
    let fileURL = path.appendingPathComponent(config.logDirectoryName).appendingPathComponent(
      fileName)

    do {
      try data?.write(to: fileURL)
    } catch let error {
      print(error.localizedDescription)
      XCTFail("Unable to write test file in testWriteLocalLogFile")
    }
    return fileURL
  }

  internal func isLogFileDirectoryEmpty() -> Bool {
    return logFileDirectoryFileCount() == 0
  }

  internal func logFileDirectoryFileCount() -> Int {
    return logFileDirectoryContents().count
  }

  internal func logFileDirectoryContents() -> [URL] {
    let pathURL = path.appendingPathComponent(config.logDirectoryName)
    do {
      let files = try FileManager.default.contentsOfDirectory(
        at: pathURL, includingPropertiesForKeys: nil)
      return files
    } catch {

    }
    XCTFail("Unable to determine how many files in the test log directory")
    return []
  }

  internal func deleteAllLogFiles() {
    var isDir: ObjCBool = false
    let directoryFileURL = path.appendingPathComponent(config.logDirectoryName)
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
