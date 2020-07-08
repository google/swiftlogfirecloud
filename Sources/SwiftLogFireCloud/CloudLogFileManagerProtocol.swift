import Foundation

public protocol CloudLogFileManagerProtocol {

  func writeLogFileToCloud(localLogFile: LocalLogFile)
  func addFileToCloudPushQueue(localLogFile: LocalLogFile)
  func reportUploadStatus(_ status: CloudUploadStatus)
  func isNowTheRightTimeToWriteToCloud(_ localLogFile: LocalLogFile) -> Bool
}

public enum CloudUploadStatus {
  case success
  case error
  case failure
}

public protocol CloudFileUploaderProtocol: class {

  func uploadFile(
    _ cloudManager: CloudLogFileManagerProtocol, from localFile: LocalLogFile, to cloudPath: String)
}
