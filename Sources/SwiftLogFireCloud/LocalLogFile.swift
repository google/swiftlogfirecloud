#if canImport(UIKit)
  import UIKit
#endif

/// Class object representing the logging buffer and metadata for writing the buffer to the device local disk.
internal class LocalLogFile: NSCopying {
  func copy(with zone: NSZone? = nil) -> Any {
    let copy = LocalLogFile(label: label, config: config)
    copy.buffer = buffer
    copy.fileURL = fileURL
    copy.bytesWritten = bytesWritten
    copy.firstFileWrite = firstFileWrite
    copy.lastFileWrite = lastFileWrite
    copy.lastFileWriteAttempt = lastFileWriteAttempt
    copy.successiveWriteFailures = successiveWriteFailures
    copy.localFileWriteToPushFactor = localFileWriteToPushFactor
    return copy
  }

  var fileURL: URL?
  var bytesWritten: UInt64 = 0
  var firstFileWrite: Date?
  var lastFileWrite: Date?
  var lastFileWriteAttempt: Date?
  var successiveWriteFailures: Int = 0

  internal var buffer: Data = Data()
  private let config: SwiftLogFileCloudConfig
  /// If the log file buffer grows beyond this size, the log file is abandoned.
  private let bufferSizeToGiveUp: Int
  private let label: String
  private var localFileWriteToPushFactor = 0.25

