import Foundation

internal protocol CloudLogFileManagerProtocol {
    func writeLogFileToCloud(localLogFile: LocalLogFile)
    func addFileToCloudPushQueue(localLogFile: LocalLogFile)
}
