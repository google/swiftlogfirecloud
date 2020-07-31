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

#if canImport(UIKit)
  import UIKit
#endif

/// Manager object that processes log messages and manages the writes to the local logfile and coordinationg of pushing files to the cloud.
internal class SwiftLogManager {

  private var config: SwiftLogFireCloudConfig
  internal var localLogFile: LocalLogFile?

  private let localLogQueue = DispatchQueue(
    label: "com.google.firebase.swiftfirelogcloud-local", qos: .background)
  internal var writeTimer: Timer?
  private var cloudLogfileManager: CloudLogFileManagerProtocol
  internal let label: String

  internal var firstFileWrite: Date?
  internal var lastFileWriteAttempt: Date?
  internal var lastFileWrite: Date?
  internal var successiveWriteFailures: Int = 0
  private let strandedFilesDelay: TimeInterval
  private var impairedMessages: Data?
  private var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
  
  private func startWriteTimer(interval: TimeInterval) -> Timer {
    return Timer.scheduledTimer(
      timeInterval: interval, target: self, selector: #selector(timedAttemptToWriteToCloud),
      userInfo: nil, repeats: true)
  }
  
  /// Creates a SwiftLogManager for the given logger.
  /// - Parameters:
  ///   - label: The label provided by the client app for the logger being managed by this object.
  ///   - config: the `SwiftLogFireCloudConfig` sent by the client app on how the cloud logger should behave.
  ///   - cloudLogfileManager: The object that is repsonsible for managing the coordination of pushing log files to the cloud.
  init(
    label: String, config: SwiftLogFireCloudConfig, cloudLogfileManager: CloudLogFileManagerProtocol
  ) {

    self.label = label
    self.config = config
    self.cloudLogfileManager = cloudLogfileManager
    self.strandedFilesDelay = !config.isTesting ? 15 : 5

    writeTimer = startWriteTimer(interval: config.localFileBufferWriteInterval)

    let notificationCenter = NotificationCenter.default
    notificationCenter.addObserver(
      self, selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    notificationCenter.addObserver(
      self, selector: #selector(appWillResumeActive),
      name: UIApplication.willEnterForegroundNotification, object: nil)

    //wait 15s after startup, then attempt to push any files from previous runs up to cloud
    DispatchQueue.main.asyncAfter(deadline: .now() + strandedFilesDelay) {
      self.processStrandedFilesAtStartup()
    }

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
  @objc internal func appWillResignActive(_ application: UIApplication) { //}, _ completionForTesting: (() -> Void)? = nil) {
    let backgroundEntitlementStatus = UIApplication.shared.backgroundRefreshStatus
    print("BrackgroundEntitlementStatus \(backgroundEntitlementStatus.rawValue)")

      switch backgroundEntitlementStatus {
      case .available:
        self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "com.google.firebase.swiftlogfirecloud.willresignactive") {
          if self.backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
          }
          //completionForTesting?()
        }
        localLogQueue.async {
          self.forceFlushLogToCloud() {
            DispatchQueue.main.async {
              if self.backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
              }
            }
          }
        }
      case .restricted:
        fallthrough
      case .denied:
        fallthrough
      @unknown default:
        localLogQueue.async {
          self.forceFlushLogToCloud() {

          }
        }
      }

