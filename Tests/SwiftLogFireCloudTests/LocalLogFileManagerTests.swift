import XCTest
@testable import SwiftLogFireCloud

final class LocalLogFileManagerTests: XCTestCase {

    var localLogFileManager: LocalLogFileManager!
    var fakeCloudLogFileManager: FakeCloudLogFileManager?
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let config = SwiftLogFileCloudConfig(logToCloud: false, localFileSizeThresholdToPushToCloud: 100, localFileBufferWriteInterval: 60, uniqueID: "TestClientID", minFileSystemFreeSpace: 20, logDirectoryName: "TestLogs", logToCloudOnSimulator: false)
    
    override func setUp() {
        
        fakeCloudLogFileManager = FakeCloudLogFileManager()
        guard let fakeCloudLogFileManager = fakeCloudLogFileManager else { XCTFail("fake cloud log file manager failed to initialize") ; return }
        localLogFileManager = LocalLogFileManager(config: config, cloudLogfileManager: fakeCloudLogFileManager)
        removeLogDirectory()

    }
    
    override func tearDown() {
        deleteAllLogFiles()
        removeLogDirectory()
    }
    
    func testCreateLocalLogDirectorySuccessful() {
        
        localLogFileManager.createLocalLogDirectory()
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        XCTAssert(paths.count > 0)
        var documentsDirectory = paths[0]
        documentsDirectory.appendPathComponent(config.logDirectoryName)
        
        var isDir: ObjCBool = false
        let logDirectoryExists = FileManager.default.fileExists(atPath: documentsDirectory.path, isDirectory: &isDir)
        
        XCTAssert(logDirectoryExists && isDir.boolValue)
    }
    
    func testRetreieveLocalLogFileListOnDiskWhenEmptyShouldFindDirectoryContentsNil() {

        localLogFileManager.createLocalLogDirectory()
        let urls = localLogFileManager.retrieveLocalLogFileListOnDisk()
        
        XCTAssert(urls.count == 0)
    }
    
    func testRetrieveLocalLogFileListOnDiskWhenNotEmptyShouldFindFiles() {
        
        let fileURL1 = writeDummyLogFile(fileName: "TestLogFileName1.log")
        let fileURL2 = writeDummyLogFile(fileName: "TestLogFileName2.log")
        
        let logFiles = localLogFileManager.retrieveLocalLogFileListOnDisk()
      
        var logFileURLs = Set<URL>()
        for logFile in logFiles where logFile.fileURL != nil {
          logFileURLs.insert(logFile.fileURL!)
        }

        XCTAssert(logFileURLs.contains(fileURL1))
        XCTAssert(logFileURLs.contains(fileURL2))
        XCTAssert(logFileURLs.count == 2)
    }
    
