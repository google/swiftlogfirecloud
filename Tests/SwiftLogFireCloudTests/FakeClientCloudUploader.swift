import Foundation

@testable import SwiftLogFireCloud

class FakeClientCloudUploader : CloudFileUploaderProtocol {
  
  var mimicSuccessUpload: Bool = true
  var successUploadCount: Int = 0
  var failureUploadCount: Int = 0
  var successUploadURLs = [URL]()
  var failureUploadURLs = [URL]()
  
  func uploadFile(_ cloudManager: CloudLogFileManagerClientProtocol, from localFile: LocalLogFile, to cloudPath: String) {
    switch mimicSuccessUpload {
    case true:
      successUploadCount += 1
      successUploadURLs.append(localFile.fileURL)
      cloudManager.reportUploadStatus(.success(localFile))
    case false:
      failureUploadCount += 1
      failureUploadURLs.append(localFile.fileURL)
      cloudManager.reportUploadStatus(.failure(CloudUploadError.failedToUpload(localFile)))
    }
  }
  
  
}
