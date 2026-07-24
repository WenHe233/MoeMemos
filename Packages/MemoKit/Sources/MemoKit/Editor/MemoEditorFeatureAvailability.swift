import Foundation

enum MemoEditorDeviceFamily: Equatable {
    case phone
    case pad
    case mac
}

enum MemoEditorFeatureAvailability {
    static func supportsJournalingSuggestions(
        operatingSystemVersion: OperatingSystemVersion,
        deviceFamily: MemoEditorDeviceFamily,
        isIOSAppOnMac: Bool
    ) -> Bool {
        guard isAtLeast(operatingSystemVersion, major: 17, minor: 2) else {
            return false
        }
        guard !isIOSAppOnMac, deviceFamily != .mac else {
            return false
        }
        if deviceFamily == .pad {
            return isAtLeast(operatingSystemVersion, major: 26, minor: 0)
        }
        return true
    }

    private static func isAtLeast(
        _ version: OperatingSystemVersion,
        major: Int,
        minor: Int
    ) -> Bool {
        (version.majorVersion, version.minorVersion) >= (major, minor)
    }
}
