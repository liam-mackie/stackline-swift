import XCTest
@testable import Stackline

final class CachedUserDefaultsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: CachedUserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "sh.mackie.stackline.test.\(UUID().uuidString)"
        defaults = CachedUserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSetAndGetString() {
        defaults.setString("test-value", forKey: "test-key")

        let value: String? = defaults.string(forKey: "test-key")
        XCTAssertEqual(value, "test-value")
    }

    func testSetAndGetBool() {
        defaults.setBool(true, forKey: "bool-key")

        let value = defaults.bool(forKey: "bool-key")
        XCTAssertTrue(value)
    }

    func testSetAndGetDouble() {
        defaults.setDouble(42.5, forKey: "double-key")

        let value = defaults.double(forKey: "double-key")
        XCTAssertEqual(value, 42.5)
    }

    func testSetAndGetData() {
        let originalData = "test data".data(using: .utf8)!
        defaults.setData(originalData, forKey: "data-key")

        let value = defaults.data(forKey: "data-key")
        XCTAssertEqual(value, originalData)
    }

    func testBoolDefaultValue() {
        let value = defaults.bool(forKey: "non-existent-key", default: true)
        XCTAssertTrue(value)
    }

    func testDoubleDefaultValue() {
        let value = defaults.double(forKey: "non-existent-key", default: 99.9)
        XCTAssertEqual(value, 99.9)
    }

    func testCachingPreventsRepeatedReads() {
        defaults.setString("cached-value", forKey: "cache-test")

        let value1: String? = defaults.string(forKey: "cache-test")
        let value2: String? = defaults.string(forKey: "cache-test")

        XCTAssertEqual(value1, "cached-value")
        XCTAssertEqual(value2, "cached-value")
    }

    func testRemoveObject() {
        defaults.setString("to-be-removed", forKey: "remove-key")
        XCTAssertEqual(defaults.string(forKey: "remove-key"), "to-be-removed")

        defaults.removeObject(forKey: "remove-key")
        XCTAssertNil(defaults.string(forKey: "remove-key"))
    }

    func testClearCache() {
        defaults.setString("value1", forKey: "key1")
        defaults.setString("value2", forKey: "key2")

        defaults.clearCache()

        let value1: String? = defaults.string(forKey: "key1")
        let value2: String? = defaults.string(forKey: "key2")

        XCTAssertEqual(value1, "value1")
        XCTAssertEqual(value2, "value2")
    }
}
