import XCTest
@testable import Models

final class ModelsTests: XCTestCase {
    func testExtractsRegularTags() throws {
        let tags = MemoTagExtractor.extract(from: "hello #swift and #ios_dev")
        XCTAssertEqual(tags, ["swift", "ios_dev"])
    }

    func testDoesNotExtractURLFragmentAsTag() throws {
        let tags = MemoTagExtractor.extract(from: "hello http://example.com/#heading")
        XCTAssertTrue(tags.isEmpty)
    }

    func testExtractsTagAndIgnoresURLFragmentInSameLine() throws {
        let tags = MemoTagExtractor.extract(from: "see http://example.com/#heading and #realTag")
        XCTAssertEqual(tags, ["realTag"])
    }

    func testStorageDirectoriesUseAppGroupWhenAvailable() {
        let groupURL = URL(fileURLWithPath: "/group")
        let directories = AppInfo.StorageDirectories(
            groupContainerURL: groupURL,
            applicationSupportURL: URL(fileURLWithPath: "/application-support"),
            cachesURL: URL(fileURLWithPath: "/caches")
        )

        XCTAssertEqual(directories.root, groupURL)
        XCTAssertEqual(
            directories.applicationSupport,
            groupURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        )
        XCTAssertEqual(
            directories.caches,
            groupURL.appendingPathComponent("Library/Caches", isDirectory: true)
        )
    }

    func testStorageDirectoriesFallBackToAppSandboxWithoutAppGroup() {
        let applicationSupportURL = URL(fileURLWithPath: "/application-support")
        let cachesURL = URL(fileURLWithPath: "/caches")
        let directories = AppInfo.StorageDirectories(
            groupContainerURL: nil,
            applicationSupportURL: applicationSupportURL,
            cachesURL: cachesURL
        )

        XCTAssertEqual(
            directories.root,
            applicationSupportURL.appendingPathComponent("MoeMemos", isDirectory: true)
        )
        XCTAssertEqual(directories.applicationSupport, directories.root)
        XCTAssertEqual(
            directories.caches,
            cachesURL.appendingPathComponent("MoeMemos", isDirectory: true)
        )
    }
}
