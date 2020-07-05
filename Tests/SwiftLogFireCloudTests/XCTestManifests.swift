import XCTest

#if !canImport(ObjectiveC)
  func allTests() -> [XCTestCaseEntry] {
    return [
      testCase(SwiftLogFireCloudTests.allTests),
      testCase(LocalLogFileManagerTests.allTests),
    ]
  }
#endif
