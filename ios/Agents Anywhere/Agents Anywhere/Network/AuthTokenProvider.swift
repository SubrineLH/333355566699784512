import Foundation

nonisolated protocol AuthTokenProvider: Sendable {
    func accessToken() async throws -> String?
}

nonisolated struct StaticAuthTokenProvider: AuthTokenProvider {
    let token: String?

    func accessToken() async throws -> String? {
        token
    }
}

/// A token refresh changes authentication for the next request without replacing
/// the account's repositories, drafts, pagination or active navigation state.
nonisolated final class MutableAuthTokenProvider: AuthTokenProvider {
    private let token: CompatLocked<String?>
    init(token: String) { self.token = CompatLocked(token) }
    func update(_ token: String?) { self.token.withLock { $0 = token } }
    func accessToken() async throws -> String? { token.withLock { $0 } }
}
