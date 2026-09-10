import SwiftUI
import UniformTypeIdentifiers

struct ProtectPDFView: View {
    var initialURL: URL? = nil
    let complete: (LibraryDocument) -> Void

    private enum Field: Hashable { case password, confirmation }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var loadedInitialSource = false
    @State private var source: Data?
    @State private var sourceName: String?
    @State private var filename = "Protected Document"
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showsPassword = false
    @State private var showFiles = false
    @State private var busy = false
    @State private var status = ""
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var protectedPDF: ProtectedPDF?

    private var passwordError: String? {
        guard !password.isEmpty else { return nil }
        return (try? PDFProtection.validate(password)) == nil
            ? "Use 6–128 characters without control characters."
            : nil
    }

    private var confirmationError: String? {
        guard !confirmation.isEmpty, password != confirmation else { return nil }
        return "Passwords do not match."
    }

    private var canPrepare: Bool {
        source != nil && !busy && passwordError == nil && confirmationError == nil
            && !password.isEmpty && password == confirmation
            && (try? PDFConverter.fileName(filename)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let sourceName {
                        Label(sourceName, systemImage: "doc")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("protect.source")
                    }
                    Button(source == nil ? "Choose PDF" : "Choose Another PDF") { showFiles = true }
                        .frame(minHeight: 44)
                        .disabled(busy)
                    Text("Create a new PDF that requires this password to open. The source PDF stays unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if source != nil {
                    Section("New copy") {
                        TextField("Filename", text: $filename)
                            .disabled(busy)
                        passwordField("Password", text: $password, field: .password)
                            .accessibilityIdentifier("protect.password")
                        if let passwordError {
                            Text(passwordError).font(.footnote).foregroundStyle(.red)
                                .accessibilityIdentifier("protect.passwordError")
                        }
                        passwordField("Confirm Password", text: $confirmation, field: .confirmation)
                            .accessibilityIdentifier("protect.confirmation")
                        if let confirmationError {
                            Text(confirmationError).font(.footnote).foregroundStyle(.red)
                                .accessibilityIdentifier("protect.confirmationError")
                        }
                        Toggle("Show password", isOn: $showsPassword)
                            .disabled(busy)
                    }

                    Section {
                        Label("Folik does not store or recover this password", systemImage: "key")
                        Text("If you forget it, the protected copy cannot be opened. Keep the unchanged original until you verify the new file.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if busy {
                    Section {
                        ProgressView(status)
                        Button("Cancel Processing") { task?.cancel() }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Protect PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { task?.cancel(); clearPasswords(); dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Review Protected Copy", action: prepare)
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 48)
                    .padding()
                    .background(.regularMaterial)
                    .disabled(!canPrepare)
                    .accessibilityIdentifier("protect.review")
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .sheet(item: $protectedPDF) { protectedPDF in
                ProtectedPDFReviewView(
                    source: source ?? Data(),
                    protectedPDF: protectedPDF,
                    filename: filename,
                    complete: complete
                )
            }
            .interactiveDismissDisabled(busy)
            .onDisappear {
                task?.cancel()
                if protectedPDF == nil { clearPasswords() }
            }
            .onAppear {
                guard !loadedInitialSource else { return }
                loadedInitialSource = true
                if let initialURL {
                    load(initialURL)
                    return
                }
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "--ui-test-pdf-source"),
                   index + 1 < arguments.count,
                   let data = Data(base64Encoded: arguments[index + 1]) {
                    source = data
                    sourceName = "Test.pdf"
                    filename = "Protected Test"
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private func passwordField(_ title: String, text: Binding<String>, field: Field) -> some View {
        if showsPassword {
            TextField(title, text: text)
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .submitLabel(field == .password ? .next : .done)
                .onSubmit { focusedField = field == .password ? .confirmation : nil }
        } else {
            SecureField(title, text: text)
                .textContentType(.newPassword)
                .focused($focusedField, equals: field)
                .submitLabel(field == .password ? .next : .done)
                .onSubmit { focusedField = field == .password ? .confirmation : nil }
        }
    }

    private func load(_ url: URL) {
        busy = true
        error = nil
        status = "Reading PDF…"
        source = nil
        sourceName = nil
        protectedPDF = nil
        clearPasswords()
        task = Task {
            defer { busy = false }
            do {
                let data = try await Task.detached {
                    try PDFConverter.readFile(url, maximumBytes: PDFProcessing.maximumBytes)
                }.value
                _ = try await Task.detached { try PDFProcessing.document(data) }.value
                try Task.checkCancellation()
                source = data
                sourceName = url.lastPathComponent
                filename = url.deletingPathExtension().lastPathComponent + " Protected"
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func prepare() {
        guard let source, canPrepare else { return }
        busy = true
        error = nil
        status = "Protecting PDF…"
        let chosenPassword = password
        task = Task {
            defer { busy = false }
            do {
                let result = try await Task.detached {
                    try PDFProtection.protect(source, password: chosenPassword)
                }.value
                try Task.checkCancellation()
                clearPasswords()
                protectedPDF = result
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func clearPasswords() {
        password = ""
        confirmation = ""
    }
}

private struct ProtectedPDFReviewView: View {
    let source: Data
    let protectedPDF: ProtectedPDF
    let filename: String
    let complete: (LibraryDocument) -> Void

    @EnvironmentObject private var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Password protection verified", systemImage: "lock.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FolikTheme.cobalt)
                    Text("You are reviewing the visible source pages because the new copy is locked. After saving, open the protected copy and enter your password before sharing it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                OfficePDFPreview(data: source)
            }
            .navigationTitle("Protection Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }.disabled(saving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    HStack {
                        if saving { ProgressView() }
                        Text(saving ? "Saving…" : "Save Protected Copy").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving)
                .padding()
                .background(.regularMaterial)
                .accessibilityIdentifier("protect.save")
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                complete(try await library.importConvertedPDF(.preparedPDF(protectedPDF.data), named: filename))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
