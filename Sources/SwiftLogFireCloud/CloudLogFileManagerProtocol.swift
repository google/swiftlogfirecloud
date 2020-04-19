import Foundation

internal protocol CloudLogFileManagerProtocol {
    func writeLogFileToCloud(localFileURL: URL)
    func addFileToCloudPushQueue(localFileURL: URL)
}
