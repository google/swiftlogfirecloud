#if canImport(UIKit)
  import UIKit
#endif

/// Manages the uploading of log files to the cloud on a background queue.
///
/// Upon successful push of the file to the cloud, the local file is deleted.  If the upload fails,
/// the file is not deleted and pushed to a processing queue to be pushed at a later time.
class CloudLogFileManager: CloudLogFileManagerProtocol {

  private var logability: Logability = .normal
  private var lastWriteAttempt: Date?
  private var lastWriteSuccess: Date?
  private var successiveFails: Int = 0
  private var strandedFilesToPush: [LocalLogFile]?
  private var strandedFileTimer: Timer?
  private var cloudDirectoryNameDateFormatter: DateFormatter
  private var cloudFileNameDateFormatter: DateFormatter
  private let config: SwiftLogFileCloudConfig
  private let label: String

  private let cloudLogQueue = DispatchQueue(
    label: "com.leisurehoundsports.swiftfirelogcloud-remove", qos: .background)

  init(label: String, config: SwiftLogFileCloudConfig) {
    self.label = label
    self.config = config

    cloudDirectoryNameDateFormatter = DateFormatter()
    cloudDirectoryNameDateFormatter.timeZone = TimeZone.current
    cloudDirectoryNameDateFormatter.dateFormat = "yyyy-MM-dd"

    cloudFileNameDateFormatter = DateFormatter()
    cloudFileNameDateFormatter.timeZone = TimeZone.current
    cloudFileNameDateFormatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSSZ'"
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

  /// Pushes a  local log file to the cloud configured by the client app.
  /// - Parameter localLogFile: Reference to LocalLogFile reference with meta data about the local file on disk.
  func writeLogFileToCloud(localLogFile: LocalLogFile) {
    cloudLogQueue.async {

      let fileAttr = localLogFile.getLocalLogFileAttributes()
      guard let fileSize = fileAttr.fileSize, fileSize > 0 else {
        localLogFile.delete()
        return
      }
      //TODO: use the same file name as local here...
      let cloudFilePath = self.createCloundFilePathAndName(date: fileAttr.creationDate)
      self.config.cloudUploader?.uploadFile(self, from: localLogFile, to: cloudFilePath)
    }
  }

  /// Adds a LocalLogFile reference to the background cloud push queue.
  /// - Parameter localLogFile: Reference to LocalLogFile reference with meta data about the local file on disk.
  func addFileToCloudPushQueue(localLogFile: LocalLogFile) {
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
          timeInterval: 25, target: self, selector: #selector(self.processCloudPushQueue),
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

}
