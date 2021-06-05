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

/// Exposes methods for cloud uploading management to the SwiftLogManager
internal protocol CloudLogFileManagerProtocol {

  func writeLogFileToCloud(localLogFile: LocalLogFile, completion: (()->Void)?)
  func addFileToCloudPushQueue(localLogFile: LocalLogFile)
  func isNowTheRightTimeToWriteToCloud(_ localLogFile: LocalLogFile) -> Bool
}

/// Error type that the clieint object conforming to `CloudLogFileManagerClientProtocol` uses to report its upload failure.
public enum CloudUploadError : Error {
  case failedToUpload(LocalLogFile)
}

/// Protocol the client object must conform to which has the Firebase Storage references and requests the upload and reports back status.
public protocol CloudFileUploaderProtocol: AnyObject {

  func uploadFile(from localFile: LocalLogFile, to cloudPath: String, completion: @escaping (Result<LocalLogFile, CloudUploadError>)->Void)
}
