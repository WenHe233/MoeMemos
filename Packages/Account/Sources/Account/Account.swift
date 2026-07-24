//
//  Account.swift
//  
//
//  Created by Mudkip on 2023/11/12.
//

import Foundation
import Models
import KeychainSwift
import MemosV0Service
import MemosV1Service

struct AccountCredentialStore {
    let saveToShared: (Data, String) -> Bool
    let saveToPrivate: (Data, String) -> Bool
    let readFromShared: (String) -> Data?
    let readFromPrivate: (String) -> Data?
    let deleteFromShared: (String) -> Void
    let deleteFromPrivate: (String) -> Void

    func save(_ data: Data, forKey key: String) -> Bool {
        if saveToShared(data, key) {
            deleteFromPrivate(key)
            return true
        }
        return saveToPrivate(data, key)
    }

    func data(forKey key: String) -> Data? {
        readFromShared(key) ?? readFromPrivate(key)
    }

    func delete(_ key: String) {
        deleteFromShared(key)
        deleteFromPrivate(key)
    }
}

public extension Account {
    private static var credentialStore: AccountCredentialStore {
        let sharedKeychain = AppInfo.keychainAccessGroupName.map { accessGroup in
            let keychain = KeychainSwift()
            keychain.accessGroup = accessGroup
            return keychain
        }
        let privateKeychain = KeychainSwift()

        return AccountCredentialStore(
            saveToShared: { data, key in
                sharedKeychain?.set(data, forKey: key, withAccess: .accessibleAfterFirstUnlock) ?? false
            },
            saveToPrivate: { data, key in
                privateKeychain.set(data, forKey: key, withAccess: .accessibleAfterFirstUnlock)
            },
            readFromShared: { key in
                sharedKeychain?.getData(key)
            },
            readFromPrivate: { key in
                privateKeychain.getData(key)
            },
            deleteFromShared: { key in
                sharedKeychain?.delete(key)
            },
            deleteFromPrivate: { key in
                privateKeychain.delete(key)
            }
        )
    }
    
    func save() throws {
        let data = try JSONEncoder().encode(self)
        let didSave = Self.credentialStore.save(data, forKey: key)
        if !didSave {
            throw MoeMemosError.accountCredentialSaveFailed(accountKey: key)
        }
    }
    
    func delete() {
        Self.credentialStore.delete(key)
    }
    
    static func retrieve(accountKey: String) -> Account? {
        if accountKey == Account.local.key {
            return .local
        }
        guard let data = Self.credentialStore.data(forKey: accountKey) else {
            return nil
        }
        return try? JSONDecoder().decode(Account.self, from: data)
    }
    
    func remoteService() -> RemoteService? {
        if case .memosV0(host: let host, id: _, accessToken: let accessToken) = self, let hostURL = URL(string: host) {
            return MemosV0Service(hostURL: hostURL, accessToken: accessToken)
        }
        if case .memosV1(host: let host, id: let userId, accessToken: let accessToken) = self, let hostURL = URL(string: host) {
            return MemosV1Service(hostURL: hostURL, accessToken: accessToken, userId: userId)
        }
        return nil
    }
    
    @MainActor
    func toUser() async throws -> User {
        if case .local = self {
            return UserSnapshot.local(accountKey: key).toUserModel()
        }
        if let remoteService = remoteService() {
            let snapshot = try await remoteService.getCurrentUser()
            return snapshot.toUserModel()
        }
        throw MoeMemosError.notLogin
    }
}
