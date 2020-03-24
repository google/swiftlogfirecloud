import XCTest
@testable import SwiftLogFireCloud

final class LocalLogFileManagerTests: XCTestCase {

    var locaLogFileManager: LocalLogFileManager?
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let testingLogFileDirectoryName = "TestLogs"
    
    private func removeLogDirectory() {
        XCTAssert(paths.count > 0)
        var documentsDirectory = paths[0]
        documentsDirectory.appendPathComponent(testingLogFileDirectoryName)
        
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
    
    private func writeDummyLogFile(fileName: String) -> URL {
        let data = "I am test data for a about to be deleted file".data(using: .utf8)
        let fileURL = paths[0].appendingPathComponent(testingLogFileDirectoryName).appendingPathComponent(fileName)
        
        locaLogFileManager?.createLocalLogDirectory()
        do {
            try data?.write(to: fileURL)
        } catch {
            XCTFail("Unable to write test file in testDeleteLocalLogFile")
        }
        return fileURL
    }
    
    private func isLogFileDirectoryEmpty() -> Bool {
        return logFileDirectoryFileCount() == 0
    }
    
    private func logFileDirectoryFileCount() -> Int {
        let pathURL =  paths[0].appendingPathComponent(testingLogFileDirectoryName)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: pathURL, includingPropertiesForKeys: nil)
            return files.count
        } catch {

        }
        XCTFail()
        return 0
    }
    
    override func setUp() {
        locaLogFileManager = LocalLogFileManager(clientDeviceID: "TestClientID", logToCloud: false, bufferWriteSize: 100, logFileDirectoryName: testingLogFileDirectoryName, writeTimeInterval: 60)
        removeLogDirectory()

    }
    
    override func tearDown() {
        removeLogDirectory()
    }
    
    func testCreateLocalLogDirectorySuccessful() {
        
        guard let locaLogFileManager = locaLogFileManager else { XCTFail(); return }
        
        locaLogFileManager.createLocalLogDirectory()
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        XCTAssert(paths.count > 0)
        var documentsDirectory = paths[0]
        documentsDirectory.appendPathComponent(testingLogFileDirectoryName)
        
        var isDir: ObjCBool = false
        let logDirectoryExists = FileManager.default.fileExists(atPath: documentsDirectory.path, isDirectory: &isDir)
        
        XCTAssert(logDirectoryExists && isDir.boolValue)
        
    }
    
    func testDeleteLocalLogFile() {
        
        guard let locaLogFileManager = locaLogFileManager else { XCTFail(); return }
        
        let fileURL = writeDummyLogFile(fileName: "TestLogFileName.log")
        
        locaLogFileManager.deleteLocalFile(fileURL)
        
        var isDir: ObjCBool = false
        let testLogFileExists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
        
        XCTAssert(testLogFileExists == false && isDir.boolValue == false)
    }
    
    func testRetreieveLocalLogFileListOnDiskWhenEmpty() {
        
        guard let locaLogFileManager = locaLogFileManager else { XCTFail(); return }
        locaLogFileManager.createLocalLogDirectory()
        let urls = locaLogFileManager.retrieveLocalLogFileListOnDisk()
        
        XCTAssert(urls.count == 0)
        
    }
    
    func testRetrieveLocalLogFileListOnDiskWhenNotEmpty() {
        guard let locaLogFileManager = locaLogFileManager else { XCTFail(); return }
        
        let fileURL1 = writeDummyLogFile(fileName: "TestLogFileName1.log")
        let fileURL2 = writeDummyLogFile(fileName: "TestLogFileName2.log")
        
        let urls = locaLogFileManager.retrieveLocalLogFileListOnDisk()

        XCTAssert(urls.contains(fileURL1))
        XCTAssert(urls.contains(fileURL2))
        XCTAssert(urls.count == 2)
    }
    
    func testProcessStrandedFilesAtStartup() {
        
        guard let locaLogFileManager = locaLogFileManager else { XCTFail(); return }
        
        _ = writeDummyLogFile(fileName: "TestLogFileName1.log")
        _ = writeDummyLogFile(fileName: "TestLogFileName2.log")
        
        let expectation = XCTestExpectation(description: "testProcessStrandedFilesAtStartup")
        
        // the logger init is setup to not log to cloud, so it should just delete files.
        locaLogFileManager.processStrandedFilesAtStartup {
            XCTAssertTrue(self.isLogFileDirectoryEmpty())
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
    
    static var allTests = [
        ("testCreateLocalLogDirectorySuccessful", testCreateLocalLogDirectorySuccessful),
        ("testDeleteLocalLogFile", testDeleteLocalLogFile),
        ("testRetreieveLocalLogFileListOnDiskWhenEmpty", testRetreieveLocalLogFileListOnDiskWhenEmpty),
        ("testRetrieveLocalLogFileListOnDiskWhenNotEmpty", testRetrieveLocalLogFileListOnDiskWhenNotEmpty),
        ("testProcessStrandedFilesAtStartup", testProcessStrandedFilesAtStartup),
    ]
}