    self.writeTimer?.invalidate()
  }
  
  /// Creates the local log file directory for the logger.  If the directory already exists, this is essentially an expensive no-op.
  internal func createLocalLogDirectory() {
    guard config.logDirectoryName.count > 0 else { return }
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)

    let pathURL = paths[0].appendingPathComponent(config.logDirectoryName)
    do {
      try FileManager.default.createDirectory(
        at: pathURL, withIntermediateDirectories: true, attributes: nil)
    } catch {
      config.logDirectoryName = ""
      //TODO:  handle the case of directory creation not successful
    }
  }
  
  /// Queries the local file system for the list of files currently in the local log directory.
  /// - Returns: Array of `LocalLogFile` objects representing the files on disk.
  internal func retrieveLocalLogFileListOnDisk() -> [LocalLogFile] {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)

    let pathURL = paths[0].appendingPathComponent(self.config.logDirectoryName)
    var localLogFilesOnDisk = [LocalLogFile]()
    do {
      let files = try FileManager.default.contentsOfDirectory(
        at: pathURL, includingPropertiesForKeys: nil
      )
      .filter { $0.pathExtension == "log" }
      for file in files {
        let logFileOnDisk = LocalLogFile(label: label, config: config, queue: localLogQueue)
        logFileOnDisk.fileURL = file
        let attr = logFileOnDisk.getLocalLogFileAttributes()
        if let fileSize = attr.fileSize {
          logFileOnDisk.bytesWritten = Int(truncatingIfNeeded: fileSize)
        }
        logFileOnDisk.firstFileWrite = attr.creationDate
        localLogFilesOnDisk.append(logFileOnDisk)
      }
    } catch {
      return localLogFilesOnDisk
    }
    return localLogFilesOnDisk
  }
  
  /// Looks for stranded files on disk from previous client app starts that can be uploaded.  Note it will only attempt to add
  /// files that are not the current log file, not log files from other loggers and are at least older than the start of this instance of the app.
  /// - Parameter completionForTesting: Completion used to report back completion of processing for testing only.  Otherwise its
  ///   a fire and forget prcoess.
  @objc internal func processStrandedFilesAtStartup(_ completionForTesting: (() -> Void)? = nil) {
    localLogQueue.async {
      for localFoundFile in self.retrieveLocalLogFileListOnDisk()
        where (localFoundFile.fileURL != self.localLogFile?.fileURL) {
          let fileAge = abs(localFoundFile.firstFileWrite?.timeIntervalSinceNow ?? 0)
          let containsLabel = localFoundFile.fileURL.absoluteString.contains(self.label)
          if fileAge > self.strandedFilesDelay + 1.0 && containsLabel {
            switch self.config.logToCloud {
            case true: self.cloudLogfileManager.addFileToCloudPushQueue(localLogFile: localFoundFile)
            case false: localFoundFile.delete()
            }
          }
      }
      completionForTesting?()
    }
  }

  @objc private func timedAttemptToWriteToCloud() {
    localLogQueue.async {
      self.queueLocalFileForCloud()
      self.localLogFile = nil
    }
  }
  
  /// Determines the logabilty of the logger, based on delta between write attemps, successful writes and successive write failures.
  /// - Returns: `Logabilty` of the local file system, `.normal`` when operable and `.impaired` or `.unfunctional` when not.
  internal func assessLocalLogability() -> Logability {
    guard let localLogFile = localLogFile else { return .normal }
    guard let freeDiskBytes = freeDiskSize(), freeDiskBytes > Int64(localLogFile.count())
    else {
      return .unfunctional
    }
    guard isFileSystemFreeSpaceSufficient() else {
      return .impaired
    }
    guard let lastWriteAttempt = lastFileWriteAttempt else {
      // haven't even tried yet.
      return .normal
    }

    // if there is a successful write, check the duration between last attemp & last write,
    if let lastWriteSuccess = lastFileWrite {
      if abs(lastWriteSuccess.timeIntervalSince(lastWriteAttempt))
        > config.localFileBufferWriteInterval * 10
      {
        return .unfunctional
      }
      if abs(lastWriteSuccess.timeIntervalSince(lastWriteAttempt))
        > config.localFileBufferWriteInterval * 3
      {
        return .impaired
      }
      return .normal
    }
    // if there has been no successful write, then determine viabiilty by how many retries since last success
    // since the lastWriteAttemp will be recent
    if successiveWriteFailures > 100 {
      return .unfunctional
    }
    if successiveWriteFailures > 12 {
      return .impaired
    }
    return .normal
  }

  private func freeDiskSize() -> Int64? {
    do {
      guard
        let totalDiskSpaceInBytes = try FileManager.default.attributesOfFileSystem(
          forPath: NSHomeDirectory())[FileAttributeKey.systemFreeSize] as? Int64
      else {
        return nil
      }
      return totalDiskSpaceInBytes
    } catch {
      return nil
    }
  }
  
  /// Compares the physical local file system free disk size compared to the config set for minimum file space required to log.
  /// - Returns: boolean which is true if the local file system is of sufficient size and free space.
  internal func isFileSystemFreeSpaceSufficient() -> Bool {
    guard let freeDiskSpace = freeDiskSize(), freeDiskSpace > config.minFileSystemFreeSpace else {
      return false
    }
    return true
  }
  
  /// Adds the current file for processing to the cloud.
  internal func queueLocalFileForCloud(completion: (()->Void)? = nil) {
    guard let localLogFile = self.localLogFile else { return }
    cloudLogfileManager.writeLogFileToCloud(localLogFile: localLogFile, completion: completion)
  }
  
  /// Attemps to retry writing previously failed log messages to the local file system.
  internal func retryWritingImpairedMessages() {
    guard let messages = impairedMessages else { return }
    
    localLogFile?.writeMessage(messages) { result in
      switch result {
      case .success(_):
        self.successiveWriteFailures = 0
        self.impairedMessages = nil
      case .failure(_):
        self.successiveWriteFailures += 1
      }
    }
  }
  
  /// Adds a log message to the list of messages logged but not successfully written to the log file.
  /// - Parameter msg: message to be logged.
  internal func addMessageToImpaired(_ msg: Data) {
    if impairedMessages == nil {
      impairedMessages = Data()
    }
    impairedMessages?.append(msg)
  }
  
  internal func forceFlushLogToCloud(completion: (() -> Void)? = nil) {
    queueLocalFileForCloud(completion: completion)
    localLogFile = nil
  }
  
  /// Logs the message from the handler.
  /// - Parameter msg: message to be logged.
  internal func log(msg: String) {
    localLogQueue.async {
      guard let msgData = "\(msg)\n".data(using: .utf8) else { return }
      
      if let localLogFile = self.localLogFile, self.cloudLogfileManager.isNowTheRightTimeToWriteToCloud(localLogFile) {
        self.queueLocalFileForCloud()
        self.localLogFile = nil
      }
      
      if self.localLogFile == nil {
        self.localLogFile = LocalLogFile(label: self.label, config: self.config, queue: self.localLogQueue)
      }
      let logability = self.assessLocalLogability()
      
      self.lastFileWriteAttempt = Date()

      guard let localLogFile = self.localLogFile else { return }
      switch logability {
      case .normal:
        // create directory in case something else removed it.
        self.createLocalLogDirectory()
        localLogFile.writeMessage(msgData) { result in
          switch result {
          case .failure(_) :
            self.successiveWriteFailures += 1
            self.addMessageToImpaired(msgData)
          case .success(_):
            break
          }
        }
      case .impaired:
        self.addMessageToImpaired(msgData)
        if self.successiveWriteFailures % 30 == 0 {
          self.retryWritingImpairedMessages()
        }
      case .unfunctional:
        self.addMessageToImpaired(msgData)
        if self.successiveWriteFailures % 300 == 0 {
          self.retryWritingImpairedMessages()
        }
      }
      self.localLogFile = self.localLogFile?.trimDiskImageIfNecessary()
    }
  }
}
