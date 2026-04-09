import Foundation
import Observation

@Observable
final class AuthManager {
    var isAuthenticated = false
    var currentUserID: String?
    var isLoading = false

    func signInWithApple() async throws {
        // TODO: Implement Sign in with Apple via Supabase Auth
        isLoading = true
        defer { isLoading = false }

        // Placeholder — will integrate with Supabase Auth
        try await Task.sleep(for: .seconds(1))
        isAuthenticated = true
        currentUserID = UUID().uuidString
    }

    func signInWithEmail(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        // TODO: Implement email auth via Supabase
        try await Task.sleep(for: .seconds(1))
        isAuthenticated = true
        currentUserID = UUID().uuidString
    }

    func signOut() {
        isAuthenticated = false
        currentUserID = nil
    }
}
