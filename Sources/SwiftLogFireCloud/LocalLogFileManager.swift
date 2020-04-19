#if canImport(UIKit)
import UIKit
#endif

internal class LocalLogFileManager {
    
    private var config: SwiftLogFileCloudConfig
    internal var localLogFile: LocalLogFile

    private var logToCloudOnSimulator = true // set only when testing the library only.
    private let localLogQueue = DispatchQueue(label: "com.leisurehoundsports.swiftfirelogcloud-local", qos: .background)
    private var localLogability: Logability = .normal
    internal var writeTimer: Timer?
    private var localFileWriteToPushFactor = 0.25
    private var cloudLogfileManager: CloudLogFileManagerProtocol
    
    internal enum Logability {
        case normal
        case impaired
        case unfunctional
    }
    
    private func startWriteTimer(interval: TimeInterval) -> Timer {
        return Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(timedAttemptToWriteToDisk), userInfo: nil, repeats: true)
    }
    
    init(config: SwiftLogFileCloudConfig, cloudLogfileManager: CloudLogFileManagerProtocol) {
        
        self.config = config
        self.cloudLogfileManager = cloudLogfileManager

        self.localLogFile = LocalLogFile(config: config) // TODO: Defer this until the first log message, which may be well after startup
        
        writeTimer = startWriteTimer(interval: config.localFileBufferWriteInterval)
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appWillResumeActive), name: UIApplication.willEnterForegroundNotification, object: nil)
        
        //wait 15s after startup, then attempt to push any files from previous runs up to cloud
        _ = Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(processStrandedFilesAtStartup), userInfo: nil, repeats: false)
        
        #if targetEnvironment(simulator)
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        print("Log File location: \(paths[0].appendingPathComponent(config.logDirectoryName))")
        #endif
    }
    
    @objc internal func appWillResumeActive() {
        if !(writeTimer?.isValid ?? false) {
           writeTimer = startWriteTimer(interval: config.localFileBufferWriteInterval)
        }
    }
    @objc internal func appWillResignActive(_ completionForTesting: (()->Void)? = nil) {
        localLogQueue.async {  //TODO: make this a background task
            self.writeLogFileToDisk(forceFlushToCloud: true)
            completionForTesting?()
        }
        self.writeTimer?.invalidate()
    }
    
    internal func createLocalLogDirectory() {
        guard config.logDirectoryName.count > 0 else { return }
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        
        let pathURL =  paths[0].appendingPathComponent(config.logDirectoryName)
        do {
            try FileManager.default.createDirectory(at: pathURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            config.logDirectoryName = ""
            //TODO:  handle the case of directory creation not successful
        }
    }
    
    internal func deleteLocalFile(_ fileURL: URL) {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            //do nothing if it fails, it will get retried on next restart.
        }
    }
    
    internal func retrieveLocalLogFileListOnDisk() -> [URL] {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)

        let pathURL =  paths[0].appendingPathComponent(self.config.logDirectoryName)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: pathURL, includingPropertiesForKeys: nil)
            return files.filter { $0.pathExtension == "log"}
        } catch {
            return []
        }
    }
    
    @objc internal func processStrandedFilesAtStartup(_ completionForTesting: (()->Void)? = nil) {
        localLogQueue.async {
            for fileURL in self.retrieveLocalLogFileListOnDisk() where fileURL != self.localLogFile.fileURL {
                if self.config.logToCloud {
                    self.cloudLogfileManager.addFileToCloudPushQueue(localFileURL: fileURL)
                } else {
                    self.deleteLocalFile(fileURL)
                }
            }
            completionForTesting?()
        }
    }
    
    @objc private func timedAttemptToWriteToDisk() {
        localLogQueue.async {
            _ = self.assessLocalLogability()
            if self.isNowTheRightTimeToWriteLogToLocalFile() {
                self.writeLogFileToDisk()
            }
            self.trimBufferIfNecessary()
        }
    }
    
    internal func appendToExistingLocalLogFile(fileURL: URL, closeAndSynchronize: Bool) {
        do {
            let fileHandle = try FileHandle(forUpdating: fileURL)
            fileHandle.seekToEndOfFile()
            fileHandle.write(localLogFile.buffer)
            localLogFile.bytesWritten += localLogFile.buffer.count
            localLogFile.buffer = Data()
            localLogFile.lastFileWrite = Date()
            localLogFile.successiveWriteFailures = 0
            
            if closeAndSynchronize  {
                do {
                    if #available(iOS 13.0, *) {
                        try fileHandle.synchronize()
                        try fileHandle.close()
                    }
                } catch {
                    // cest la vie
                }
            }
        } catch {
            localLogFile.successiveWriteFailures += 1
        }
    }
    
    internal func firstWriteOfLocalLogFile(fileURL: URL) {
        do {
            try localLogFile.buffer.write(to: fileURL)
            localLogFile.bytesWritten += localLogFile.buffer.count
            localLogFile.buffer = Data()
            localLogFile.lastFileWrite = Date()
            localLogFile.successiveWriteFailures = 0
        } catch {
            localLogFile.successiveWriteFailures += 1
        }
    }
    
    private func writeLogFileToDisk(forceFlushToCloud: Bool = false) {
         
        localLogFile.lastFileWriteAttempt = Date()
         
        createLocalLogDirectory()
         
        guard let fileURL = localLogFile.fileURL else { return }
        
        let isFileExistingOnDiskAlready = FileManager.default.fileExists(atPath: fileURL.path)
        let amIFlushingToCloud = forceFlushToCloud || isNowTheRightTimeToLogLocalFileToCloud()
        
        switch isFileExistingOnDiskAlready {
        case true:
            appendToExistingLocalLogFile(fileURL: fileURL, closeAndSynchronize: amIFlushingToCloud )
        case false:
            firstWriteOfLocalLogFile(fileURL: fileURL)
        }
        
        if amIFlushingToCloud {
            cloudLogfileManager.writeLogFileToCloud(localFileURL: fileURL)
            localLogFile = LocalLogFile(config: config)  // this is a struct, so async write to cloud is working with a copy, ok to update here
            localLogFile.lastFileWrite = Date()
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
     
    internal func isFileSystemFreeSpaceSufficient() -> Bool {
        guard let freeDiskSpace = freeDiskSize(), freeDiskSpace > config.minFileSystemFreeSpace else { return false }
        return true
    }
     
    internal func assessLocalLogability() -> Logability {
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
         
        let bufferIsBiggerThanWritableSize = localLogFile.buffer.count > Int(Double(config.localFileBufferSize) * localFileWriteToPushFactor)
        //let bufferIsBeggerThanMaximumSize = localLogFile.buffer.count > 4 * localLogFile.bufferWriteSize
         
        let acceptableRetryInterval: Double
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
        var fileSizeToPush = config.localFileBufferSize
        //TODO: This is only for testing the library development
        #if targetEnvironment(simulator)
            fileSizeToPush = 1024 * 64
        #endif
        
        return localBytesWritten > fileSizeToPush
    }
     
    internal func trimBufferIfNecessary() {
        // if the buffer size is 4x the size of when it should write, abandon the log and start over.
        if localLogFile.buffer.count >= localLogFile.bufferSizeToGiveUp {
            localLogFile = LocalLogFile(config: config) // reset
            // if you're abandoing the local file because writes are failing, delete local files as well
            // if logging to cloud, it should take care of the deletes.
            if !config.logToCloud || !logToCloudOnSimulator {
                let fileURLs = retrieveLocalLogFileListOnDisk()
                for fileURL in fileURLs where fileURL != localLogFile.fileURL {
                    deleteLocalFile(fileURL)
                }
            }
        }
    }
    
    func log(msg: String) {
        localLogQueue.async {
            guard let msgData = "\(msg)\n".data(using: .utf8) else { return }
            self.localLogFile.buffer.append(msgData)
            
            if self.isNowTheRightTimeToWriteLogToLocalFile() {
                self.writeLogFileToDisk()
            }
            self.trimBufferIfNecessary()
        }
    }
}
