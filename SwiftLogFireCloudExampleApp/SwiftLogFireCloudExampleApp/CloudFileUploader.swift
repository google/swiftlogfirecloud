//
//  CloudFileUploader.swift
//  SwiftLogFireCloudExampleApp
//
//  Created by Timothy Wise on 7/5/20.
//  Copyright © 2020 Leisure Hound Sports, Inc. All rights reserved.
//

import Foundation
import Firebase
import SwiftLogFireCloud

final class SwiftLogFireCloudUploader : CloudFileUploaderProtocol {
  
  private let storage: Storage
  
  init(storage: Storage) {
    self.storage = storage
  }
  
  func uploadFile(_ cloudManager: CloudLogFileManagerProtocol, from localFile: LocalLogFile, to cloudPath: String) {
    guard let fileURL = localFile.fileURL else { return }

    let storageReference = self.storage.reference()
    let cloudReference = storageReference.child(cloudPath)
    let uploadTask = cloudReference.putFile(from: fileURL, metadata: nil) { metadata, error in
      if let error = error {
        print(error.localizedDescription)
        // Add the file to end of the queue upon error.  If its a rights error, it will rety ad infinitum
        cloudManager.addFileToCloudPushQueue(localLogFile: localFile)
        
        // handle the error, not sure how to cascade the error here since client never knows when log to cloud is
        // invoked, as the logging is fire and forget on behalf of the client.  Perhaps add Crashlytics non-fatal
        // error logging for client to monitor incident rates.
      }
    }
    _ = uploadTask.observe(.success) { snapshot in
      localFile.delete()
    }
    _ = uploadTask.observe(.failure) { snapshot in
      cloudManager.addFileToCloudPushQueue(localLogFile: localFile)
    }
  }
  
}
