import SwiftUI

/// Reviews an AI-generated email. The user edits it, then sends it from their
/// own mail app (mailto:) or copies it — JobTrack never sends silently.
struct EmailDraftSheet: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    let draft: EmailDraft
    let recipient: String?
    let onSent: () -> Void
    let onClose: () -> Void

    @State private var subject: String
    @State private var body: String
    @State private var to: String
    @State private var copied = false

    init(draft: EmailDraft, recipient: String?, onSent: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.draft = draft
        self.recipient = recipient
        self.onSent = onSent
        self.onClose = onClose
        _subject = State(initialValue: draft.subject)
        _body = State(initialValue: draft.body)
        _to = State(initialValue: recipient ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Destinataire") {
                    TextField("email@entreprise.com", text: $to)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .autocorrectionDisabled()
                }
                Section("Objet") {
                    TextField("Objet", text: $subject)
                }
                Section("Message") {
                    TextEditor(text: $body)
                        .frame(minHeight: 220)
                        .font(.body)
                }
                Section {
                    Button {
                        openInMail()
                    } label: {
                        Label("Ouvrir dans Mail", systemImage: "envelope")
                    }
                    Button {
                        copyToClipboard()
                    } label: {
                        Label(copied ? "Copié ✓" : "Copier le message", systemImage: "doc.on.doc")
                    }
                    Button {
                        onSent()
                        dismiss()
                    } label: {
                        Label("Marquer comme envoyé", systemImage: "checkmark.circle")
                    }
                } footer: {
                    Text("JobTrack n'envoie jamais d'e-mail à ta place : tu valides "
                         + "et tu envoies depuis ta messagerie.")
                }
            }
            .navigationTitle("Brouillon")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { onClose(); dismiss() }
                }
            }
        }
    }

    private func openInMail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to.trimmingCharacters(in: .whitespacesAndNewlines)
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url {
            openURL(url)
        }
    }

    private func copyToClipboard() {
        let text = "Objet : \(subject)\n\n\(body)"
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copied = true
    }
}

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
