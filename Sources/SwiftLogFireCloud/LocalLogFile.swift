#if canImport(UIKit)
import UIKit
#endif

internal struct LocalLogFile {
    var buffer: Data = Data()
    var fileURL: URL?
    let config: SwiftLogFileCloudConfig
    let bufferSizeToGiveUp: Int
    var bytesWritten: Int = 0
    var firstFileWrite: Date?
    var lastFileWrite: Date?
    var lastFileWriteAttempt: Date?
    var successiveWriteFailures: Int = 0
    
    private static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSSZ'"
        return dateFormatter
    }()

    fileprivate func createLogFileName(deviceId: String?) -> String {
        var deviceIdForFileName = deviceId
        if deviceId == nil || deviceId?.count == 0 {
            deviceIdForFileName = UIDevice.current.identifierForVendor?.uuidString
        }
        let fileDateString = LocalLogFile.dateFormatter.string(from: Date())
        let bundleString = Bundle.main.bundleIdentifier
        let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
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

        fileString += ".log"
        print(fileString)
        return fileString.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! //TODO this shoudl always escape, but be better here
    }

    internal func createLogFileURL(localLogDirectoryName: String, clientDeviceID: String?) -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    
        if localLogDirectoryName.count != 0 {
            return paths[0].appendingPathComponent(localLogDirectoryName).appendingPathComponent(createLogFileName(deviceId: clientDeviceID))
        } else {
            return paths[0].appendingPathComponent(createLogFileName(deviceId: clientDeviceID))
        }
    }
    
    init(config: SwiftLogFileCloudConfig) {
        self.config = config
        self.bufferSizeToGiveUp = 4 * config.localFileBufferSize
        self.fileURL = createLogFileURL(localLogDirectoryName: config.logDirectoryName, clientDeviceID: config.uniqueIDString)
        
        
        // The below only applies for manual testing, and breaks value type constants
        //  #if targetEnvironment(simulator)
        //      self.bufferWriteSize = 1024 * 16
        //  #endif
    }
}
