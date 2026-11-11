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
                SecureField("Password", text: $password)
                    .textContentType(.password)
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
