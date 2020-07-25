import Foundation

/// Exposes methods for cloud uploading management to the SwiftLogManager
internal protocol CloudLogFileManagerProtocol {

  func writeLogFileToCloud(localLogFile: LocalLogFile)
  func addFileToCloudPushQueue(localLogFile: LocalLogFile)
  func isNowTheRightTimeToWriteToCloud(_ localLogFile: LocalLogFile) -> Bool
}

/// Exposes one method for the Client to report its Firebase Storage upload success or failure.
public protocol CloudLogFileManagerClientProtocol {
  func reportUploadStatus(_ result: Result<LocalLogFile, CloudUploadError>)
}

/// Error type that the clieint object conforming to `CloudLogFileManagerClientProtocol` uses to report its upload failure.
public enum CloudUploadError : Error {
  case failedToUpload(LocalLogFile)
}

/// Protocol the client object must conform to which has the Firebase Storage references and requests the upload and reports back status.
public protocol CloudFileUploaderProtocol: class {

  func uploadFile(
    _ cloudManager: CloudLogFileManagerClientProtocol, from localFile: LocalLogFile, to cloudPath: String)
}
