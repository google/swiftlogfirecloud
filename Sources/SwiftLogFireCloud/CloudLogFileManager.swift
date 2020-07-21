#if canImport(UIKit)
  import UIKit
#endif

/// Manages the uploading of log files to the cloud on a background queue.
///
/// Upon successful push of the file to the cloud, the local file is deleted.  If the upload fails,
/// the file is not deleted and pushed to a processing queue to be pushed at a later time.
class CloudLogFileManager: CloudLogFileManagerProtocol, CloudLogFileManagerClientProtocol {

  private var logability: Logability = .normal
  private var lastWriteAttempt: Date?
  private var lastWriteSuccess: Date?
  private var successiveFails: Int = 0
  private var strandedFilesToPush: [LocalLogFile]?
  private var strandedFileTimer: Timer?
  private var cloudDirectoryNameDateFormatter: DateFormatter
  private var cloudFileNameDateFormatter: DateFormatter
  private let config: SwiftLogFireCloudConfig
  private let label: String
  private let isTesting: Bool

  private let cloudLogQueue = DispatchQueue(
    label: "com.google.firebase.swiftfirelogcloud-cloud", qos: .background)

  init(label: String, config: SwiftLogFireCloudConfig) {
    self.label = label
    self.config = config

    cloudDirectoryNameDateFormatter = DateFormatter()
    cloudDirectoryNameDateFormatter.timeZone = TimeZone.current
    cloudDirectoryNameDateFormatter.dateFormat = "yyyy-MM-dd"

    cloudFileNameDateFormatter = DateFormatter()
    cloudFileNameDateFormatter.timeZone = TimeZone.current
    cloudFileNameDateFormatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSSZ'"
    
    isTesting = ProcessInfo.processInfo.environment["isTesting"] == "true"
  }

  private func createCloundFilePathAndName(date: Date?) -> String {
    var cloudFilePath = "\(self.config.logDirectoryName)"
    if cloudFilePath.count != 0 { cloudFilePath += "/" }

    var fileDate = Date()
    if let date = date {
      fileDate = date
    }

    let directoryDateString = self.cloudDirectoryNameDateFormatter.string(from: fileDate)
    cloudFilePath += "\(directoryDateString)/"

    if let bundleString = Bundle.main.bundleIdentifier {
      cloudFilePath += "\(bundleString)/"
    }

    if let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String,
      let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    {
      cloudFilePath += "v\(versionNumber)b\(buildNumber)/"
    }

    if let deviceIDForFilename = config.uniqueIDString, deviceIDForFilename.count != 0 {
      cloudFilePath += "\(deviceIDForFilename)/"
    } else {
      if let deviceID = UIDevice.current.identifierForVendor?.uuidString {
        cloudFilePath += "\(deviceID)/"
      }
    }
    cloudFilePath += "\(label)/"

    let fileDateString = self.cloudFileNameDateFormatter.string(from: fileDate)
    cloudFilePath += "\(fileDateString).log"
    return cloudFilePath
  }

  /// Determines if the buffer is bigger than the size to push buffer to the cloud.
  /// - Returns: true if the buffer is larger than the `config.localFileSizeThresholdToPushToCloud`.
  internal func isNowTheRightTimeToWriteToCloud(_ localLogFile: LocalLogFile) -> Bool {
    #if targetEnvironment(simulator)
      if !config.logToCloudOnSimulator { return false }
    #endif
    let fileSizeToPush = config.localFileSizeThresholdToPushToCloud

    var acceptableRetryInterval: Double
    let logability = assessLogability()
    switch logability {
    case .normal: acceptableRetryInterval = config.localFileBufferWriteInterval
    case .unfunctional: acceptableRetryInterval = config.localFileBufferWriteInterval * 10
    case .impaired: acceptableRetryInterval = config.localFileBufferWriteInterval * 3
    }

    var sufficientTimeSinceLastWrite: Bool = false
    if let lastWrite = lastWriteAttempt {
      sufficientTimeSinceLastWrite = abs(lastWrite.timeIntervalSinceNow) > acceptableRetryInterval
    }

    switch logability {
    case .normal: return localLogFile.bytesWritten > fileSizeToPush || sufficientTimeSinceLastWrite
    case .impaired, .unfunctional: return sufficientTimeSinceLastWrite
    }
  }

