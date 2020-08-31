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

import Foundation
import Logging

/// Client created object used bootstrap the logging system.
public class SwiftLogFileCloudManager {

  /// Description LogHandler factory method type.
  public typealias LogHandlerFactory = (String) -> LogHandler
  internal var logHandlers = [String:SwiftLogFireCloud]()
  private var allLoggersLogToCloud = false
  //internal static var swiftLogFireCloud: SwiftLogFireCloud?

  /// Called when bootstrapping the logging system with the SwiftLogFireCloud handler.
  /// - Parameter config: SwiftLogFireCloudConfig object for configuring the logger.
  /// - Returns: returns a function that makes a LogHandler.
  public func makeLogHandlerFactory(config: SwiftLogFireCloudConfig) -> LogHandlerFactory {
    allLoggersLogToCloud = config.logToCloud
    func makeLogHandler(label: String) -> LogHandler {
      logHandlers[label] = SwiftLogFireCloud(label: label, config: config)
      // SwiftLogFireCloud can't return nil
      // swift-format-ignore: NeverForceUnwrap
      return logHandlers[label]!
    }
    return makeLogHandler
  }
  
  public init() {
    //apparently a public init is not synthesized even tho its a public class.
  }
  
  /// Allows client apps to control when to log to cloud programatically after the logger is created (to turn it off, for example).
  /// When the parameter is changed from true to false, the log files generated thus far are queed for push to the cloud.
  /// - Parameter enabled: boolean when true turns cloud logging on, when false turns it off.
  public func setLogToCloud(_ enabled: Bool) {
    allLoggersLogToCloud = enabled
    for (_, handler) in logHandlers {
      handler.config.logToCloud = allLoggersLogToCloud
    }
  }
  
  /// Query the Cloud Loggers current setting of logging to cloud.
  /// - Returns: `true` when the logger is set to log to cloud, false otherise.
  public func getLogToCloud() -> Bool {
    return allLoggersLogToCloud
  }
  
  /// Immediately flush all logger's local files to the cloud.
  /// Note: the logger already response to AppWillResignActive notification and automatically request the flush files to
  /// the cloud, and will do so on a background task if the client app has entitlements for background refresh.
  public func flushLoggersToCloud() {
    for (_, handler) in logHandlers {
      handler.localFileLogManager.forceFlushLogToCloud()
    }
  }
}

/// Enum for the status of logability, used by both local file logging and cloud logging capability.
internal enum Logability {
  case normal
  case impaired
  case unfunctional
}

/// SwiftLog handler coordinating the management of the local and cloud logs.
internal class SwiftLogFireCloud: LogHandler {

  private var label: String
  internal var config: SwiftLogFireCloudConfig
  internal var localFileLogManager: SwiftLogManager
  private var logMessageDateFormatter = DateFormatter()
  private var logHandlerSerialQueue: DispatchQueue
  private var cloudLogFileManager: CloudLogFileManagerProtocol
  
  /// LogHandler created by the `SwiftLogFireCloudManager` factory method for every logger requested by the client app
  /// This should only be called by the
  /// - Parameters:
  ///   - label: client supplied string describing the logger.  Should be unique but not enforced
  ///   - config: `SwiftLogFireCouldConfig` object supplied by client app.
  ///   - cloudLogfileManager: object that is used to manage the uploading of files to the cloud through the client provided uploader.
  internal init(
    label: String, config: SwiftLogFireCloudConfig,
    cloudLogfileManager: CloudLogFileManagerProtocol? = nil
  ) {
    self.label = label
    self.config = config
    logMessageDateFormatter.timeZone = TimeZone.current
    logMessageDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    logMessageDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
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
  
  /// LogHandler method that takes the clients call to the Logger interface and performs the logging to file & cloud.
  /// - Parameters:
  ///   - level: the log level set by the user, as defined in the SwiftLog interface.
  ///   - message: the message to be logged.
  ///   - metadata: the metadata to also be logged, as set by the client app.
  ///   - file: filename from where the client app requested a message to be logged.
  ///   - function: method from where the client app requested a message to be logged.
  ///   - line: file line number where the client app requested a message to be logged.
  internal func log(
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

      #if targetEnvironment(simulator)
      if self.config.logToCloudOnSimulator && self.config.logToCloud {
        self.localFileLogManager.log(msg: logmsg)
      }
      #else
      if self.config.logToCloud == true {
        self.localFileLogManager.log(msg: logmsg)
      }
      #endif

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
  
  /// Metadata dictionary to be written with log
  public var metadata: Logger.Metadata = .init()
  
  /// Default log level for the logger
  public var logLevel: Logger.Level = .info

}
