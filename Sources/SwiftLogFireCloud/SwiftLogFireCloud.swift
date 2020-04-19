import Logging
import Foundation
//import Firebase
//TODO:  I actually want to be injected the Storage object, but I need a Firebase object in the library definition to compile, no?  I think I can
// add it to the test object easy enough, but then I can't build the library without testing. Or is that a feature...



struct SwiftLogFileCloudConfig {
    internal static let megabyte     : Int = 1048576
    var logToCloud                  : Bool = false
    var localFileBufferSize         : Int = megabyte
    var localFileBufferWriteInterval: TimeInterval = 60.0
    let uniqueIDString              : String?
    var minFileSystemFreeSpace      : Int = 20 * megabyte
    var logDirectoryName            : String = "Logs"
    //let storage                   : Storage  //This is a Firebase object.  I don't want the library to depend on firebase, rather want to receive it from the library client.
    
    init(logToCloud: Bool? = nil, localFileBufferSize: Int? = nil, localFileBufferWriteInterval: TimeInterval? = nil, uniqueID: String? = nil, minFileSystemFreeSpace: Int? = nil, logDirectoryName: String? = nil) {
        if let logToCloud = logToCloud {
            self.logToCloud = logToCloud
        }
        if let localFileBufferSize = localFileBufferSize {
            self.localFileBufferSize = localFileBufferSize
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
        self.uniqueIDString = uniqueID
    }
}

class SwfitLogFileCloudManager {
    
    typealias LogHandlerFactory = (String) -> LogHandler
    static var swiftLogFireCloud: SwiftLogFireCloud?
    
    func makeLogHandlerFactory(config: SwiftLogFileCloudConfig) -> LogHandlerFactory {
        func makeLogHandler(label: String) -> LogHandler {
            SwfitLogFileCloudManager.swiftLogFireCloud = SwiftLogFireCloud(label: label, config: config)
            return SwfitLogFileCloudManager.swiftLogFireCloud!
        }
        return makeLogHandler
    }
    
    //ISSUE: is this a hack?  adding all the logger extensions to the manager statically?
    public static func flushLogToCloudNow() {
        print("Flushing to cloud from the SwiftLogCloudManager")
        swiftLogFireCloud?.flushLogToCloudNow()
    }
}
class SwiftLogFireCloud : LogHandler {

    private var label: String
    private var config: SwiftLogFileCloudConfig
    private var localFileLogManager: LocalLogFileManager
    private var logMessageDateFormatter = DateFormatter()
    private var logHandlerSerialQueue: DispatchQueue
    private var cloudLogFileManager: CloudLogFileManagerProtocol
    
    init(label: String, config: SwiftLogFileCloudConfig, cloudLogfileManager: CloudLogFileManagerProtocol? = nil) {
        self.label = label
        self.config = config
        logMessageDateFormatter.timeZone = TimeZone.current
        logMessageDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        logMessageDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        logMessageDateFormatter.calendar = Calendar(identifier: .gregorian)
        
        self.cloudLogFileManager = cloudLogfileManager == nil ? CloudLogFileManager() : cloudLogfileManager!

        localFileLogManager = LocalLogFileManager(config: config, cloudLogfileManager: self.cloudLogFileManager)
        logHandlerSerialQueue = DispatchQueue(label: "com.leisurehoundsports.swiftlogfirecloud", qos: .background)
    }

    #if DEBUG
    private static let isRunningUnderDebugger: Bool = {
        // https://stackoverflow.com/questions/33177182/detect-if-swift-app-is-being-run-from-xcode
        // according to this post, this is essentially lazy and dispatched once.
        // https://medium.com/@jmig/dispatch-once-in-swift-a-24-hours-journey-e18e370eac05
        var info = kinfo_proc()
        var mib : [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let junk = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        assert(junk == 0, "sysctl failed")
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }()
    #endif

    
    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {
        logHandlerSerialQueue.async {

            var metadataString: String = ""
            let dateString = self.logMessageDateFormatter.string(from: Date())
            if let metadata = metadata {
                metadataString = !metadata.isEmpty ? metadata.map { "\($0)=\($1)"}.joined(separator: " ") : ""
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
    
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            return metadata[key]
        }
        set(newValue) {
            metadata[key] = newValue
        }
    }
    
    var metadata: Logger.Metadata = .init()
    
    var logLevel: Logger.Level = .info
    
    func flushLogToCloudNow() {
        //ISSUE:  this method is not part of the protocol, so its inaccessible to the client.
        print("Flushing log to cloud from logHandler")
    }
}

extension Logger {
    func flushLogToCloudNow()  {

        print("Flushing log to cloud from Logger extension")
        //ISSUE:  this is vislble to the client, but it can't access the handler for it to flush
        //let handler = self.handler as? SwiftLogFireCloud
        //Compiler error: 'handler' is inaccessible due to 'internal' protection level
    }
    
}
