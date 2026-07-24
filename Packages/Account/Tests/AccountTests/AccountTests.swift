import XCTest
@testable import Account

final class AccountTests: XCTestCase {
    func testV0CompatibilityRejectsVersionsLowerThan0210() {
        let result = evaluateMemosVersionCompatibility(.v0(version: "0.20.9"))
        XCTAssertEqual(result, .unsupported)
    }

    func testV0CompatibilityTreatsCanaryAsSupported() {
        let result = evaluateMemosVersionCompatibility(.v0(version: "canary"))
        XCTAssertEqual(result, .supported)
    }

    func testV0CompatibilityRejectsEmptyVersion() {
        let result = evaluateMemosVersionCompatibility(.v0(version: ""))
        XCTAssertEqual(result, .unsupported)
    }

    func testV0CompatibilityAccepts0210AndHigher() {
        let exact = evaluateMemosVersionCompatibility(.v0(version: "0.21.0"))
        let higher = evaluateMemosVersionCompatibility(.v0(version: "0.30.2"))
        XCTAssertEqual(exact, .supported)
        XCTAssertEqual(higher, .supported)
    }

    func testV1CompatibilitySupports0270To0291() {
        let v0270 = evaluateMemosVersionCompatibility(.v1(version: "0.27.0"))
        let v0271 = evaluateMemosVersionCompatibility(.v1(version: "0.27.1"))
        XCTAssertEqual(v0270, .supported)
        XCTAssertEqual(v0271, .supported)
    }

    func testV1CompatibilityRejectsLowerThan0260() {
        let result = evaluateMemosVersionCompatibility(.v1(version: "0.25.9"))
        XCTAssertEqual(result, .unsupported)
    }

    func testV1CompatibilitySupports0291() {
        let result = evaluateMemosVersionCompatibility(.v1(version: "0.29.1"))
        XCTAssertEqual(result, .supported)
    }

    func testV1CompatibilityRequiresWarningForHigherThan0291() {
        let result = evaluateMemosVersionCompatibility(.v1(version: "0.29.2"))
        XCTAssertEqual(result, .v1HigherThanSupported(version: "0.29.2"))
    }

    func testV1CompatibilityRejectsEmptyVersion() {
        let result = evaluateMemosVersionCompatibility(.v1(version: ""))
        XCTAssertEqual(result, .unsupported)
    }

    func testV1CompatibilityTreatsCanaryAsHigherThanSupported() {
        let result = evaluateMemosVersionCompatibility(.v1(version: "canary"))
        XCTAssertEqual(result, .v1HigherThanSupported(version: "canary"))
    }

    func testVersionParserHandlesPrefixAndSuffix() {
        let result = evaluateMemosVersionCompatibility(.v1(version: "v0.27.1-beta.3"))
        XCTAssertEqual(result, .supported)
    }

    func testCredentialStoreFallsBackToPrivateKeychain() {
        var sharedSaveCount = 0
        var privateSaveCount = 0
        let store = makeCredentialStore(
            saveToShared: { _, _ in
                sharedSaveCount += 1
                return false
            },
            saveToPrivate: { _, _ in
                privateSaveCount += 1
                return true
            }
        )

        XCTAssertTrue(store.save(Data("token".utf8), forKey: "account"))
        XCTAssertEqual(sharedSaveCount, 1)
        XCTAssertEqual(privateSaveCount, 1)
    }

    func testCredentialStorePrefersSharedKeychain() {
        var privateSaveCount = 0
        var privateDeleteCount = 0
        let store = makeCredentialStore(
            saveToShared: { _, _ in true },
            saveToPrivate: { _, _ in
                privateSaveCount += 1
                return true
            },
            deleteFromPrivate: { _ in
                privateDeleteCount += 1
            }
        )

        XCTAssertTrue(store.save(Data("token".utf8), forKey: "account"))
        XCTAssertEqual(privateSaveCount, 0)
        XCTAssertEqual(privateDeleteCount, 1)
    }

    func testCredentialStoreReadsPrivateKeychainWhenSharedValueIsMissing() {
        let expected = Data("token".utf8)
        let store = makeCredentialStore(
            readFromShared: { _ in nil },
            readFromPrivate: { _ in expected }
        )

        XCTAssertEqual(store.data(forKey: "account"), expected)
    }

    func testCredentialStoreDeletesBothKeychains() {
        var deletedSharedKeys: [String] = []
        var deletedPrivateKeys: [String] = []
        let store = makeCredentialStore(
            deleteFromShared: { deletedSharedKeys.append($0) },
            deleteFromPrivate: { deletedPrivateKeys.append($0) }
        )

        store.delete("account")

        XCTAssertEqual(deletedSharedKeys, ["account"])
        XCTAssertEqual(deletedPrivateKeys, ["account"])
    }

    private func makeCredentialStore(
        saveToShared: @escaping (Data, String) -> Bool = { _, _ in false },
        saveToPrivate: @escaping (Data, String) -> Bool = { _, _ in false },
        readFromShared: @escaping (String) -> Data? = { _ in nil },
        readFromPrivate: @escaping (String) -> Data? = { _ in nil },
        deleteFromShared: @escaping (String) -> Void = { _ in },
        deleteFromPrivate: @escaping (String) -> Void = { _ in }
    ) -> AccountCredentialStore {
        AccountCredentialStore(
            saveToShared: saveToShared,
            saveToPrivate: saveToPrivate,
            readFromShared: readFromShared,
            readFromPrivate: readFromPrivate,
            deleteFromShared: deleteFromShared,
            deleteFromPrivate: deleteFromPrivate
        )
    }
}
