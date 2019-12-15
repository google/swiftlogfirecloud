#if os(iOS)
import UIKit
#endif

class LocalLogFileManager {
    
    private var localLogFile: LocalLogFile
    private var logToCloud: Bool
    private var logToCloudOnSimulator = true // set only when testing the library only.
    private let localLogQueue = DispatchQueue(label: "com.leisurehoundsports.swiftfirelogcloud-local", qos: .background)
    private let localLogFileDeleteQueue = DispatchQueue(label: "com.leisurehoundsports.swiftfirelogcloud-localfilesdelete", qos: .background)
    private var localLogDirectoryName: String
    private var defaultLocalLogWriteFileSize: Int
    private var localLogability: Logability = .normal
    private var writeTimer: Timer?
    private var resignActiveObserverSet = false
    private var clientDeviceID: String?
    private var localFileWriteToPushFactor = 0.25
    
    private enum Logability {
        case normal
        case impaired
        case unfunctional
    }
    
    private struct LocalLogFile {
        var buffer: String = ""
        var fileURL: URL?
        var bufferWriteSize: Int
        var bytesWritten: Int = 0
        var firstFileWrite: Date?
        var lastFileWrite: Date?
        var lastFileWriteAttempt: Date?
        var successiveWriteFailures: Int = 0
        private static let dateFormatter: DateFormatter = {
                let dateFormatter = DateFormatter()
                dateFormatter.timeZone = TimeZone.current
                dateFormatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSSZ'"
                return dateFormatter
        }()
        
        fileprivate func createLogFileName(deviceId: String?) -> String {
            var deviceIdForFileName = deviceId
            if deviceId == nil || deviceId?.count == 0 {
                deviceIdForFileName = UIDevice.current.identifierForVendor?.uuidString
            }
            let fileDateString = LocalLogFile.dateFormatter.string(from: Date())
            let bundleString = Bundle.main.bundleIdentifier
            let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            
            var fileString: String = ""
            if let deviceID = deviceIdForFileName {
                fileString += "\(deviceID)"
            }
            fileString += "-\(fileDateString)"
            if let bundleString = bundleString {
                fileString += "-\(bundleString)"
            }
            if let buildNumber = buildNumber, let versionNumber = versionNumber {
                fileString += "-v\(versionNumber)b\(buildNumber)"
            }

            fileString += ".log"
            return fileString.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! //TODO this shoudl always escape, but be better here
        }
        
        init(bufferWriteSize: Int = 1048576) {
            self.bufferWriteSize = bufferWriteSize
            #if targetEnvironment(simulator)
                self.bufferWriteSize = 1024 * 16
            #endif
        }
    }
    
    init(clientDeviceID: String? = nil, logToCloud: Bool = false, bufferWriteSize: Int = 1048576, logFileDirectoryName: String = "Logs", writeTimeInterval: TimeInterval = 60.0) {
        self.localLogDirectoryName = logFileDirectoryName
        self.defaultLocalLogWriteFileSize = bufferWriteSize
        self.clientDeviceID = clientDeviceID
        self.logToCloud = logToCloud
        
        //TODO:  make this an optional, if logToCloud is false we'll still have a LocalLogFile manager to clean up previous runs, but the localLogFile can be nil
        self.localLogFile = LocalLogFile()
        
        writeTimer = Timer.scheduledTimer(timeInterval: writeTimeInterval, target: self, selector: #selector(timedAtemptToWriteToDisk), userInfo: nil, repeats: true)
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        resignActiveObserverSet = true
        
        //wait 15s after startup, then attempt to push any files from previous runs up to cloud
        _ = Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(processStrandedFilesAtStartup), userInfo: nil, repeats: false)
        
        #if targetEnvironment(simulator)
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        print("Log File location: \(paths[0].appendingPathComponent(localLogDirectoryName))")
        #endif
    }
    
    deinit {
        if resignActiveObserverSet {
            NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
            resignActiveObserverSet = false // because who knows.
        }
    }
    
    @objc private func appWillResignActive() {
        localLogQueue.async {  //TODO: make this a background task
            self.writeLogFileToDisk(forceFlushToCloud: true)
        }
    }
    
