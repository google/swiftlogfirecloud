import XCTest
@testable import SwiftLogFireCloud

final class LocalLogFileManagerTests: XCTestCase {

    var localLogFileManager: LocalLogFileManager?
    var fakeCloudLogFileManager: FakeCloudLogFileManager?
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let config = SwiftLogFileCloudConfig(logToCloud: false, localFileBufferSize: 100, localFileBufferWriteInterval: 60, uniqueID: "TestClientID", minFileSystemFreeSpace: 20, logDirectoryName: "TestLogs")
    
    override func setUp() {
        
        fakeCloudLogFileManager = FakeCloudLogFileManager()
        guard let fakeCloudLogFileManager = fakeCloudLogFileManager else { XCTFail("fake cloud log file manager failed to initialize") ; return }
        localLogFileManager = LocalLogFileManager(config: config, cloudLogfileManager: fakeCloudLogFileManager)
        removeLogDirectory()

    }
    
    override func tearDown() {
        removeLogDirectory()
    }
    
    func testCreateLocalLogDirectorySuccessful() {
        
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        localLogFileManager.createLocalLogDirectory()
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        XCTAssert(paths.count > 0)
        var documentsDirectory = paths[0]
        documentsDirectory.appendPathComponent(config.logDirectoryName)
        
        var isDir: ObjCBool = false
        let logDirectoryExists = FileManager.default.fileExists(atPath: documentsDirectory.path, isDirectory: &isDir)
        
        XCTAssert(logDirectoryExists && isDir.boolValue)
        
    }
    
    func testDeleteLocalLogFile() {
        
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        let fileURL = writeDummyLogFile(fileName: "TestLogFileName.log")
        
        localLogFileManager.deleteLocalFile(fileURL)
        
        var isDir: ObjCBool = false
        let testLogFileExists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir)
        
