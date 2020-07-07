import Foundation
import Logging

/// Configuration struct to configure the local and cloud logging logic.
///
/// Set values to instruct the Log Handler to manage how often to
/// write logs to disk and the cloud, when to control the persistance
/// logging itself, cloud and local directory name and the minimum
/// local file system space for temporarily holding the logs.
public struct SwiftLogFileCloudConfig {

  /// Enable to ensure log files are persisted to Firebase Cloud Storage bucket.
  var logToCloud: Bool = false

  /// The approximate log size when logs will be persisted to Firebase Cloud Storage bucket.
  ///
  /// log files are pushed to the cloud once they eclipse this size or if the `localFileBufferWriteInterval`
  /// has elapsed
  var localFileSizeThresholdToPushToCloud: Int = megabyte

  /// TimeInterval between when logs will be check for persistence  to Firebase Cloud Storage bucket.
  ///
  /// log files are check to be pushed to the cloud on this interval or once they eclipse a size of `localFileSizeThresholdToPushToCloud`
  var localFileBufferWriteInterval: TimeInterval = 60.0

  /// An optional uniqueID string to identify the log file that is embedded in the log file name.
  ///
  /// If omitted, the library will utlize the `UIDevice.current.identifierForVendor`  to uniquely identify the logfile
  let uniqueIDString: String?

  /// Minimum required local file system space to start or continue logging.
  var minFileSystemFreeSpace: Int = 20 * megabyte

  /// Directory name used for storing logs, both locally and as the root directy in the cloud storage bucket.
  var logDirectoryName: String = "Logs"

  /// Boolean value to control whether log files are sent to the cloud when running within a simulator.
  var logToCloudOnSimulator: Bool = false

  /// Object responsible for uploading the local log file to the cloud.
  ///
  /// Ideally the library could do this but I don't want the library to depend on firebase,
  /// rather want to receive it from the client of the library.  But I'm not able to compile against
  /// those symbols without also linking against the Firestore library which would create
  /// duplicate symbol issues for theclient app.
  weak var cloudUploader: CloudFileUploaderProtocol?

  internal static let megabyte: Int = 1_048_576

  /// Create a new `SwiftLogFileCloudConfig`.
  ///
  /// - Parameters:
  ///   - logToCloud: Enable to ensure log files are persisted to Firebase Cloud Storage bucket.
  ///   - localFileSizeThresholdToPushToCloud: The approximate log size when logs will be persisted to Firebase Cloud Storage bucket.
  ///   - localFileBufferWriteInterval: TimeInterval between when logs will be check for persistence  to Firebase Cloud Storage bucket.
  ///   - uniqueID: An optional uniqueID string to identify the log file that is embedded in the log file name.
  ///   - minFileSystemFreeSpace: Minimum required local file system space to start or continue logging.
  ///   - logDirectoryName: Directory name used for storing logs, both locally and as the root directy in the cloud storage bucket.
  ///   - logToCloudOnSimulator: Boolean value to control whether log files are sent to the cloud when running within a simulator.
  public init(
    logToCloud: Bool? = nil, localFileSizeThresholdToPushToCloud: Int? = nil,
    localFileBufferWriteInterval: TimeInterval? = nil, uniqueID: String? = nil,
    minFileSystemFreeSpace: Int? = nil, logDirectoryName: String? = nil,
    logToCloudOnSimulator: Bool? = false, cloudUploader: CloudFileUploaderProtocol?
  ) {
    if let logToCloud = logToCloud {
      self.logToCloud = logToCloud
    }
    if let localFileSizeThresholdToPushToCloud = localFileSizeThresholdToPushToCloud {
      self.localFileSizeThresholdToPushToCloud = localFileSizeThresholdToPushToCloud
    }
    if let localFileBufferWriteInterval = localFileBufferWriteInterval {
      self.localFileBufferWriteInterval = localFileBufferWriteInterval
    }
    if let minFileSystemFreeSpace = minFileSystemFreeSpace {
      self.minFileSystemFreeSpace = minFileSystemFreeSpace
    }
    if let logDirectoryName = logDirectoryName {
      self.logDirectoryName = logDirectoryName
    }
    if let logToCloudOnSimulator = logToCloudOnSimulator {
      self.logToCloudOnSimulator = logToCloudOnSimulator
    }
    self.uniqueIDString = uniqueID
    self.cloudUploader = cloudUploader
  }
}

