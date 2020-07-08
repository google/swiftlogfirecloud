import Foundation

@testable import SwiftLogFireCloud

class FakeCloudLogFileManager: CloudLogFileManagerProtocol {

  var cloudPushQueue: [URL] = []
  var recentWrittenFiles: [URL] = []

  func reportUploadStatus(_ status: CloudUploadStatus) {
  }

  func isNowTheRightTimeToWriteToCloud(_ localLogFile: LocalLogFile) -> Bool {
    return true
  }

  func writeLogFileToCloud(localLogFile: LocalLogFile) {
    if let fileURL = localLogFile.fileURL {
      recentWrittenFiles.append(fileURL)
    }
  }
  func addFileToCloudPushQueue(localLogFile: LocalLogFile) {
    if let fileURL = localLogFile.fileURL {
      cloudPushQueue.append(fileURL)
    }
  }
}
