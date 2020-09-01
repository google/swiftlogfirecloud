# SwiftLogFireCloud Firebase Extension

This library can be used as an implementation of Apple's SwiftLog interface that captures console logs from iOS and (TODO: macOS) 
apps and pushes them to Firebase Cloud Storage as flat files for later review.  It is implemented with the inherent bias to retain a 
positive user experience of the client app and therefore opts to lose logs over consuming bandwidth or excessive retry failure processing.  
Controlling whether the library will log to the cloud can be managed by the client app and even remotely via a Firestore doc listener, an 
exercise left to the reader.

This is not an officially supported Google product.

## How to add SwiftLogFireCloud to your app

1. In your Xcode project, select File -> Swift Packages -> Add Package Dependencies
1. Enter `https://github.com/google/swiftlogfirecloud` into the search bar.
1. Select `master` as branch or appropriate version for your needs
1. Add and initialize Firebase in your project, if not already done.  See https://firebase.google.com/docs/ios/setup
1. Create a object in your app that conforms to `CloudFileUploaderProtocol` and implements the `uploadFile` method as such:
    
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

1. In your `AppDelegate` add `import Logging` and `import SwiftLogFireCloud`
1. In your `AppDelegate` method `didFinishLaunchingWithOptions` add the following :

        //Create the client impl of the FirebaseStorage uploader
        logUploader = SwiftLogFireCloudUploader(storage: Storage.storage())

        //Configure and initialize the SwiftLogFireCloud library
        let config = SwiftLogFireCloudConfig(
          logToCloud: true,
          localFileSizeThresholdToPushToCloud: 1024*1024*3,
          logToCloudOnSimulator: false,
          cloudUploader: logUploader)
        let swiftLogFileCloudManager = SwiftLogFileCloudManager()

        //Bootstrap SwiftLog...make sure this is only run once
        LoggingSystem.bootstrap(swiftLogFileCloudManager.makeLogHandlerFactory(config: config))

        //Create a logger
        logger = Logger(label: "SwiftLogFireCloudExampleAppLogger")

1. And lastly, wherever in your code you want to log, add `import Logging` and log as such:
`logger?.info("I am a log message")`

The sample project SwiftLogFireCloudExampleApp in the depot demonstrates a working client app logging using SwiftLog.

## A note about privacy

The SwiftLog interface was apparently originally designed for Swift on the Server, as such there is 
no integration of SwiftLog with OSLog on Apple platforms.  As such, it is imperative that client app developers
use descretion when using SwiftLogFireCloud and not log personally identifiable information with 
SwiftLogFireCloud from client devices which will reach your Firebase Storage buckets.

## Warning
This library violates the fundamental rule of software engineering:  never let the software engineering manager write code.  Caveat emptor.

## License
Licensed under the Apache License, Version 2.0 (the "License"); you may not use this work except in compliance with the License.
You may obtain a copy of the License at https://www.apache.org/licenses/LICENSE-2.0