/// Client created object used bootstrap the logging system.
public class SwiftLogFileCloudManager {

  /// Description LogHandler factory method type.
  public typealias LogHandlerFactory = (String) -> LogHandler
  public static var swiftLogFireCloud: SwiftLogFireCloud?

  /// Called when bootstrapping the logging system with the SwiftLogFireCloud handler.
  /// - Parameter config: SwiftLogFireCloudConfig object for configuring the logger.
  /// - Returns: returns a function that makes a LogHandler.
  public func makeLogHandlerFactory(config: SwiftLogFileCloudConfig) -> LogHandlerFactory {
    func makeLogHandler(label: String) -> LogHandler {
      SwiftLogFileCloudManager.swiftLogFireCloud = SwiftLogFireCloud(label: label, config: config)
      // SwiftLogFireCloud can't return nil
      // swift-format-ignore: NeverForceUnwrap
      return SwiftLogFileCloudManager.swiftLogFireCloud!
    }
    return makeLogHandler
  }

  public init() {

  }
}

internal enum Logability {
  case normal
  case impaired
  case unfunctional
}

/// SwiftLog handler coordinating the management of the local and cloud logs.
public class SwiftLogFireCloud: LogHandler {

  private var label: String
  private var config: SwiftLogFileCloudConfig
  private var localFileLogManager: LocalLogFileManager
  private var logMessageDateFormatter = DateFormatter()
  private var logHandlerSerialQueue: DispatchQueue
  private var cloudLogFileManager: CloudLogFileManagerProtocol

  init(
    label: String, config: SwiftLogFileCloudConfig,
    cloudLogfileManager: CloudLogFileManagerProtocol? = nil
  ) {
    self.label = label
    self.config = config
    logMessageDateFormatter.timeZone = TimeZone.current
    logMessageDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    logMessageDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
    logMessageDateFormatter.calendar = Calendar(identifier: .gregorian)

    // swift-format-ignore: NeverForceUnwrap
    self.cloudLogFileManager =
      cloudLogfileManager == nil
      ? CloudLogFileManager(label: label, config: config) : cloudLogfileManager!

    localFileLogManager = LocalLogFileManager(
      label: label, config: config, cloudLogfileManager: self.cloudLogFileManager)
    logHandlerSerialQueue = DispatchQueue(
      label: "com.leisurehoundsports.swiftlogfirecloud", qos: .background)
  }

  #if DEBUG
    private static let isRunningUnderDebugger: Bool = {
      // https://stackoverflow.com/questions/33177182/detect-if-swift-app-is-being-run-from-xcode
      // according to this post, this is essentially lazy and dispatched once.
      // https://medium.com/@jmig/dispatch-once-in-swift-a-24-hours-journey-e18e370eac05
      var info = kinfo_proc()
      var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
      var size = MemoryLayout<kinfo_proc>.stride
      let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
      assert(junk == 0, "sysctl failed")
      return (info.kp_proc.p_flag & P_TRACED) != 0
    }()
  #endif

  public func log(
    level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String,
    function: String, line: UInt
  ) {
    logHandlerSerialQueue.async {

      //TODO: test that the metadata information is written to the log.
      var metadataString: String = ""
      let dateString = self.logMessageDateFormatter.string(from: Date())
      if let metadata = metadata {
        metadataString =
          !metadata.isEmpty ? metadata.map { "\($0)=\($1)" }.joined(separator: " ") : ""
      }
      let logmsg = "\(dateString) \(metadataString) \(level): \(message.description)"

      if self.config.logToCloud == true {
        self.localFileLogManager.log(msg: logmsg)
      }

      var printToConsole = false
      #if DEBUG
        printToConsole = SwiftLogFireCloud.isRunningUnderDebugger
      #endif
      #if targetEnvironment(simulator)
        printToConsole = true
      #endif
      if printToConsole {
        print("\(logmsg)")
      }
    }
  }

  public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get {
      return metadata[key]
    }
    set(newValue) {
      metadata[key] = newValue
    }
  }

  public var metadata: Logger.Metadata = .init()

  public var logLevel: Logger.Level = .info

}
