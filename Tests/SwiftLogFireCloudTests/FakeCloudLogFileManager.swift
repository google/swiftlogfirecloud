import Foundation

@testable import SwiftLogFireCloud

class FakeCloudLogFileManager: CloudLogFileManagerProtocol {

  var cloudPushQueue: [URL] = []
  var recentWrittenFiles: [URL] = []

  func reportUploadStatus(_ result: Result<LocalLogFile, CloudUploadError>) {
  }

  func isNowTheRightTimeToWriteToCloud(_ localLogFile: LocalLogFile) -> Bool {
    return true
  }

  func writeLogFileToCloud(localLogFile: LocalLogFile) {
    recentWrittenFiles.append(localLogFile.fileURL)
  }
  func addFileToCloudPushQueue(localLogFile: LocalLogFile) {
    cloudPushQueue.append(localLogFile.fileURL)
  }
}
