import SwiftUI

/// The email + password sign-in form — the same sign-in the
/// website uses (the tracker's own server, its own accounts),
/// in native dress. Shows the server's own error words when a
/// sign-in fails; never invents a reason.
struct SignInView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false

    var body: some View {
        Form {
            Section {
                Text("\u{1F4B5} Know what you actually made.")
                    .font(.headline)
                Text("What'd I Make? keeps your products, videos, sales and costs from all your shops in one place \u2014 and shows your real profit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("7 days free, no card needed. Then " + StoreConfig.priceDisplay + ". No ads, ever.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Sign in with the same email and password you use on whatdimake.com.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section(header: Text("Your account")) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                PasswordField(placeholder: "Password", text: $password, contentType: .password)
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
                        await session.signIn(email: email.trimmingCharacters(in: .whitespaces),
                                             password: password)
                        isWorking = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isWorking { ProgressView() }
                        Text("Sign in")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isWorking || email.isEmpty || password.isEmpty)
            }
            Section {
                NavigationLink {
                    SignUpView()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New here? Create an account")
                            .fontWeight(.semibold)
                        Text("7 days free, no card needed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("What'd I Make?")
    }
}


// MARK: - Password field with show / hide eye

/// A password box with a little eye at the right end: tap it to
/// see what you typed, tap again to hide it. The testers asked
/// for this \u2014 mistyped passwords are the top reason a sign-in
/// fails.
struct PasswordField: View {
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType = .password
    @State private var isVisible = false

    var body: some View {
        HStack {
            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textContentType(contentType)
            .autocapitalization(.none)
            .autocorrectionDisabled()

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isVisible ? "Hide password" : "Show password")
        }
    }
}