    func testProcessStrandedFilesAtStartupWhenNotLoggingToCloudShouldDeleteLocalFiles() {
        
        _ = writeDummyLogFile(fileName: "TestLogFileName1.log")
        _ = writeDummyLogFile(fileName: "TestLogFileName2.log")
        
        let expectation = XCTestExpectation(description: "testProcessStrandedFilesAtStartup")
        
        // the logger init is setup to not log to cloud, so it should just delete files.
        localLogFileManager.processStrandedFilesAtStartup {
            XCTAssertTrue(self.isLogFileDirectoryEmpty())
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testProcessStrandedFilesAtStartupWheLoggingToCloudShouldPutFilesOnQueue() {
        var config = self.config
        config.logToCloud = true
        
        // create a special localLogFileManager with an updated config
        let fakeCloudLogFileManager = FakeCloudLogFileManager()
        let localLogFileManager = LocalLogFileManager(config: config, cloudLogfileManager: fakeCloudLogFileManager)
        
        let fileURL1 = writeDummyLogFile(fileName: "TestLogFileName1.log")
        let fileURL2 = writeDummyLogFile(fileName: "TestLogFileName2.log")
        
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
    
    // MARK: testIsFileSystemFreeSpaceSufficient()
    func testIsFileSystemFreeSpaceSufficent() {

        guard let totalDiskSpaceInBytes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[FileAttributeKey.systemFreeSize] as? Int64 else { XCTFail(); return}
        
        XCTAssert((totalDiskSpaceInBytes > 20 * 1048576 && localLogFileManager.isFileSystemFreeSpaceSufficient()) ||
            (totalDiskSpaceInBytes < 20 * 1048576 && !localLogFileManager.isFileSystemFreeSpaceSufficient()))
    }
    
    func testIsFileSystemFreeSpaceSufficeintWhenNot() {
        var config = self.config
        config.minFileSystemFreeSpace = SwiftLogFileCloudConfig.megabyte * 10_000_000_000 // FLAKY: this will fail when devices and simulators ship with 10PB.
        
        let fakeCloudLogFileManager = FakeCloudLogFileManager()
        let localLogFileManager = LocalLogFileManager(config: config, cloudLogfileManager: fakeCloudLogFileManager)
        XCTAssertFalse(localLogFileManager.isFileSystemFreeSpaceSufficient())
    }
    
    func testAppWillResumeActiveWhenTimerStoppedShouldRestartWriteTimer() {
        
        if localLogFileManager.writeTimer?.isValid ?? false {
            localLogFileManager.writeTimer?.invalidate()
        }
        
        localLogFileManager.appWillResumeActive()
        
        XCTAssertTrue(localLogFileManager.writeTimer?.isValid ?? false)
    }
    
    func testAppWillResumeActiveWhenTimerActiveShouldStillHaveActiveTimer() {
        
        XCTAssertTrue(localLogFileManager.writeTimer?.isValid ?? false)
        
        localLogFileManager.appWillResumeActive()
        
        XCTAssertTrue(localLogFileManager.writeTimer?.isValid ?? false)
    }
    
    func testAppWillResignActiveShouldWriteFileToCloudAndStopTimer() {

      let config = SwiftLogFileCloudConfig(logToCloud: true, localFileSizeThresholdToPushToCloud: 400, uniqueID: "testDevice", logDirectoryName: "TestLogs", logToCloudOnSimulator: true)
        
        let fakeCloudLogFileManager = FakeCloudLogFileManager()
        let localLogFileManager = LocalLogFileManager(config: config, cloudLogfileManager: fakeCloudLogFileManager)
        
        guard let localFileURL = localLogFileManager.localLogFile.fileURL else {
            XCTFail("No local file created")
            return
        }
        let bufferStr = floodLocalLogFileBuffer()
        localLogFileManager.localLogFile.buffer = (bufferStr?.data(using: .utf8))!
        localLogFileManager.localLogFile.writeLogFileToDisk(shouldSychronize: true)

        let expectation = XCTestExpectation(description: "testAppWillResignActiveShouldWriteFileToCloudAndStopTimer")
        localLogFileManager.appWillResignActive() {
            expectation.fulfill()
      }
        
        wait(for: [expectation], timeout: 5.0)
        XCTAssert(fakeCloudLogFileManager.recentWrittenFiles.contains(localFileURL))
        XCTAssertFalse(localLogFileManager.writeTimer?.isValid ?? false)
    }
    
    func testAssessLocalLogabilityWhenDiskSpaceInsufficientShouldBeImpaired() {
        var config = self.config
        // FLAKY: this will fail when devices and simulators ship with 10PB.
        config.minFileSystemFreeSpace = SwiftLogFileCloudConfig.megabyte * 10_000_000_000
        
        let fakeCloudLogFileManager = FakeCloudLogFileManager()
        let localLogFileManager = LocalLogFileManager(config: config, cloudLogfileManager: fakeCloudLogFileManager)
        
        let logability = localLogFileManager.assessLocalLogability()
        
        XCTAssert(logability == .impaired)
    }
    
    func testAssessLocalLogabilityWhenNoWritesAttemptedShouldBeNormal() {
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        let logability = localLogFileManager.assessLocalLogability()
        
        XCTAssert(logability == .normal)
    }
    
    func testAssessLocalLogabilityWhenLastWriteIsAllCasesShouldReturnAllLogabilities() {
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        localLogFileManager.localLogFile.lastFileWriteAttempt = Date()
        
        localLogFileManager.localLogFile.lastFileWrite = Date(timeInterval: -900, since: Date())
        let unFunctionalLogability = localLogFileManager.assessLocalLogability()
        XCTAssert(unFunctionalLogability == .unfunctional)
        
        localLogFileManager.localLogFile.lastFileWrite = Date(timeInterval: -300, since: Date())
        let impairedLogability = localLogFileManager.assessLocalLogability()
        XCTAssert(impairedLogability == .impaired)
        
        localLogFileManager.localLogFile.lastFileWrite = Date(timeInterval: -60, since: Date())
        let normalLogability = localLogFileManager.assessLocalLogability()
        XCTAssert(normalLogability == .normal)
        
    }
    
    func testAssessLocalLogabilityWhenSuccessiveFailuresAllCasesShouldReturnAllLogabilites() {
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        localLogFileManager.localLogFile.lastFileWriteAttempt = Date()
        
        localLogFileManager.localLogFile.successiveWriteFailures = 100
        let unFunctionalLogability = localLogFileManager.assessLocalLogability()
        XCTAssert(unFunctionalLogability == .unfunctional)
        
        localLogFileManager.localLogFile.successiveWriteFailures = 40
        let impairedLogability = localLogFileManager.assessLocalLogability()
        XCTAssert(impairedLogability == .impaired)
        
        localLogFileManager.localLogFile.successiveWriteFailures = 10
        let normalLogability = localLogFileManager.assessLocalLogability()
               XCTAssert(normalLogability == .normal)
    }
    
    static var allTests = [
        ("testCreateLocalLogDirectorySuccessful", testCreateLocalLogDirectorySuccessful),
        ("testRetreieveLocalLogFileListOnDiskWhenEmptyShouldFindDirectoryContentsNil", testRetreieveLocalLogFileListOnDiskWhenEmptyShouldFindDirectoryContentsNil),
        ("testRetrieveLocalLogFileListOnDiskWhenNotEmptyShouldFindFiles", testRetrieveLocalLogFileListOnDiskWhenNotEmptyShouldFindFiles),
        ("testProcessStrandedFilesAtStartupWhenNotLoggingToCloudShouldDeleteLocalFiles", testProcessStrandedFilesAtStartupWhenNotLoggingToCloudShouldDeleteLocalFiles),
        ("testProcessStrandedFilesAtStartupWheLoggingToCloudShouldPutFilesOnQueue", testProcessStrandedFilesAtStartupWheLoggingToCloudShouldPutFilesOnQueue),
        ("testIsFileSystemFreeSpaceSufficent", testIsFileSystemFreeSpaceSufficent),
        ("testIsFileSystemFreeSpaceSufficeintWhenNot", testIsFileSystemFreeSpaceSufficeintWhenNot),
        ("testAppWillResumeActiveWhenTimerStoppedShouldRestartWriteTimer", testAppWillResumeActiveWhenTimerStoppedShouldRestartWriteTimer),
        ("testAppWillResumeActiveWhenTimerActiveShouldStillHaveActiveTimer", testAppWillResumeActiveWhenTimerActiveShouldStillHaveActiveTimer),
        ("testAppWillResignActiveShouldWriteFileToCloudAndStopTimer", testAppWillResignActiveShouldWriteFileToCloudAndStopTimer),
        ("testAssessLocalLogabilityWhenDiskSpaceInsufficientShouldBeImpaired", testAssessLocalLogabilityWhenDiskSpaceInsufficientShouldBeImpaired),
        ("testAssessLocalLogabilityWhenNoWritesAttemptedShouldBeNormal",testAssessLocalLogabilityWhenNoWritesAttemptedShouldBeNormal),
        ("testAssessLocalLogabilityWhenLastWriteIsAllCasesShouldReturnAllLogabilities", testAssessLocalLogabilityWhenLastWriteIsAllCasesShouldReturnAllLogabilities),
    ]
}
