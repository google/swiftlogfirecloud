import Foundation

class FakeCloudLogFileManager : CloudLogFileManagerProtocol {
    
    var cloudPushQueue: [URL] = []
    var recentWrittenFiles: [URL] = []
    
    func writeLogFileToCloud(localFileURL: URL) {
        recentWrittenFiles.append(localFileURL)
    }
    
    func addFileToCloudPushQueue(localFileURL: URL) {
        cloudPushQueue.append(localFileURL)
    }
    
    
}
