import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SettingsViewModel {
    var apiKeyInput = ""
    var hasStoredKey = false
    var statusMessage: String?
    var isError = false
    var isTesting = false

    // France Travail credentials
    var ftClientIDInput = ""
    var ftClientSecretInput = ""
    var hasFranceTravail = false

    // Adzuna credentials
    var adzunaAppIDInput = ""
    var adzunaAppKeyInput = ""
    var hasAdzuna = false

    private let secretStore: SecretStore
    private let claude: ClaudeService

    init(secretStore: SecretStore, claude: ClaudeService) {
        self.secretStore = secretStore
        self.claude = claude
        refreshKeyState()
    }

    func refreshKeyState() {
        hasStoredKey = secretStore.anthropicAPIKey() != nil
        hasFranceTravail = secretStore.value(AppConfig.franceTravailClientIDAccount) != nil
            && secretStore.value(AppConfig.franceTravailClientSecretAccount) != nil
        hasAdzuna = secretStore.value(AppConfig.adzunaAppIDAccount) != nil
            && secretStore.value(AppConfig.adzunaAppKeyAccount) != nil
    }

    // MARK: - France Travail / Adzuna credentials

    func saveFranceTravail() {
        let id = ftClientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = ftClientSecretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else { return }
        do {
            try secretStore.save(id, account: AppConfig.franceTravailClientIDAccount)
            try secretStore.save(secret, account: AppConfig.franceTravailClientSecretAccount)
            ftClientIDInput = ""; ftClientSecretInput = ""
            hasFranceTravail = true
            show("Clés France Travail enregistrées. Active la source dans le Fil.", error: false)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    func deleteFranceTravail() {
        try? secretStore.delete(account: AppConfig.franceTravailClientIDAccount)
        try? secretStore.delete(account: AppConfig.franceTravailClientSecretAccount)
        hasFranceTravail = false
        show("Clés France Travail supprimées.", error: false)
    }

    func saveAdzuna() {
        let id = adzunaAppIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = adzunaAppKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !key.isEmpty else { return }
        do {
            try secretStore.save(id, account: AppConfig.adzunaAppIDAccount)
            try secretStore.save(key, account: AppConfig.adzunaAppKeyAccount)
            adzunaAppIDInput = ""; adzunaAppKeyInput = ""
            hasAdzuna = true
            show("Clés Adzuna enregistrées. Active la source dans le Fil.", error: false)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    func deleteAdzuna() {
        try? secretStore.delete(account: AppConfig.adzunaAppIDAccount)
        try? secretStore.delete(account: AppConfig.adzunaAppKeyAccount)
        hasAdzuna = false
        show("Clés Adzuna supprimées.", error: false)
    }

    func saveKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try secretStore.save(key, account: AppConfig.apiKeyKeychainAccount)
            apiKeyInput = ""
            hasStoredKey = true
            show("Clé enregistrée dans le Keychain.", error: false)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    func deleteKey() {
        do {
            try secretStore.delete(account: AppConfig.apiKeyKeychainAccount)
            hasStoredKey = false
            show("Clé supprimée.", error: false)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    /// Lightweight connectivity/validity check using a tiny parse call.
    func testKey() async {
        isTesting = true
        defer { isTesting = false }
        do {
            _ = try await claude.parseOffer(rawText: "Test connexion API. Poste: Testeur chez ExampleCorp à Paris.")
            show("Clé valide ✓", error: false)
        } catch let error as ClaudeError {
            show(error.errorDescription ?? "Erreur", error: true)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    // MARK: - Data management

    /// Export all offers as JSON to a temporary file for sharing.
    func exportData(offers: [JobOffer]) -> URL? {
        struct ExportOffer: Encodable {
            let title, company, location, description, status, notes: String
            let sourceURL: String?
            let tags: [String]
            let dateAdded: Date
            let matchScore: Int?
        }
        let export = offers.map {
            ExportOffer(
                title: $0.title, company: $0.company, location: $0.location,
                description: $0.descriptionText, status: $0.status.rawValue,
                notes: $0.notes, sourceURL: $0.sourceURL, tags: $0.tags,
                dateAdded: $0.dateAdded, matchScore: $0.matchScore
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(export)
            let url = FileManager.default.temporaryDirectory
                .appending(path: "JobTrack-export.json")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            show("Export impossible : \(error.localizedDescription)", error: true)
            return nil
        }
    }

    /// Delete ALL offers, resumes and letters.
    func deleteAllData(context: ModelContext) {
        do {
            try context.delete(model: CoverLetter.self)
            try context.delete(model: JobOffer.self)
            try context.delete(model: Resume.self)
            try context.save()
            show("Toutes les données ont été supprimées.", error: false)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    private func show(_ message: String, error: Bool) {
        statusMessage = message
        isError = error
    }
}
