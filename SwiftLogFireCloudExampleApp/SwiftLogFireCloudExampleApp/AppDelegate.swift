//
//  AppDelegate.swift
//  SwiftLogFireCloudExampleApp

import Firebase
import Logging
import SwiftLogFireCloud
import UIKit




@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

  var logger: Logger?
  var altLogger: Logger?
  var logUploader: SwiftLogFireCloudUploader?

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    
    //Initialize Firebase
    FirebaseApp.configure()
  
    //Create the client impl of the FirebaseStorage uploader
    logUploader = SwiftLogFireCloudUploader(storage: Storage.storage())

    //Configure and initialize the SwiftLogFireCloud library
    //Note:  localFileSizeThresholdToPushToCloud is artificially low to see the sample app in action
    let config = SwiftLogFireCloudConfig(
      logToCloud: true,
      localFileSizeThresholdToPushToCloud: 1024,
      logToCloudOnSimulator: true,
      cloudUploader: logUploader)
    let swiftLogFileCloudManager = SwiftLogFileCloudManager()
    
    //Bootstrap SwiftLog...make sure this is only run once
    LoggingSystem.bootstrap(swiftLogFileCloudManager.makeLogHandlerFactory(config: config))
    
    //Create a logger
    logger = Logger(label: "SwiftLogFireCloudExampleAppLogger")
    
    //Log something
    logger?.info("This is a very long log message, I need it to be longer than 100 bytes so it trips the trigger to write the log file to the local disk.  Is this long enough?")
    
    //Log more messages over time.
    for i in 1...50 {
      //Async the writes in this example app given a trivially low localFileSizeThresholdToPushToCloud as
      //Firebase Storage rate limits
      let delay = DispatchTime.now().advanced(by: .seconds(i*1))
      DispatchQueue.main.asyncAfter(deadline: delay) {
        self.logger?.info("\(i) This is another short message, which shoud eclipse the file threshold for cloud upload after its repeated logs")
      }
    }
    
    //Create another logger, with a different label
    altLogger = Logger(label: "SwiftLogFireCloudAlternativeExampleAppLogger")

    //Log messages to altLogger over time
    for i in 1...50 {
      //Async the writes in this example app given a trivially low localFileSizeThresholdToPushToCloud as
      //Firebase Storage rate limits
      let delay = DispatchTime.now().advanced(by: .seconds(i*1))
      DispatchQueue.main.asyncAfter(deadline: delay) {
        self.altLogger?.info("\(i) I'm writing to the alternate logger, the files on disk and in the cloud should not collide with messages polluting each other")
      }
    }
    return true
  }

  // MARK: UISceneSession Lifecycle

  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
  }

  func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
  }


}

