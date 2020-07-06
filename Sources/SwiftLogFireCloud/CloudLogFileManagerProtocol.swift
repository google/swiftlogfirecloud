import Foundation

public protocol CloudLogFileManagerProtocol {
  func writeLogFileToCloud(localLogFile: LocalLogFile)
  func addFileToCloudPushQueue(localLogFile: LocalLogFile)
}

public protocol CloudFileUploaderProtocol {
  func uploadFile(_ cloudManager: CloudLogFileManagerProtocol, from localFile: URL, to cloudPath: String)
}
