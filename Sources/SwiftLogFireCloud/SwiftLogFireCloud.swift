import Foundation
import Logging

/// Client created object used bootstrap the logging system.
public class SwiftLogFileCloudManager {

  /// Description LogHandler factory method type.
  public typealias LogHandlerFactory = (String) -> LogHandler
  public static var swiftLogFireCloud: SwiftLogFireCloud?

  /// Called when bootstrapping the logging system with the SwiftLogFireCloud handler.
  /// - Parameter config: SwiftLogFireCloudConfig object for configuring the logger.
  /// - Returns: returns a function that makes a LogHandler.
  public func makeLogHandlerFactory(config: SwiftLogFireCloudConfig) -> LogHandlerFactory {
    func makeLogHandler(label: String) -> LogHandler {
      SwiftLogFileCloudManager.swiftLogFireCloud = SwiftLogFireCloud(label: label, config: config)
      // SwiftLogFireCloud can't return nil
      // swift-format-ignore: NeverForceUnwrap
      return SwiftLogFileCloudManager.swiftLogFireCloud!
    }
    return makeLogHandler
  }
  
  public init() {
    //apparently a public init is not synthesized even tho its a public class.
  }
  
  public func setLogToCloud(_ enabled: Bool) {
    SwiftLogFileCloudManager.swiftLogFireCloud?.config.logToCloud = enabled
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
  internal var config: SwiftLogFireCloudConfig
  private var localFileLogManager: SwiftLogManager
  private var logMessageDateFormatter = DateFormatter()
  private var logHandlerSerialQueue: DispatchQueue
  private var cloudLogFileManager: CloudLogFileManagerProtocol

  init(
    label: String, config: SwiftLogFireCloudConfig,
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

    localFileLogManager = SwiftLogManager(
      label: label, config: config, cloudLogfileManager: self.cloudLogFileManager)
    logHandlerSerialQueue = DispatchQueue(
      label: "com.google.firebase.swiftlogfirecloud", qos: .background)
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
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    file: String = #file,
    function: String = #function,
    line: UInt = #line
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
