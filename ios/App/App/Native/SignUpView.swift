import SwiftUI

/// Create an account — the same signup the website offers,
/// against the tracker's own server. The server stamps the
/// 7-day no-card trial at signup and signs the new account in
/// immediately, so a successful signup lands straight inside
/// the app (the home placeholder, for Phase 1).
struct SignUpView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                Text("Create your What'd I Make? account. It is the same account as the website — one email and password works both places.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section(header: Text("Your new account")) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                SecureField("Password (8 or more characters)", text: $password)
                    .textContentType(.newPassword)
            }
            Section {
                Label("7 days free, no card needed. After the free week it is " + StoreConfig.priceDisplay + ".", systemImage: "calendar.badge.clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let error = session.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
            Section {
                Button {
                    isWorking = true
                    Task {
                        await session.signUp(email: email.trimmingCharacters(in: .whitespaces),
                                             password: password)
                        isWorking = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView() }
                        Text("Create account")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isWorking || email.isEmpty || password.isEmpty)
            }
        }
        .navigationTitle("Create account")
    }
}
