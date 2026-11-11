import Foundation

/// Sign-in state for the native layer, talking to the tracker's
/// own server (whatdimake.com) — email + password, session
/// cookie, server-side gate. Kept deliberately small for
/// Phase 1: restore on launch from the cookie, sign in, sign
/// up (the server stamps the 7-day no-card trial at signup and
/// logs the new account in immediately), refresh the access
/// answer, sign out.
///
/// THE GATE IS THE SERVER'S. GET /auth/me reports the account
/// and its access in one answer:
///   { loggedIn, email, subscriptionStatus, trialEndsAt,
///     trialActive, access }
/// and the same gate answers API calls with 401 (signed out)
/// or 402 (signed in, subscription required). This store just
/// carries those answers into view state — it never invents
/// access of its own.
@MainActor
final class SessionStore: ObservableObject {
    enum State: Equatable {
        case restoring
        case signedOut
        case working
        case signedIn
        case subscriptionRequired
    }

    @Published private(set) var state: State = .restoring
    @Published var lastError: String?

    private(set) var currentEmail: String?
    private(set) var subscriptionStatus: String?
    private(set) var trialEndsAt: String?
    private(set) var trialActive: Bool = false
    private(set) var access: Bool = false

    var isSignedIn: Bool { state == .signedIn }

    private let client = APIClient.shared

    // MARK: - Launch

    /// Called once at app start: if the session cookie survived
    /// (shared cookie jar + the UserDefaults mirror), /auth/me
    /// restores the account; otherwise signed out.
    func restore() async {
        state = .restoring
        await refreshAccess()
    }

    /// Re-asks the server who this is and whether they have
    /// access, and routes state from the answer. Used at launch
    /// and by the paywall's "Restore / check again" button.
    func refreshAccess() async {
        do {
            let response = try await client.me()
            applyGateResponse(response)
        } catch {
            if state == .restoring {
                state = .signedOut
            }
        }
    }

    // MARK: - Sign in / up / out

    func signIn(email: String, password: String) async {
        lastError = nil
        state = .working
        do {
            let response = try await client.login(email: email, password: password)
            guard response.status == 200 else {
                lastError = response.serverMessage ?? ("Sign-in failed (HTTP " + String(response.status) + ").")
                state = .signedOut
                return
            }
            // The cookie is set; /auth/me is the authoritative
            // account + access answer.
            await refreshAccess()
        } catch {
            lastError = "Could not reach the server. Check your connection and try again."
            state = .signedOut
        }
    }

    func signUp(email: String, password: String) async {
        lastError = nil
        state = .working
        do {
            let response = try await client.signup(email: email, password: password)
            guard response.status == 200 else {
                lastError = response.serverMessage ?? ("Sign-up failed (HTTP " + String(response.status) + ").")
                state = .signedOut
                return
            }
            await refreshAccess()
        } catch {
            lastError = "Could not reach the server. Check your connection and try again."
            state = .signedOut
        }
    }

    func signOut() async {
        _ = try? await client.logout()
        client.clearCookies()
        currentEmail = nil
        subscriptionStatus = nil
        trialEndsAt = nil
        trialActive = false
        access = false
        lastError = nil
        state = .signedOut
    }

    // MARK: - Gate answers

    /// Interprets one /auth/me (or gate) response:
    /// - 401: no session — signed out.
    /// - 402: the gate's "signed in but no access" answer — the
    ///   body still carries the account's status fields.
    /// - 200 with loggedIn true: access decides signedIn vs
    ///   subscriptionRequired.
    /// - 200 with loggedIn false: signed out.
    private func applyGateResponse(_ response: APIResponse) {
        switch response.status {
        case 401:
            clearAccount()
            state = .signedOut
        case 402:
            if let json = response.jsonObject {
                applyStatusFields(json)
            }
            access = false
            state = .subscriptionRequired
        case 200:
            guard let json = response.jsonObject,
                  let loggedIn = json["loggedIn"] as? Bool, loggedIn else {
                clearAccount()
                state = .signedOut
                return
            }
            applyStatusFields(json)
            access = (json["access"] as? Bool) ?? false
            state = access ? .signedIn : .subscriptionRequired
        default:
            if state == .restoring {
                state = .signedOut
            }
        }
    }

    private func clearAccount() {
        currentEmail = nil
        subscriptionStatus = nil
        trialEndsAt = nil
        trialActive = false
        access = false
    }

    /// Pulls the account fields out of a gate answer. Every
    /// field is optional in practice — the 402 body carries a
    /// subset, older answers may omit some — so each one is
    /// read defensively and only written when present.
    private func applyStatusFields(_ json: [String: Any]) {
        if let email = json["email"] as? String, !email.isEmpty {
            currentEmail = email
        }
        if let status = json["subscriptionStatus"] as? String {
            subscriptionStatus = status
        } else if let status = json["status"] as? String {
            // The 402 body names the field just "status".
            subscriptionStatus = status
        }
        if let trial = json["trialActive"] as? Bool {
            trialActive = trial
        }
        if let ends = stringValue(json["trialEndsAt"]) {
            trialEndsAt = ends
        }
    }

    /// trialEndsAt arrives as a date string from /auth/me; the
    /// 402 body may carry it in the same shape. A numeric epoch
    /// (seconds or milliseconds) is formatted instead of shown
    /// raw. Anything else yields nil.
    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string.isEmpty ? nil : string
        }
        if let number = value as? NSNumber {
            var seconds = number.doubleValue
            if seconds > 1_000_000_000_000 { seconds /= 1000 }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: Date(timeIntervalSince1970: seconds))
        }
        return nil
    }
}
