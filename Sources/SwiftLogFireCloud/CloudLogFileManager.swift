#if canImport(UIKit)
import UIKit
#endif

protocol CloudLogFileLocalFileManagerProtocol : class {
    func deleteLocalFile(fileURL: URL)
    func getLocalLogFileAttributes(fileURL: URL) -> (fileSize: UInt64?, creationDate: Date?)
}

class CloudLogFileManager : CloudLogFileManagerProtocol {
    
    private var logability: Logability = .normal
    private var lastWriteAttempt: Date?
    private var lastWriteSuccess: Date?
    private var successiveFails: Int = 0
    private var strandedFilesToPush: [URL]?
    private var strandedFileTimer: Timer?
    private var cloudDateFormatter: DateFormatter
    private let config: SwiftLogFileCloudConfig
    
    
    private let cloudLogQueue = DispatchQueue(label: "com.leisurehoundsports.swiftfirelogcloud-remove", qos: .background)
    
    weak var delegate : CloudLogFileLocalFileManagerProtocol?
    
    init(config: SwiftLogFileCloudConfig) {
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
        
        if  let versionNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            cloudFilePath += "v\(versionNumber)b\(buildNumber)/"
        }
        
        if let deviceIDForFilename = config.uniqueIDString, deviceIDForFilename.count != 0 {
            cloudFilePath += "\(deviceIDForFilename)/"
        } else {
            if let deviceID = UIDevice.current.identifierForVendor?.uuidString {
                cloudFilePath += "\(deviceID)/"
            }
        }
        cloudFilePath += "\(fileDateString).log"
        return cloudFilePath
    }
    
    func writeLogFileToCloud(localFileURL: URL) {
        cloudLogQueue.async {
            
            let fileAttr = self.delegate?.getLocalLogFileAttributes(fileURL: localFileURL)
            guard let fileSize = fileAttr?.fileSize, fileSize > 0 else { self.delegate?.deleteLocalFile(fileURL: localFileURL); return }
            let cloudFilePath = self.createCloundFilePathAndName(date: fileAttr?.creationDate)
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
    
    func addFileToCloudPushQueue(localFileURL: URL) {
        if strandedFilesToPush == nil {
            strandedFilesToPush = [URL]()
        }
        if let fileCount = strandedFilesToPush?.count, fileCount <= 20 {
            strandedFilesToPush?.append(localFileURL)
        } else {
            delegate?.deleteLocalFile(fileURL: localFileURL)
        }
        if strandedFilesToPush?.count == 1 {
            DispatchQueue.main.async {
                self.strandedFileTimer = Timer.scheduledTimer(timeInterval: 25, target: self, selector: #selector(self.processCloudPushQueue), userInfo: nil, repeats: true)
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
            
            guard let fileCount = self.strandedFilesToPush?.count, fileCount  > 0 else { return }
            if let fileURL = self.strandedFilesToPush?.first {
                self.writeLogFileToCloud(localFileURL: fileURL)
                self.strandedFilesToPush?.removeFirst()
            }
        }
    }

}
