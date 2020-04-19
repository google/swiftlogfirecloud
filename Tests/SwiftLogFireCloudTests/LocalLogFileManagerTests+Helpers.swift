//
//  LocalLogFileManagerTests+Helpers.swift
//  SwiftLogFireCloud
//
//  Created by Timothy Wise on 3/24/20.
//

import XCTest
@testable import SwiftLogFireCloud

extension LocalLogFileManagerTests {
    
    internal func removeLogDirectory() {
        XCTAssert(paths.count > 0)
        var documentsDirectory = paths[0]
        documentsDirectory.appendPathComponent(config.logDirectoryName)
        
        var isDir: ObjCBool = false
        let logDirectoryExists = FileManager.default.fileExists(atPath: documentsDirectory.path, isDirectory: &isDir)
        
        if logDirectoryExists {
            do {
                try FileManager.default.removeItem(at: documentsDirectory)
            } catch {
                XCTFail()
            }
        }
    }
    
    internal func writeDummyLogFile(fileName: String) -> URL {
        let data = "I am test data for a about to be deleted file".data(using: .utf8)
        let fileURL = paths[0].appendingPathComponent(config.logDirectoryName).appendingPathComponent(fileName)
        
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
        let pathURL =  paths[0].appendingPathComponent(config.logDirectoryName)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: pathURL, includingPropertiesForKeys: nil)
            return files.count
        } catch {

        }
        XCTFail("Unable to determine how many files in the test log directory")
        return 0
    }
}