  /// Pushes a  local log file to the cloud configured by the client app.
  /// - Parameter localLogFile: Reference to LocalLogFile reference with meta data about the local file on disk.
  internal func writeLogFileToCloud(localLogFile: LocalLogFile) {
    cloudLogQueue.async {
      //TODO:  this probably should be rate limited since Firebase ratelimits
      
      if localLogFile.pendingWriteCount != 0 && localLogFile.pendingWriteWaitCount < 5 {
        localLogFile.pendingWriteWaitCount += 1
        self.cloudLogQueue.asyncAfter(deadline: .now() + 5.0) {
          self.writeLogFileToCloud(localLogFile: localLogFile)
        }
        return
      }
      
      localLogFile.close()
      
      // since the tests use the real file system, there is an apparently delay between writing
      // to a file and when the file attributes are updated, resulting in this getting
      // short circuited in testing as the fileSize is always zero. While I care about not uploading
      // zero byte files in production, this check is not necessary for tests.
      let fileAttr = localLogFile.getLocalLogFileAttributes()
      if let fileSize = fileAttr.fileSize, !self.config.isTesting && fileSize == 0  {
        localLogFile.delete()
        return
      }
      let cloudFilePath = self.createCloundFilePathAndName(date: fileAttr.creationDate)
      self.config.cloudUploader?.uploadFile(self, from: localLogFile, to: cloudFilePath)
      self.lastWriteAttempt = Date()
    }
  }

  /// Adds a LocalLogFile reference to the background cloud push queue.
  /// - Parameter localLogFile: Reference to LocalLogFile reference with meta data about the local file on disk.
  internal func addFileToCloudPushQueue(localLogFile: LocalLogFile) {
    if strandedFilesToPush == nil {
      strandedFilesToPush = [LocalLogFile]()
    }
    if let fileCount = strandedFilesToPush?.count, fileCount <= 20 {
      strandedFilesToPush?.append(localLogFile)
    } else {
      localLogFile.delete()
    }
    if strandedFilesToPush?.count == 1 {
      DispatchQueue.main.async {
        self.strandedFileTimer = Timer.scheduledTimer(
          timeInterval: (!self.config.isTesting ? 25 : 1), target: self, selector: #selector(self.processCloudPushQueue),
          userInfo: nil, repeats: true)
      }
    }
  }

  @objc private func processCloudPushQueue() {
    cloudLogQueue.async {

      defer {
        if self.strandedFilesToPush?.count == 0 {
          if self.strandedFileTimer?.isValid ?? false {
            self.strandedFileTimer?.invalidate()
          }
        }
      }

      guard let fileCount = self.strandedFilesToPush?.count, fileCount > 0 else { return }
      if let localLogFile = self.strandedFilesToPush?.first {
        self.writeLogFileToCloud(localLogFile: localLogFile)
        self.strandedFilesToPush?.removeFirst()
      }
    }
  }

  public func reportUploadStatus(_ result: Result<LocalLogFile, CloudUploadError>) {
    switch result {
    case .success(let logFile):
      successiveFails = 0
      lastWriteSuccess = Date()
      logFile.delete()
    case .failure(let error):
      successiveFails += 1
      switch error {
      case .failedToUpload(let logFile):
        addFileToCloudPushQueue(localLogFile: logFile)
      }
      
    }
  }

  internal func assessLogability() -> Logability {
    if let lastWriteSuccess = lastWriteSuccess,
      let lastWriteAttempt = lastWriteAttempt
    {
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
    // since the lastWriteAttemp
    if successiveFails > 10 {
      return .unfunctional
    }
    if successiveFails > 3 {
      return .impaired
    }
    return .normal
  }

}
