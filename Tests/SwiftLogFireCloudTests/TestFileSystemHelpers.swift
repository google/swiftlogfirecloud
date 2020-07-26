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

class TestFileSystemHelpers {

  let path: URL
  let config: SwiftLogFireCloudConfig

  init(path: URL, config: SwiftLogFireCloudConfig) {
    self.path = path
    self.config = config
  }
  
  internal func flood(handler: SwiftLogFireCloud) {
    let sampleLogString = "This is a sample log string"
    for _ in 0...3 {
      handler.log(level: .info, message: "\(sampleLogString)", metadata: nil)
    }
    return
  }
  
  internal func flood(localLogFile: LocalLogFile) -> String? {
    let sampleLogString = "This is a sample log string\n"
    guard let sampleLogData = sampleLogString.data(using: .utf8) else {
      XCTFail("Unable to flood log as conversion from string to data failed")
      return nil
    }
    var logData = Data()
    for _ in 0...20 {
      localLogFile.writeMessage(sampleLogData)
      logData.append(sampleLogData)
    }
    return String(bytes: logData, encoding: .utf8)
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
      XCTFail("Unable to write test file in writeDummyLogFile")
    }
    return fileURL
  }
  
  internal func readDummyLogFile(fileName: String) -> String? {
    let fileURL = path.appendingPathComponent(config.logDirectoryName).appendingPathComponent(fileName)
    
     return readDummyLogFile(url: fileURL)
  }
  
  internal func readDummyLogFile(url: URL) -> String? {
    do {
      let logString = try String(contentsOf: url)
      return logString
    } catch let error {
      print(error.localizedDescription)
      XCTFail("Unable to read from test file \(url.absoluteString) in readDummyLogFile")
    }
    return nil
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
