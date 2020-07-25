# SwiftLogFireCloud Firebase Extension

This library can be used as an implementation of Apple's SwiftLog interface that captures console logs from iOS and (TODO: macOS) 
apps and pushes them to Firebase Cloud Storage as flat files for later review.  It is implemented with the interent bias to retain a 
positive user experience of the client app and therefore opts to lose logs over consuming badnwidth or excessive retry failure processing.  Controlling whether the library will log to the cloud can be controlled by the client app and even remotely via a Firestore doc listener, an exercise 
left to the reader


## How to add SwiftLogFireCloud to your app

1. In your Xcode project, select File -> Swift Packages -> Add Package Dependencies
1. Enter `https://github.com/google/swiftlogfirecloud` into the search bar.
1. Select `master` as branch and appropriate version for your needs
1. Add and initialize Firebase in your project, if not already done.  See https://firebase.google.com/docs/ios/setup
1. Create a object in your app that conforms to `CloudFileUploaderProtocol` and implements the
`uploadFile` method as such:
```code
final class SwiftLogFireCloudUploader : CloudFileUploaderProtocol {
  
  private let storage: Storage
  
  init(storage: Storage) {
    self.storage = storage
  }
  
  func uploadFile(_ cloudManager: CloudLogFileManagerClientProtocol, from localFile: LocalLogFile, to cloudPath: String) {

    let storageReference = self.storage.reference()
    let cloudReference = storageReference.child(cloudPath)
    let uploadTask = cloudReference.putFile(from: localFile.fileURL, metadata: nil) { metadata, error in
      if let error = error {
        print(error.localizedDescription)
        // Add the file to end of the queue upon error.  If its a rights error, it will rety ad infinitum
        cloudManager.reportUploadStatus(.failure(CloudUploadError.failedToUpload(localFile)))
        
        // handle the error, not sure how to cascade the error here since client never knows when log to cloud is
        // invoked, as the logging is fire and forget on behalf of the client.  Perhaps add Crashlytics non-fatal
        // error logging for client to monitor incident rates.
      }
    }
    _ = uploadTask.observe(.success) { snapshot in
      cloudManager.reportUploadStatus(.success(localFile))
    }
    _ = uploadTask.observe(.failure) { snapshot in
      cloudManager.reportUploadStatus(.failure(CloudUploadError.failedToUpload(localFile)))
    }
  }
}

```
1. In your `AppDelegate` add `import Logging` and `import SwiftLogFireCloud`
1. In your `AppDelegate` method `didFinishLaunchingWithOptions` add the following :
```code
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
```
1. And lastly, wherever in your code you want to log, add `import Logging` and log as such:
```
logger?.info("I am a log message")
```

## A note about privacy

SwiftLog was apparently originally designed for Swift on the Server, as such there is no integration
of SwiftLog with OSLog on Apple platforms.  As such, it is imperative that client app developers
use descretion when using SwiftLogFireCloud and not log personally identifiable information with 
SwiftLogFireCloud from client devices which will reach your Firebase Storage buckets.

## Warning
This library violates the fundamental rule of software engineering:  never let the software engineering manager write code.  Caveat emptor.