        XCTAssert(testLogFileExists == false && isDir.boolValue == false)
    }
    
    // MARK: testRetreiveLocalLogFileList
    func testRetreieveLocalLogFileListOnDiskWhenEmptyShouldFindDirectoryContentsNil() {
        
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        localLogFileManager.createLocalLogDirectory()
        let urls = localLogFileManager.retrieveLocalLogFileListOnDisk()
        
        XCTAssert(urls.count == 0)
        
    }
    
    func testRetrieveLocalLogFileListOnDiskWhenNotEmptyShouldFindFiles() {
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        let fileURL1 = writeDummyLogFile(fileName: "TestLogFileName1.log")
        let fileURL2 = writeDummyLogFile(fileName: "TestLogFileName2.log")
        
        let urls = localLogFileManager.retrieveLocalLogFileListOnDisk()

        XCTAssert(urls.contains(fileURL1))
        XCTAssert(urls.contains(fileURL2))
        XCTAssert(urls.count == 2)
    }
    
    // MARK: tesProcessStrandedFilesAtStartup
    func testProcessStrandedFilesAtStartupWhenNotLoggingToCloudShouldDeleteLocalFiles() {
        
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
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
        
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
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
    
    // MARK: testAppWillResumeActive
    func testAppWillResumeActiveWhenTimerStoppedShouldRestartWriteTimer() {
        
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        if localLogFileManager.writeTimer?.isValid ?? false {
            localLogFileManager.writeTimer?.invalidate()
        }
        
        localLogFileManager.appWillResumeActive()
        
        XCTAssertTrue(localLogFileManager.writeTimer?.isValid ?? false)
    }
    
    func testAppWillResumeActiveWhenTimerActiveShouldStillHaveActiveTimer() {
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        XCTAssertTrue(localLogFileManager.writeTimer?.isValid ?? false)
        
        localLogFileManager.appWillResumeActive()
        
        XCTAssertTrue(localLogFileManager.writeTimer?.isValid ?? false)
    }
    
    // MARK: testAppWillResignActive
    func testAppWillResignActiveShouldWriteFileToCloudAndStopTimer() {

        let config = SwiftLogFileCloudConfig(logToCloud: true, uniqueID: "testDevice", logDirectoryName: "TestLogs")
        
        let fakeCloudLogFileManager = FakeCloudLogFileManager()
        let localLogFileManager = LocalLogFileManager(config: config, cloudLogfileManager: fakeCloudLogFileManager)
        
        guard let localFileURL = localLogFileManager.localLogFile.fileURL else {
            XCTFail("No local file created")
            return
        }

        let expectation = XCTestExpectation(description: "testAppWillResignActiveShouldWriteFileToCloudAndStopTimer")
        localLogFileManager.appWillResignActive() {
            XCTAssert(fakeCloudLogFileManager.recentWrittenFiles.contains(localFileURL))
            expectation.fulfill()
        }
        XCTAssertFalse(localLogFileManager.writeTimer?.isValid ?? false)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: testFirstWriteOfLocalFile
    func testtFirstWriteOfLocalFileShouldWriteFileData() {
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        guard let fileURL = localLogFileManager.localLogFile.fileURL else { XCTFail(); return }
        
        let sampleLogString = "Sample Log Message"
        guard let sampleLogData = sampleLogString.data(using: .utf8) else { XCTFail(); return }
        
        localLogFileManager.localLogFile.buffer = sampleLogData
        localLogFileManager.createLocalLogDirectory()
        localLogFileManager.firstWriteOfLocalLogFile(fileURL: fileURL)
        
        do {
            let textRead = try String(contentsOf: fileURL)
            XCTAssert(textRead == sampleLogString)
        } catch {
            XCTFail("Unable to read the written text file in testtFirstWriteOfLocalFileShouldWriteFileData()")
        }
    }
    
    // MARK: testAppendToExistingLocalLogFile
    func testAppendToExistingLocalLogFileShouldAppendFile() {
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        guard let fileURL = localLogFileManager.localLogFile.fileURL else { XCTFail(); return }
        
        let sampleLogString1 = "Sample Log Message"
        guard let sampleLogData1 = sampleLogString1.data(using: .utf8) else { XCTFail(); return }
        
        localLogFileManager.createLocalLogDirectory()
        do {
            try sampleLogData1.write(to: fileURL)
        } catch {
            XCTFail("Unable to write initial text file in testAppendToExistingLocalLogFileShouldAppendFile()")
        }
        
        let sampleLogString2 = "Appended sample log message"
        guard let sampleLogData2 = sampleLogString2.data(using: .utf8) else { XCTFail(); return }
        
        localLogFileManager.localLogFile.buffer = sampleLogData2
        localLogFileManager.appendToExistingLocalLogFile(fileURL: fileURL, closeAndSynchronize: true)
        
        do {
            let textRead = try String(contentsOf: fileURL)
            XCTAssert(textRead == "\(sampleLogString1)\(sampleLogString2)")
        } catch {
            XCTFail("Unable to read appended text file in testAppendToExistingLocalLogFileShouldAppendFile()")
        }
    }
    
    // MARK: testAssessLocalLogability
    
    func testAssessLocalLogabilityWhenDiskSpaceInsufficientShouldBeImpaired() {
        var config = self.config
        config.minFileSystemFreeSpace = SwiftLogFileCloudConfig.megabyte * 10_000_000_000 // FLAKY: this will fail when devices and simulators ship with 10PB.
        
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
    
    // MARK: testTrimBufferIfNecessary
    func testTrimBufferIfNecessaryWithEmptyBufferShouldStillBeEmpty() {
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        localLogFileManager.trimBufferIfNecessary()
        
        XCTAssert(localLogFileManager.localLogFile.buffer.count == 0)
    }
    
    func testTrimBufferIfNecessaryWithOverflowingBufferShouldResetBufferAndDeleteFiles() {
        guard let localLogFileManager = localLogFileManager else { XCTFail(); return }
        
        let sampleLogString = "This is a Sample Log String"
        guard let sampleLogData = sampleLogString.data(using: .utf8) else { XCTFail(); return }
        
        for _ in 1...50 {
            localLogFileManager.localLogFile.buffer.append(sampleLogData)
        }
        _ = writeDummyLogFile(fileName: "tokenLogFile.log")
        
        localLogFileManager.trimBufferIfNecessary()
        
        XCTAssert(localLogFileManager.localLogFile.buffer.count == 0)
        XCTAssert(isLogFileDirectoryEmpty())
    }
    
    static var allTests = [
        ("testCreateLocalLogDirectorySuccessful", testCreateLocalLogDirectorySuccessful),
        ("testDeleteLocalLogFile", testDeleteLocalLogFile),
        ("testRetreieveLocalLogFileListOnDiskWhenEmptyShouldFindDirectoryContentsNil", testRetreieveLocalLogFileListOnDiskWhenEmptyShouldFindDirectoryContentsNil),
        ("testRetrieveLocalLogFileListOnDiskWhenNotEmptyShouldFindFiles", testRetrieveLocalLogFileListOnDiskWhenNotEmptyShouldFindFiles),
        ("testProcessStrandedFilesAtStartupWhenNotLoggingToCloudShouldDeleteLocalFiles", testProcessStrandedFilesAtStartupWhenNotLoggingToCloudShouldDeleteLocalFiles),
        ("testProcessStrandedFilesAtStartupWheLoggingToCloudShouldPutFilesOnQueue", testProcessStrandedFilesAtStartupWheLoggingToCloudShouldPutFilesOnQueue),
        ("testIsFileSystemFreeSpaceSufficent", testIsFileSystemFreeSpaceSufficent),
        ("testIsFileSystemFreeSpaceSufficeintWhenNot", testIsFileSystemFreeSpaceSufficeintWhenNot),
        ("testAppWillResumeActiveWhenTimerStoppedShouldRestartWriteTimer", testAppWillResumeActiveWhenTimerStoppedShouldRestartWriteTimer),
        ("testAppWillResumeActiveWhenTimerActiveShouldStillHaveActiveTimer", testAppWillResumeActiveWhenTimerActiveShouldStillHaveActiveTimer),
        ("testAppWillResignActiveShouldWriteFileToCloudAndStopTimer", testAppWillResignActiveShouldWriteFileToCloudAndStopTimer),
        ("testtFirstWriteOfLocalFileShouldWriteFileData", testtFirstWriteOfLocalFileShouldWriteFileData),
        ("testAppendToExistingLocalLogFileShouldAppendFile", testAppendToExistingLocalLogFileShouldAppendFile),
        ("testAssessLocalLogabilityWhenDiskSpaceInsufficientShouldBeImpaired", testAssessLocalLogabilityWhenDiskSpaceInsufficientShouldBeImpaired),
        ("testAssessLocalLogabilityWhenNoWritesAttemptedShouldBeNormal",testAssessLocalLogabilityWhenNoWritesAttemptedShouldBeNormal),
        ("testAssessLocalLogabilityWhenLastWriteIsAllCasesShouldReturnAllLogabilities", testAssessLocalLogabilityWhenLastWriteIsAllCasesShouldReturnAllLogabilities),
        ("testTrimBufferIfNecessaryWithEmptyBufferShouldStillBeEmpty", testTrimBufferIfNecessaryWithEmptyBufferShouldStillBeEmpty),
        ("testTrimBufferIfNecessaryWithOverflowingBufferShouldResetBufferAndDeleteFiles", testTrimBufferIfNecessaryWithOverflowingBufferShouldResetBufferAndDeleteFiles),
        
    ]
}
