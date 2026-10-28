import Cocoa
import FlutterMacOS
import XCTest

@testable import xue_hua_navite_auto_update

class RunnerTests: XCTestCase {

  func testCheckEnvironment() {
    let plugin = XueHuaNaviteAutoUpdatePlugin()
    let call = FlutterMethodCall(methodName: "checkEnvironment", arguments: nil)

    let resultExpectation = expectation(description: "checkEnvironment returns environment map.")
    plugin.handle(call) { result in
      guard let map = result as? [String: Any] else {
        XCTFail("Expected dictionary response from checkEnvironment")
        return
      }
      XCTAssertEqual(map["platform"] as? String, "macos")
      XCTAssertNotNil(map["executablePath"] as? String)
      XCTAssertNotNil(map["bundlePath"] as? String)
      XCTAssertGreaterThan((map["processId"] as? Int) ?? 0, 0)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 2)
  }

  func testVerifyPackageChecksum() throws {
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("xue_hua_test_\(UUID().uuidString).dmg")
    try "abc".data(using: .utf8)?.write(to: tempURL)
    defer {
      try? FileManager.default.removeItem(at: tempURL)
    }

    let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    XCTAssertTrue(
      XueHuaNaviteAutoUpdatePlugin.verifySha256(
        filePath: tempURL.path,
        expectedHex: expected
      )
    )
  }
}
