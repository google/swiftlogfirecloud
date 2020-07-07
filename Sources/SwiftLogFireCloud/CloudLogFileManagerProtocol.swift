import Foundation

public protocol CloudLogFileManagerProtocol {
  func writeLogFileToCloud(localLogFile: LocalLogFile)
  func addFileToCloudPushQueue(localLogFile: LocalLogFile)
}

public protocol CloudFileUploaderProtocol: class {
  func uploadFile(
    _ cloudManager: CloudLogFileManagerProtocol, from localFile: LocalLogFile, to cloudPath: String)
}
