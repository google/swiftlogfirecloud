import XCTest

import SwiftLogFireCloudTests

var tests = [XCTestCaseEntry]()
tests += SwiftLogFireCloudTests.allTests()
tests += LocaalLogFileManagerTests.allTests()
XCTMain(tests)
