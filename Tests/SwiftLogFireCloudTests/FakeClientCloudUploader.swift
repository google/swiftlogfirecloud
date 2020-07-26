/*
Copyright 2020 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

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
