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
  private var cloudDateFormatter: DateFormatter
  private let config: SwiftLogFileCloudConfig
  private let label: String

  private let cloudLogQueue = DispatchQueue(
    label: "com.leisurehoundsports.swiftfirelogcloud-remove", qos: .background)

  init(label: String, config: SwiftLogFileCloudConfig) {
    self.label = label
    self.config = config

    cloudDateFormatter = DateFormatter()
    cloudDateFormatter.timeZone = TimeZone.current
    cloudDateFormatter.dateFormat = "yyyy-MM-dd"
  }

  private func createCloundFilePathAndName(date: Date?) -> String {
    var cloudFilePath = "\(self.config.logDirectoryName)"
    if cloudFilePath.count != 0 { cloudFilePath += "/" }

    var fileDate = Date()
    if let date = date {
      fileDate = date
    }

    let fileDateString = self.cloudDateFormatter.string(from: fileDate)
    cloudFilePath += "\(fileDateString)/"

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
      //            let storageReference = self.storage.reference()
      //            let cloudReference = storageReference.child(cloudFilePath)
      //            let uploadTask = cloudReference.putFile(from: localFileURL, metadata: nil) { metadata, error in
      //                if let error = error {
      // handle the error, not sure how to cascade the error here since client never knows when log to cloud is
      // invoked, as the logging is fire and forget on behalf of the client.  Perhaps add Crashlytics non-fatal
      // error logging for client to monitor incident rates.
      //                }
      //            }
      //            _ = uploadTask.observe(.success) { snapshot in
      //                self.delegate?.deleteLocalFile(fileURL: localFileURL)
      //            }

      //            _ = uploadTask.observe(.failure) { snapshot in
      //                self.addFileToCloudPushQueue(localFileURL: localFileURL)
      //            }
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
