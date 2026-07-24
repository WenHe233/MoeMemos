import Foundation
import XCTest
@testable import MemoKit

final class MemoEditorFeatureAvailabilityTests: XCTestCase {
    func testJournalingSuggestionsAreUnavailableBeforeIOS172() {
        XCTAssertFalse(
            supportsJournalingSuggestions(version: (17, 0), deviceFamily: .phone)
        )
        XCTAssertFalse(
            supportsJournalingSuggestions(version: (17, 1), deviceFamily: .phone)
        )
    }

    func testJournalingSuggestionsAreAvailableOnIPhoneFromIOS172() {
        XCTAssertTrue(
            supportsJournalingSuggestions(version: (17, 2), deviceFamily: .phone)
        )
        XCTAssertTrue(
            supportsJournalingSuggestions(version: (18, 0), deviceFamily: .phone)
        )
    }

    func testJournalingSuggestionsRequireIOS26OnIPad() {
        XCTAssertFalse(
            supportsJournalingSuggestions(version: (18, 0), deviceFamily: .pad)
        )
        XCTAssertTrue(
            supportsJournalingSuggestions(version: (26, 0), deviceFamily: .pad)
        )
    }

    func testJournalingSuggestionsAreUnavailableForMacPresentation() {
        XCTAssertFalse(
            supportsJournalingSuggestions(version: (26, 0), deviceFamily: .mac)
        )
        XCTAssertFalse(
            supportsJournalingSuggestions(
                version: (26, 0),
                deviceFamily: .phone,
                isIOSAppOnMac: true
            )
        )
    }

    func testJournalingSuggestionsAreUnavailableWithoutEntitlement() {
        XCTAssertFalse(
            supportsJournalingSuggestions(
                version: (18, 0),
                deviceFamily: .phone,
                hasRequiredEntitlement: false
            )
        )
    }

    private func supportsJournalingSuggestions(
        version: (Int, Int),
        deviceFamily: MemoEditorDeviceFamily,
        isIOSAppOnMac: Bool = false,
        hasRequiredEntitlement: Bool = true
    ) -> Bool {
        MemoEditorFeatureAvailability.supportsJournalingSuggestions(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: version.0,
                minorVersion: version.1,
                patchVersion: 0
            ),
            deviceFamily: deviceFamily,
            isIOSAppOnMac: isIOSAppOnMac,
            hasRequiredEntitlement: hasRequiredEntitlement
        )
    }
}