  private static let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.timeZone = TimeZone.current
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSSZ'"
    return dateFormatter
  }()

  internal func count() -> Int {
    return buffer.count
  }

  /// Creates a unique log file name based in deviceID, creation date/time, bundleID & version and logger label.
  /// - Parameter deviceId: Client supplied unique identifer for the log
  /// - Returns: `String` representation of the log file name.
  private func createLogFileName(deviceId: String?) -> String {
    var deviceIdForFileName = deviceId
    if deviceId == nil || deviceId?.count == 0 {
      deviceIdForFileName = UIDevice.current.identifierForVendor?.uuidString
    }
    let fileDateString = LocalLogFile.dateFormatter.string(from: Date())
    let bundleString = Bundle.main.bundleIdentifier
    let versionNumber =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
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

    fileString += "-\(label)"
    fileString += ".log"
    print(fileString)
    //TODO this should always be escaped, but better to be safe here
    if let escapedFileString = fileString.addingPercentEncoding(
      withAllowedCharacters: .urlPathAllowed)
    {
      return escapedFileString
    } else {
      return fileString
    }
  }

  /// Creates a fully qualifying file URL for the log file.
  /// - Parameters:
  ///   - localLogDirectoryName: Directory name for storing logs on the local device
  ///   - clientDeviceID: Client supplied unique identifer for the log
  /// - Returns: `URL` representation of the log file name.
  internal func createLogFileURL(localLogDirectoryName: String, clientDeviceID: String?) -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)

    if localLogDirectoryName.count != 0 {
      return paths[0].appendingPathComponent(localLogDirectoryName).appendingPathComponent(
        createLogFileName(deviceId: clientDeviceID))
    } else {
      return paths[0].appendingPathComponent(createLogFileName(deviceId: clientDeviceID))
    }
  }

  init(label: String, config: SwiftLogFileCloudConfig) {
    self.config = config
    self.label = label
    self.bufferSizeToGiveUp = 4 * config.localFileSizeThresholdToPushToCloud
    self.fileURL = createLogFileURL(
      localLogDirectoryName: config.logDirectoryName, clientDeviceID: config.uniqueIDString)
  }

  /// Appends data to the log buffer.
  /// - Parameter data: logging data.
  internal func append(_ data: Data) {
    buffer.append(data)
  }

  /// Deletes the local file from the filesystem.
  internal func delete() {
    guard let url = fileURL else { return }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      //do nothing if it fails, it will get retried on next restart.
    }
  }

  /// Determines if the buffer is bigger than the size to push buffer to the cloud.
  /// - Returns: true if the buffer is larger than the `config.localFileSizeThresholdToPushToCloud`.
  internal func isNowTheRightTimeToLogLocalFileToCloud() -> Bool {
    #if targetEnvironment(simulator)
      if !config.logToCloudOnSimulator { return false }
    #endif
    let fileSizeToPush = config.localFileSizeThresholdToPushToCloud
    //TODO: This is only for testing the library development
    //        #if targetEnvironment(simulator)
    //            fileSizeToPush = 1024 * 64
    //        #endif

    return bytesWritten > fileSizeToPush
  }

  /// If the buffer has grown grossly larger than the writable size, abaondon the buffer & delete its local file if it exists
  /// - Returns: returns self if not trimmed, a new `LocalLogFile` if trimmed.
  internal func trimBufferIfNecessary() -> LocalLogFile {
    // if the buffer size is 4x the size of when it should write, abandon the log and start over.
    if buffer.count >= bufferSizeToGiveUp {
      // if you're abandoing the local file because writes are failing, delete local files as well
      // if logging to cloud, it should take care of the deletes.
      if !config.logToCloud || !config.logToCloudOnSimulator {
        delete()
      }
      return LocalLogFile(label: label, config: config)  // reset
    }
    return self
  }

  /// Determines if the buffer is bigger than the size to push buffer to file system.
  /// 
  /// - Parameter logability: current local logability assesment.
  /// - Returns: return true if the retry interval based on logability has elapsed.
  internal func isNowTheRightTimeToWriteLogToLocalFile(logability: Logability) -> Bool {

    let bufferIsBiggerThanWritableSize =
      buffer.count
      > UInt64(Double(config.localFileSizeThresholdToPushToCloud) * localFileWriteToPushFactor)

    let acceptableRetryInterval: Double
    switch logability {
    case .normal: acceptableRetryInterval = 60.0
    case .impaired: acceptableRetryInterval = 180.0
    case .unfunctional: acceptableRetryInterval = 600.0
    }

    var sufficientTimeSinceLastWrite: Bool = true
    if let lastWrite = lastFileWrite {
      sufficientTimeSinceLastWrite = abs(lastWrite.timeIntervalSinceNow) > acceptableRetryInterval
    }

    if logability == .normal && (bufferIsBiggerThanWritableSize || sufficientTimeSinceLastWrite) {
      return true
    }
    // basically retry at very long intervals, if file system comes back
    if logability == .unfunctional && sufficientTimeSinceLastWrite { return true }
    // retry at longer intervals than normal.
    if logability == .impaired && sufficientTimeSinceLastWrite { return true }

    return false
  }

  /// Retrieves attributs of the log file as it sits on the file system.
  /// - Returns: tuple  of `fileSize` and `creationDate` of the file.
  internal func getLocalLogFileAttributes() -> (fileSize: UInt64?, creationDate: Date?) {
    guard let fileURL = fileURL else { return (nil, nil) }
    do {
      let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path) as NSDictionary
      return (attr.fileSize(), attr.fileCreationDate())
    } catch {
    }
    return (nil, nil)
  }

  /// Writes the logfile to the disk.
  /// - Parameter shouldSychronize: `Bool` to determine if the file should be synchronized to disk in preparation for push to cloud.
  internal func writeLogFileToDisk(shouldSychronize: Bool = false) {

    lastFileWriteAttempt = Date()

    guard let fileURL = fileURL else { return }

    let isFileExistingOnDiskAlready = FileManager.default.fileExists(atPath: fileURL.path)

    switch isFileExistingOnDiskAlready {
    case true:
      appendToExistingLocalLogFile(fileURL: fileURL, closeAndSynchronize: shouldSychronize)
    case false:
      firstWriteOfLocalLogFile(fileURL: fileURL)
    }
  }

  private func appendToExistingLocalLogFile(fileURL: URL, closeAndSynchronize: Bool) {
    do {
      let fileHandle = try FileHandle(forUpdating: fileURL)
      fileHandle.seekToEndOfFile()
      fileHandle.write(buffer)
      bytesWritten += UInt64(buffer.count)
      buffer = Data()
      lastFileWrite = Date()
      successiveWriteFailures = 0

      if closeAndSynchronize {
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
      successiveWriteFailures += 1
    }
  }

  private func firstWriteOfLocalLogFile(fileURL: URL) {
    do {
      try buffer.write(to: fileURL)
      bytesWritten += UInt64(buffer.count)
      buffer = Data()
      lastFileWrite = Date()
      successiveWriteFailures = 0
    } catch {
      successiveWriteFailures += 1
    }
  }
}
