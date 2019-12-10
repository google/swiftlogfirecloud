import Logging
import Foundation
//import Firebase
//TODO:  I actually want to be injected the Storage object, but I need a Firebase object in the library definition to compile, no?  I think I can
// add it to the test object easy enough, but then I can't build the library without testing. Or is that a feature...

struct SwiftLogFileCloudConfig {
    let logToCloud                  : Bool?
    let localFileBufferSize         : Int?
    let localFileBufferWriteInterval: TimeInterval?
    //let storage                   : Storage  //This is a Firebase object.  I don't want the library to depend on firebase, rather want to receive it from the library client.
    
    init(logToCloud: Bool? = nil, localFileBufferSize: Int? = nil, localFileBufferWriteInterval: TimeInterval? = nil) {
        self.logToCloud = logToCloud
        self.localFileBufferSize = localFileBufferSize
        self.localFileBufferWriteInterval = localFileBufferWriteInterval
    }
}

class SwfitLogFileCloudManager {
    
    typealias LogHandlerFactory = (String) -> LogHandler
    
    func makeLogHandlerFactory(config: SwiftLogFileCloudConfig) -> LogHandlerFactory {
        func makeLogHandler(label: String) -> LogHandler {
            return SwiftLogFireCloud(label: label, config: config)
        }
        return makeLogHandler
    }
}
class SwiftLogFireCloud : LogHandler {

    private var label: String
    private var config: SwiftLogFileCloudConfig
    
    init(label: String, config: SwiftLogFileCloudConfig) {
        self.label = label
        self.config = config
    }
    
    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, file: String, function: String, line: UInt) {

        var metadataString: String = ""
        if let metadata = metadata {
            metadataString = !metadata.isEmpty ? metadata.map { "\($0)=\($1)"}.joined(separator: " ") : ""
        }
        print("\(metadataString) \(level): \(message.description)")
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
    
}
