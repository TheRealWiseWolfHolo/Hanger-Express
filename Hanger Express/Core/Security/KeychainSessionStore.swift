import Foundation
import Security

actor KeychainSessionStore: SessionStore {
    private let service: String
    private let account: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        service: String = "com.hangerexpress.rsi-session",
        account: String = "robertsspaceindustries"
    ) {
        self.service = service
        self.account = account
    }

    func loadSession() async -> UserSession? {
        let query = baseQuery(returnData: true)
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        do {
            return try decoder.decode(UserSession.self, from: data)
        } catch {
#if DEBUG
            print("KeychainSessionStore failed to decode the saved RSI session: \(error)")
#endif
            return nil
        }
    }

    func save(_ session: UserSession) async {
        guard let data = try? encoder.encode(session) else {
            return
        }

        let query = baseQuery(returnData: false)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() async {
        SecItemDelete(baseQuery(returnData: false) as CFDictionary)
    }

    private func baseQuery(returnData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        if returnData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }

        return query
    }
}
