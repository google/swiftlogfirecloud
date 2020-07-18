#if canImport(UIKit)
  import UIKit
#endif

enum LocalLogFileError : Error {
  case distpatchIOErrorNo(Int)
  case emptyFileWriteError
}

/// Class object representing the logging buffer and metadata for writing the buffer to the device local disk.
public class LocalLogFile {
  
  private let queue: DispatchQueue

  public var fileURL: URL
  
  internal var bytesWritten: Int = 0
  
  internal var firstFileWrite: Date?
  
  internal var pendingWriteCount = 0
  internal var pendingWriteWaitCount = 0

  private let config: SwiftLogFireCloudConfig
  /// If the log file buffer grows beyond this size, the log file is abandoned.
  private let bufferSizeToGiveUp: Int
  private let label: String
  lazy var fileHandle: FileHandle? = {
    try? FileHandle(forWritingTo: fileURL)
  }()
  lazy var dispatchIO: DispatchIO? = {
    guard let fileDescriptor = fileHandle?.fileDescriptor else { return nil }
    return DispatchIO(type: .stream, fileDescriptor: fileDescriptor, queue: queue, cleanupHandler: { errorNo in
      print("Error in creating DispatchIO: \(errorNo)")
    })
  }()

  private static let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.timeZone = TimeZone.current
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSSZ'"
    return dateFormatter
  }()

  internal func count() -> Int {
    return Int(truncatingIfNeeded: bytesWritten)
  }
  
  init(label: String, config: SwiftLogFireCloudConfig, queue: DispatchQueue) {
    self.config = config
    self.label = label
    self.bufferSizeToGiveUp = 4 * config.localFileSizeThresholdToPushToCloud
    self.queue = queue
    self.fileURL = LocalLogFile.createLogFileURL(
      localLogDirectoryName: config.logDirectoryName, clientDeviceID: config.uniqueIDString, label: label)
  }
  
  deinit {
    close()
  }

  /// Creates a unique log file name based in deviceID, creation date/time, bundleID & version and logger label.
  /// - Parameter deviceId: Client supplied unique identifer for the log
  /// - Returns: `String` representation of the log file name.
  private static func createLogFileName(deviceId: String?, label: String) -> String {
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
  ///   - label: the SwiiftLog label specified by the client
  /// - Returns: `URL` representation of the log file name.
  internal static func createLogFileURL(localLogDirectoryName: String, clientDeviceID: String?, label: String) -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)

    if localLogDirectoryName.count != 0 {
      return paths[0].appendingPathComponent(localLogDirectoryName).appendingPathComponent(
        LocalLogFile.createLogFileName(deviceId: clientDeviceID, label: label))
    } else {
      return paths[0].appendingPathComponent(LocalLogFile.createLogFileName(deviceId: clientDeviceID, label: label))
    }
  }

  /// Deletes the local file from the filesystem.
  public func delete() {
    // Close the DispatchIO if it hasn't been closed?
    do {
      try FileManager.default.removeItem(at: fileURL)
    } catch {
      //do nothing if it fails, it will get retried on next restart.
    }
  }

  /// If the local file has grown grossly larger than the writable size, abaondon the file & delete its local file if it exists
  /// - Returns: returns self if not trimmed, a new `LocalLogFile` if trimmed.
  internal func trimDiskImageIfNecessary() -> LocalLogFile? {
    // if the buffer size is 4x the size of when it should write, abandon the log and start over.
    if bytesWritten >= bufferSizeToGiveUp {
      delete()
      return nil  // reset
    }
    return self
  }

  /// Retrieves attributs of the log file as it sits on the file system.
  /// - Returns: tuple  of `fileSize` and `creationDate` of the file.
  internal func getLocalLogFileAttributes() -> (fileSize: UInt64?, creationDate: Date?) {
    do {
      let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path) as NSDictionary
      return (attr.fileSize(), attr.fileCreationDate())
    } catch {
    }
    return (nil, nil)
  }

  /// Writes the logfile to the disk.
  /// - Parameter completion: closure called upon successful write
  internal func writeMessage(_ msg: Data, completion: ((Result<Int?, Error>) -> Void)? = nil) {
    
    // DispatchIO.write() appears to require a file to exist before writing to it
    if bytesWritten == 0 {
      do {
        try "".write(to: fileURL, atomically: true, encoding: .utf8)
      } catch {
        completion?(.failure(LocalLogFileError.emptyFileWriteError))
      }
    }
    //TODO: this call style is deprecated, but can't figure out new style to use
    //TODO: is the closure called immediately and sync
    let dispatchData = msg.withUnsafeBytes {
      DispatchData(bytes: UnsafeRawBufferPointer(start: $0, count: msg.count))
    }
    pendingWriteCount += 1
    dispatchIO?.write(offset: 0, data: dispatchData, queue: queue, ioHandler: {[weak self] done, dataRemaining, errorNo in
      
      if done { // done can be true on failure with a nonzero errorNo, but while not successful, its not pending either.
        self?.pendingWriteCount -= 1
      }

      guard errorNo == 0 else {
        completion?(.failure(LocalLogFileError.distpatchIOErrorNo(Int(errorNo))))
        return
      }
      
      self?.firstFileWrite = self?.firstFileWrite == nil ? Date() : self?.firstFileWrite
      self?.bytesWritten += (msg.count - (dataRemaining?.count ?? 0))
      completion?(.success(self?.bytesWritten))
    })
  }
  
  internal func close() {
    dispatchIO?.close()
  }

}
