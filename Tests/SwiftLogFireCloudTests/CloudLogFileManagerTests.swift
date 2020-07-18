//
//  CloudLogFileManagerTests.swift
//  SwiftLogFireCloudTests
//
//  Created by Timothy Wise on 7/17/20.
//

import XCTest

class CloudLogFileManagerTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
  
  func testInit() {
    // should set label, config.
  }
  
  func testCreateCloudFilePathWithDate() {
    // should ensure bundle, date, deviceID etc are in the path.
  }
  
  func testRightTimetoWriteToCloudWhenLogabilityNormal() {
    // should return true for normal conditions.
  }
  
  func testRightTimeToWriteTOCloudWhenLogabilityImpairedAndWithinRetryInterval() {
    // should return false
  }
  
  func testRightTimeToWriteTOCloudWhenLogabilityImpairedAndOutsideRetryInterval() {
    // should return true
  }
  
  func testRightTimeToWriteTOCloudWhenLogabilityUnfunctionalAndWithinRetryInterval() {
    // should return false
  }
  
  func testRightTimeToWriteTOCloudWhenLogabilityUnfunctionalAndOutsideRetryInterval() {
    // should return true
  }
  
  func testWriteLogFileTCloudWithNoPendingWrites() {
    // should call the uploader delegate
  }
  
  func testWriteLogFileToCloudWithResolvedPendingWrites() {
    
  }
  
  func testWriteLogFileToCloudAfterPendingWritesTimeout() {
    
  }
  
  func testWriteLogFileToCloudIsIgnoredWithSizeZeroAndDeletedLocally() {
    
  }

  func testAddingFirstFileToCloudPushQueue() {
    // should have length of 1
  }
  
  func testAddingAdditionalFilesToCloudPushQueue() {
    
  }
  
  func testReportUploadStatusOnSuccess() {
    
  }
  
  func testReportUploadStatusOnFailure() {
    
  }
  
  func testClodLogabilityWhenNormal() {
    
  }
  
  func testCloudLogabilityWhenImpaired() {
    
  }
  
  func testCloudLogabilityWhenUnfunctional() {
    
  }
}
