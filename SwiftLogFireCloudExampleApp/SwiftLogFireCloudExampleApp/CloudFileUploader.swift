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
import Firebase
import SwiftLogFireCloud

final class SwiftLogFireCloudUploader : CloudFileUploaderProtocol {
  
  private let storage: Storage
  
  init(storage: Storage) {
    self.storage = storage
  }
  
  func uploadFile(from localFile: LocalLogFile, to cloudPath: String, completion: @escaping (Result<LocalLogFile, CloudUploadError>) -> Void) {

    let storageReference = self.storage.reference()
    let cloudReference = storageReference.child(cloudPath)
    let uploadTask = cloudReference.putFile(from: localFile.fileURL, metadata: nil) { metadata, error in
      if let error = error {
        print(error.localizedDescription)
        completion(.failure(CloudUploadError.failedToUpload(localFile)))
      }
    }
    _ = uploadTask.observe(.success) { snapshot in
      completion(.success(localFile))
    }
    _ = uploadTask.observe(.failure) { snapshot in
      completion(.failure(CloudUploadError.failedToUpload(localFile)))
    }
  }
}
