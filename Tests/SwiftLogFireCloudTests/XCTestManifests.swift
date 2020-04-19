import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(SwiftLogFireCloudTests.allTests),
        testCase(LocalLogFileManagerTests.allTests),
    ]
}
#endif
