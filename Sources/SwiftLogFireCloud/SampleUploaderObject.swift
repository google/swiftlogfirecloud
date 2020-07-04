//
//  SampleUploaderObject.swift
//  SwiftLogFireCloud
//
//  Created by Timothy Wise on 7/3/20.
//

import Foundation
//import Firebase

protocol CloudFileUploaderProtocol {
  //func uploadFile(from localFile: URL, to cloudPath: String)
}

struct CloudFileUploader : CloudFileUploaderProtocol {
  
//  let storage = Storage.storage()
//
//  func uploadFile(from localFile: URL, to cloudPath: String) {
//    let storageReference = self.storage.reference()
//    let cloudReference = storageReference.child(cloudFilePath)
//    let uploadTask = cloudReference.putFile(from: localFileURL, metadata: nil) { metadata, error in
//      if let error = error {
//        // handle the error, not sure how to cascade the error here since client never knows when log to cloud is
//        // invoked, as the logging is fire and forget on behalf of the client.  Perhaps add Crashlytics non-fatal
//        // error logging for client to monitor incident rates.
//      }
//    }
//    _ = uploadTask.observe(.success) { snapshot in
//      self.delegate?.deleteLocalFile(fileURL: localFile)
//    }
//
//    _ = uploadTask.observe(.failure) { snapshot in
//      self.addFileToCloudPushQueue(localFileURL: localFile)
//    }
//  }
}
