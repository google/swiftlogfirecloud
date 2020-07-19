import Foundation

internal protocol CloudLogFileManagerProtocol {

  func writeLogFileToCloud(localLogFile: LocalLogFile)
  func addFileToCloudPushQueue(localLogFile: LocalLogFile)
  func isNowTheRightTimeToWriteToCloud(_ localLogFile: LocalLogFile) -> Bool
}

public protocol CloudLogFileManagerClientProtocol {
  func reportUploadStatus(_ result: Result<LocalLogFile, CloudUploadError>)
}

public enum CloudUploadError : Error {
  case failedToUpload(LocalLogFile)

}

public protocol CloudFileUploaderProtocol: class {

  func uploadFile(
    _ cloudManager: CloudLogFileManagerClientProtocol, from localFile: LocalLogFile, to cloudPath: String)
}
