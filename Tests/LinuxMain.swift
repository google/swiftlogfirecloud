import SwiftLogFireCloudTests
import XCTest

var tests = [XCTestCaseEntry]()
tests += SwiftLogFireCloudTests.allTests()
tests += LocaalLogFileManagerTests.allTests()
XCTMain(tests)