    private func createLocalLogDirectory() {
        guard localLogDirectoryName.count > 0 else { return }
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        
        let pathURL =  paths[0].appendingPathComponent(localLogDirectoryName)
        do {
            try FileManager.default.createDirectory(at: pathURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            localLogDirectoryName = ""
            //TODO:  handle the case of directory creation not successful
        }
    }
    
    private func deleteLocalFile(fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            //do nothing if it fails, it will get retried on next restart.
        }
    }
    
    private func retrieveLocalLogFileListOnDisk() -> [URL] {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        
        let pathURL =  paths[0].appendingPathComponent(self.localLogDirectoryName)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: pathURL, includingPropertiesForKeys: nil)
            return files.filter { $0.pathExtension == "log"}
        } catch {
            return []
        }
    }
    
    private func createLogFileURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        
        if localLogDirectoryName.count != 0 {
            return paths[0].appendingPathComponent(localLogDirectoryName).appendingPathComponent(localLogFile.createLogFileName(deviceId: clientDeviceID))
        } else {
            return paths[0].appendingPathComponent(localLogFile.createLogFileName(deviceId: clientDeviceID))
        }
    }
    
    @objc private func processStrandedFilesAtStartup() {
        localLogQueue.async {
            for fileURL in self.retrieveLocalLogFileListOnDisk() where fileURL != self.localLogFile.fileURL {
                if self.logToCloud {
                    //self.addFileToCloudPushQueue(localFileURL: fileURL)
                } else {
                    self.deleteLocalFile(fileURL: fileURL)
                }
            }
        }
    }
    
    @objc private func timedAtemptToWriteToDisk() {
        localLogQueue.async {
            _ = self.assesLocalLogability()
            if self.isNowTheRightTimeToWriteLogToLocalFile() {
                self.writeLogFileToDisk()
            }
            self.trimBufferIfNecessary()
        }
    }
    
    private func writeLogFileToDisk(forceFlushToCloud: Bool = false) {
         
        localLogFile.lastFileWriteAttempt = Date()
         
        if localLogFile.fileURL == nil {
            localLogFile.fileURL = createLogFileURL()
            localLogFile.firstFileWrite = Date()
        }
         
        createLocalLogDirectory()
         
        guard let fileURL = localLogFile.fileURL else { return }
        guard let logData = localLogFile.buffer.data(using: .utf8) else { return }
    
        if FileManager.default.fileExists(atPath: fileURL.path) {  // append to the file
            do {
                let fileHandle = try FileHandle(forUpdating: fileURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(logData)
                localLogFile.bytesWritten += localLogFile.buffer.count
                localLogFile.buffer = ""
                localLogFile.lastFileWrite = Date()
                localLogFile.successiveWriteFailures = 0
                 
                if forceFlushToCloud || isNowTheRightTimeToLogLocalFileToCloud() {
//                    do {
//                        if #available(iOS 13.0, *) || #available(macOS 10.15, *) {
//                            try fileHandle.synchronize()
//                            try fileHandle.close()
//                        }
//                    } catch {
//
//                    }
//                    writeLogFileToCloud(logFile: localLogFile)
                    localLogFile = LocalLogFile()
                    localLogFile.lastFileWrite = Date()
//                } else {
//                    if #available(iOS 13.0, *) {
//                        try fileHandle.close()
//                    }
                }
            } catch {
                localLogFile.successiveWriteFailures += 1
            }
        } else { // first write to file
            do {
                try localLogFile.buffer.write(to: fileURL, atomically: true, encoding: .utf8)
                localLogFile.bytesWritten += localLogFile.buffer.count
                localLogFile.buffer = ""
                localLogFile.lastFileWrite = Date()
                localLogFile.successiveWriteFailures = 0
            } catch {
                localLogFile.successiveWriteFailures += 1
            }
        }
    }
     
    private func freeDiskSize() -> Int64? {
        do {
            guard let totalDiskSpaceInBytes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[FileAttributeKey.systemFreeSize] as? Int64 else {
                return nil
            }
            return totalDiskSpaceInBytes
        } catch {
            return nil
        }
    }
     
    private func isFileSystemFreeSpaceSufficient() -> Bool {
        guard let freeDiskSpace = freeDiskSize(), freeDiskSpace > 20 * 1048576 else { return false }
        return true
    }
     
    private func assesLocalLogability() -> Logability {
        guard let freeDiskBytes = freeDiskSize(), freeDiskBytes > Int64(localLogFile.buffer.count) else { localLogability = .unfunctional; return .unfunctional }
        guard isFileSystemFreeSpaceSufficient() else { localLogability = .impaired; return .impaired }
        guard let lastWriteAttempt = localLogFile.lastFileWriteAttempt else { localLogability = .normal; return .normal } // haven't even tried yet.
         
        // if there is a successful write, check the duration between last attemp & last write,
        if let lastWriteSuccess = localLogFile.lastFileWrite {
            //TODO: make these values default but allow override on init.
            if abs(lastWriteSuccess.timeIntervalSince(lastWriteAttempt)) > 600.0 {
                localLogability = .unfunctional
                return localLogability
            }
            if abs(lastWriteSuccess.timeIntervalSince(lastWriteAttempt)) > 180.0 {
                localLogability = .impaired
                return localLogability
            }
            localLogability = .normal
            return localLogability
        }
        // if there has been no successful write, then determine viabiilty by how many retries since last success
        // since the lastWriteAttemp will be recent
        if localLogFile.successiveWriteFailures > 60 {
            localLogability = .unfunctional
            return localLogability
        }
        if localLogFile.successiveWriteFailures > 20 {
            localLogability = .impaired
            return localLogability
        }
        localLogability = .normal
        return localLogability
    }
     
     
    private func isNowTheRightTimeToWriteLogToLocalFile() -> Bool {
         
        if !isFileSystemFreeSpaceSufficient() { return false }
         
        let bufferIsBiggerThanWritableSize = localLogFile.buffer.count > Int(Double(localLogFile.bufferWriteSize) * localFileWriteToPushFactor)
        //let bufferIsBeggerThanMaximumSize = localLogFile.buffer.count > 4 * localLogFile.bufferWriteSize
         
        var acceptableRetryInterval: Double
        switch localLogability {
        case .normal: acceptableRetryInterval = 60.0
        case .impaired: acceptableRetryInterval = 180.0
        case .unfunctional: acceptableRetryInterval = 600.0
        }
         
        var sufficientTimeSinceLastWrite: Bool = true
        if let lastWrite = localLogFile.lastFileWrite {
            sufficientTimeSinceLastWrite = abs(lastWrite.timeIntervalSinceNow) > acceptableRetryInterval
        }
         
        if localLogability == .normal && (bufferIsBiggerThanWritableSize || sufficientTimeSinceLastWrite) { return true }
        if localLogability == .unfunctional && sufficientTimeSinceLastWrite { return true }  // basically retry at very long intervals, if file system comes back
        if localLogability == .impaired && sufficientTimeSinceLastWrite { return true } // retry at longer intervals than normal.
         
        return false
    }
    
    private func isNowTheRightTimeToLogLocalFileToCloud() -> Bool {
        #if targetEnvironment(simulator)
            if !logToCloudOnSimulator { return false }
        #endif
        let localBytesWritten = localLogFile.bytesWritten
        var fileSizeToPush = localLogFile.bufferWriteSize
        #if targetEnvironment(simulator)
            fileSizeToPush = 1024 * 64
        #endif
        
        return localBytesWritten > fileSizeToPush
    }
     
    private func trimBufferIfNecessary() {
        // if the buffer size is 4x the size of when it should write, abandon the log and start over.
        if localLogFile.buffer.count >= localLogFile.bufferWriteSize * 4 {
            localLogFile = LocalLogFile() // reset
            // if you're abandoing the local file because writes are failing, delete local files as well
            // if logging to cloud, it should take care of the deletes.
            if !logToCloud || !logToCloudOnSimulator {
                let fileURLs = retrieveLocalLogFileListOnDisk()
                for fileURL in fileURLs where fileURL != localLogFile.fileURL {
                    deleteLocalFile(fileURL: fileURL)
                }
            }
        }
    }
    
    func log(msg: String) {
        localLogQueue.async {
            self.localLogFile.buffer += "\(msg)\n"
            
            if self.isNowTheRightTimeToWriteLogToLocalFile() {
                self.writeLogFileToDisk()
            }
            self.trimBufferIfNecessary()
        }
    }
}
