import SwiftUI

/// Reviews an AI-generated email. The user edits it, then sends it from their
/// own mail app (mailto:) or copies it — JobTrack never sends silently.
struct EmailDraftSheet: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    let draft: EmailDraft
    let recipient: String?
    let gmail: GmailService?
    let onSent: () -> Void
    let onClose: () -> Void

    @State private var subject: String
    @State private var messageBody: String
    @State private var to: String
    @State private var copied = false
    @State private var isSending = false
    @State private var sendError: String?

    init(
        draft: EmailDraft,
        recipient: String?,
        gmail: GmailService? = nil,
        onSent: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.draft = draft
        self.recipient = recipient
        self.gmail = gmail
        self.onSent = onSent
        self.onClose = onClose
        _subject = State(initialValue: draft.subject)
        _messageBody = State(initialValue: draft.body)
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
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 220)
                        .font(.body)
                }
                Section {
                    if let gmail, gmail.isConnected {
                        Button {
                            Task { await sendViaGmail(gmail) }
                        } label: {
                            if isSending {
                                HStack { ProgressView(); Text("Envoi via Gmail…") }
                            } else {
                                Label("Envoyer via Gmail", systemImage: "paperplane.fill")
                            }
                        }
                        .disabled(isSending || to.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
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
                    if let sendError {
                        Text(sendError).foregroundStyle(.orange)
                    } else {
                        Text("Tu peux envoyer directement via Gmail (si connecté), "
                             + "ouvrir ta messagerie, ou copier le message.")
                    }
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

    private func sendViaGmail(_ gmail: GmailService) async {
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            try await gmail.send(
                to: to.trimmingCharacters(in: .whitespacesAndNewlines),
                subject: subject,
                body: messageBody)
            onSent()
            dismiss()
        } catch let error as GmailError {
            sendError = error.errorDescription
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func openInMail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to.trimmingCharacters(in: .whitespacesAndNewlines)
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: messageBody),
        ]
        if let url = components.url {
            openURL(url)
        }
    }

    private func copyToClipboard() {
        let text = "Objet : \(subject)\n\n\(messageBody)"
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
