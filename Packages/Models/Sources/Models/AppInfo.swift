//
//  AppInfo.swift
//
//
//  Created by Mudkip on 2023/11/12.
//

import Foundation
import Observation
import StoreKit
import SwiftData
import Factory
import OSLog
#if canImport(Security)
import Security
#endif

@Observable public class AppInfo {
    public static let groupContainerIdentifier = "group.me.mudkip.MoeMemos"
    private static let logger = Logger(subsystem: "me.mudkip.MoeMemos", category: "Persistence")
    private static let keychainAccessGroupSuffix = ".me.mudkip.MoeMemos"

    public struct StorageDirectories: Equatable, Sendable {
        public let root: URL
        public let applicationSupport: URL
        public let caches: URL

        public init(groupContainerURL: URL?, applicationSupportURL: URL, cachesURL: URL) {
            if let groupContainerURL {
                root = groupContainerURL
                applicationSupport = groupContainerURL
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
                caches = groupContainerURL
                    .appendingPathComponent("Library/Caches", isDirectory: true)
            } else {
                root = applicationSupportURL.appendingPathComponent("MoeMemos", isDirectory: true)
                applicationSupport = root
                caches = cachesURL.appendingPathComponent("MoeMemos", isDirectory: true)
            }
        }
    }
    
    @ObservationIgnored public let modelContext: ModelContext
    @ObservationIgnored public let usesPersistentStorage: Bool
    
    public init() {
        let container: ModelContainer
        do {
            let directories = try Self.storageDirectories()
            try FileManager.default.createDirectory(at: directories.root, withIntermediateDirectories: true)
            let storeURL = directories.root.appendingPathComponent("MoeMemos_20260207.store", isDirectory: false)
            let configuration = ModelConfiguration(url: storeURL)
            container = try ModelContainer(
                for: User.self,
                StoredMemo.self,
                StoredResource.self,
                configurations: configuration
            )
            usesPersistentStorage = true
        } catch {
            Self.logger.fault("Persistent model container failed: \(error.localizedDescription, privacy: .public)")
            let fallbackConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
            guard let fallbackContainer = try? ModelContainer(
                for: User.self,
                StoredMemo.self,
                StoredResource.self,
                configurations: fallbackConfiguration
            ) else {
                fatalError("Unable to create the fallback model container.")
            }
            container = fallbackContainer
            usesPersistentStorage = false
        }

        modelContext = ModelContext(container)
    }

    public static func storageDirectories(fileManager: FileManager = .default) throws -> StorageDirectories {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cachesURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let groupContainerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: groupContainerIdentifier
        )
        let directories = StorageDirectories(
            groupContainerURL: groupContainerURL,
            applicationSupportURL: applicationSupportURL,
            cachesURL: cachesURL
        )

        if groupContainerURL == nil {
            logger.notice("App Group is unavailable; using the app sandbox for storage.")
        }
        return directories
    }

    public static func sharedUserDefaults(fileManager: FileManager = .default) -> UserDefaults {
        guard
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupContainerIdentifier) != nil,
            let sharedDefaults = UserDefaults(suiteName: groupContainerIdentifier)
        else {
            return .standard
        }
        return sharedDefaults
    }

    public static var keychainAccessGroupName: String? {
        keychainAccessGroupName(from: entitlementValues(for: "keychain-access-groups"))
    }

    public static var hasJournalingSuggestionsEntitlement: Bool {
        entitlementValues(for: "com.apple.developer.journal.allow").contains("suggestions")
    }

    public static func keychainAccessGroupName(from entitlementValues: [String]) -> String? {
        entitlementValues.first { $0.hasSuffix(keychainAccessGroupSuffix) }
    }

    private static func entitlementValues(for key: String) -> [String] {
#if canImport(Security)
        guard
            let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        else {
            return []
        }
        return value as? [String] ?? []
#else
        return []
#endif
    }
    
    @ObservationIgnored public lazy var website = URL(string: "https://memos.moe")!
    @ObservationIgnored public lazy var privacy = URL(string: "https://memos.moe/privacy")!
    @ObservationIgnored public lazy var registration = ""
}

public extension Container {
    var appInfo: Factory<AppInfo> {
        self { AppInfo() }.shared
    }
}
