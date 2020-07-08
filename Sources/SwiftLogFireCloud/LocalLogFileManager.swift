#if canImport(UIKit)
  import UIKit
#endif

internal class LocalLogFileManager {

  private var config: SwiftLogFireCloudConfig
  internal var localLogFile: LocalLogFile?

  private let localLogQueue = DispatchQueue(
    label: "com.leisurehoundsports.swiftfirelogcloud-local", qos: .background)
  internal var writeTimer: Timer?
  private var cloudLogfileManager: CloudLogFileManagerProtocol
  private let label: String

  private func startWriteTimer(interval: TimeInterval) -> Timer {
    return Timer.scheduledTimer(
      timeInterval: interval, target: self, selector: #selector(timedAttemptToWriteToDisk),
      userInfo: nil, repeats: true)
  }

  init(
    label: String, config: SwiftLogFireCloudConfig, cloudLogfileManager: CloudLogFileManagerProtocol
  ) {

    self.label = label
    self.config = config
    self.cloudLogfileManager = cloudLogfileManager

    writeTimer = startWriteTimer(interval: config.localFileBufferWriteInterval)

    let notificationCenter = NotificationCenter.default
    notificationCenter.addObserver(
      self, selector: #selector(appWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    notificationCenter.addObserver(
      self, selector: #selector(appWillResumeActive),
      name: UIApplication.willEnterForegroundNotification, object: nil)

    //wait 15s after startup, then attempt to push any files from previous runs up to cloud
    DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
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
  @objc internal func appWillResignActive(_ completionForTesting: (() -> Void)? = nil) {
    localLogQueue.async {  //TODO: make this a background task
      self.writeLocalLogFileToDisk(forceFlushToCloud: true)
      completionForTesting?()
    }
    self.writeTimer?.invalidate()
  }

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
        let logFileOnDisk = LocalLogFile(label: label, config: config)
        logFileOnDisk.fileURL = file
        let attr = logFileOnDisk.getLocalLogFileAttributes()
        if let fileSize = attr.fileSize {
          logFileOnDisk.bytesWritten = fileSize
        }
        logFileOnDisk.firstFileWrite = attr.creationDate
        localLogFilesOnDisk.append(logFileOnDisk)
      }
    } catch {
      return localLogFilesOnDisk
    }
    return localLogFilesOnDisk
  }

  @objc internal func processStrandedFilesAtStartup(_ completionForTesting: (() -> Void)? = nil) {
    localLogQueue.async {
      for localFoundFile in self.retrieveLocalLogFileListOnDisk()
      where localFoundFile.fileURL != self.localLogFile?.fileURL {
        if self.config.logToCloud {
          self.cloudLogfileManager.addFileToCloudPushQueue(localLogFile: localFoundFile)
        } else {
          localFoundFile.delete()
        }
      }
      completionForTesting?()
    }
  }

  @objc private func timedAttemptToWriteToDisk() {
    localLogQueue.async {
      guard let localLogFile = self.localLogFile else { return }
      if localLogFile.isNowTheRightTimeToWriteLogToLocalFile(
        logability: self.assessLogability())
      {
        self.writeLocalLogFileToDisk(forceFlushToCloud: true)
      }
      self.localLogFile = localLogFile.trimBufferIfNecessary()
    }
  }

  internal func assessLogability() -> Logability {
    guard let localLogFile = localLogFile else { return .normal }
    guard let freeDiskBytes = freeDiskSize(), freeDiskBytes > Int64(localLogFile.count())
    else {
      return .unfunctional
    }
    guard isFileSystemFreeSpaceSufficient() else {
      return .impaired
    }
    guard let lastWriteAttempt = localLogFile.lastFileWriteAttempt else {
      // haven't even tried yet.
      return .normal
    }

    // if there is a successful write, check the duration between last attemp & last write,
    if let lastWriteSuccess = localLogFile.lastFileWrite {
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
    if localLogFile.successiveWriteFailures > 10 {
      return .unfunctional
    }
    if localLogFile.successiveWriteFailures > 3 {
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

  internal func isFileSystemFreeSpaceSufficient() -> Bool {
    guard let freeDiskSpace = freeDiskSize(), freeDiskSpace > config.minFileSystemFreeSpace else {
      return false
    }
    return true
  }

  private func writeLocalLogFileToDisk(forceFlushToCloud: Bool = false) {
    guard let localLogFile = localLogFile else { return }
    createLocalLogDirectory()

    let amIFlushingToCloud =
      forceFlushToCloud || cloudLogfileManager.isNowTheRightTimeToWriteToCloud(localLogFile)

    localLogFile.writeLogFileToDisk(shouldSychronize: amIFlushingToCloud)

    if amIFlushingToCloud {
      if let localFileToPush = localLogFile.copy() as? LocalLogFile {
        cloudLogfileManager.writeLogFileToCloud(localLogFile: localFileToPush)
      }
      self.localLogFile = LocalLogFile(label: label, config: config)
      localLogFile.lastFileWrite = Date()
    }
  }
  func log(msg: String) {
    localLogQueue.async {
      guard let msgData = "\(msg)\n".data(using: .utf8) else { return }
      if self.localLogFile == nil {
        self.localLogFile = LocalLogFile(label: self.label, config: self.config)
      }
      self.localLogFile?.append(msgData)

      if self.localLogFile?.isNowTheRightTimeToWriteLogToLocalFile(
        logability: self.assessLogability()) ?? false
      {
        self.writeLocalLogFileToDisk()
      }
      self.localLogFile = self.localLogFile?.trimBufferIfNecessary()
    }
  }
}
