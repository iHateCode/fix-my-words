import SwiftUI
import FixMyWordsCore

struct AISettingsView: View {
    let keychain: KeychainStore
    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var keyStatus: String?
    @State private var catalogue: [CatalogueModel] = []
    @State private var catalogueError: String?

    var body: some View {
        @Bindable var settings = AppSettings.shared
        Form {
            Section("OpenRouter key") {
                // After saving, the field is emptied and only "A key is saved" shows, so the key is never shown again.
                SecureField(hasKey ? "A key is saved. Paste a new one to replace it." : "Paste your OpenRouter key",
                            text: $keyDraft)
                    .accessibilityIdentifier("settings.key")
                HStack {
                    Button("Save") { saveKey() }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("settings.saveKey")
                    Button("Test key") { Task { await testKey() } }
                        .disabled(!hasKey)
                        .accessibilityIdentifier("settings.testKey")
                    if let keyStatus {
                        Text(verbatim: keyStatus).foregroundStyle(.secondary).accessibilityIdentifier("settings.keyStatus")
                    }
                }
            }
            Section("Main model") {
                ModelPicker(modelID: $settings.primaryModel, effort: $settings.primaryEffort, catalogue: catalogue,
                            identifier: "settings.primary")
            }
            Section("Backup model (used when the main model fails)") {
                ModelPicker(modelID: $settings.backupModel, effort: $settings.backupEffort, catalogue: catalogue,
                            identifier: "settings.backup")
            }
            if let catalogueError {
                Text(verbatim: catalogueError).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { hasKey = keychain.read() != nil }
        .task { await loadCatalogue() }
    }

    private func saveKey() {
        do {
            try keychain.save(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            keyDraft = ""
            hasKey = true
            keyStatus = "Key saved"
        } catch {
            keyStatus = "Couldn't save the key to the Keychain."
        }
    }

    private func testKey() async {
        guard let key = keychain.read() else { return }
        keyStatus = "Testing…"
        do {
            try await OpenRouterCatalogue.testKey(key, baseURL: AppSettings.shared.openRouterSettings.baseURL)
            keyStatus = "Key works"
        } catch {
            keyStatus = FixFailure(error).message
        }
    }

    private func loadCatalogue() async {
        guard catalogue.isEmpty else { return }
        do {
            catalogue = try await OpenRouterCatalogue.models(baseURL: AppSettings.shared.openRouterSettings.baseURL)
            catalogueError = nil
        } catch {
            catalogueError = "Couldn't load OpenRouter's model list, so model ids are typed by hand."
        }
    }
}

private struct ModelPicker: View {
    @Binding var modelID: String
    @Binding var effort: String?
    let catalogue: [CatalogueModel]
    let identifier: String

    var body: some View {
        Group { pickers }
            // A saved level the model doesn't offer would make OpenRouter refuse every request, silently sending
            // each fix to the backup. Correct it once the list is known.
            .onChange(of: catalogue, initial: true) { correctSavedEffort() }
    }

    private func correctSavedEffort() {
        guard let entry = catalogue.first(where: { $0.id == modelID }) else { return }
        if let effort, entry.efforts.contains(effort) { return }
        if effort == nil, entry.efforts.isEmpty { return }
        effort = entry.defaultEffort
    }

    @ViewBuilder private var pickers: some View {
        let entry = catalogue.first { $0.id == modelID }
        if catalogue.isEmpty {
            // Typed by hand: the old model's level may not apply, so send none until the list can be checked.
            TextField("Model id", text: Binding(get: { modelID }, set: { modelID = $0; effort = nil }))
        } else {
            Picker("Model", selection: Binding(get: { modelID }, set: { newID in
                modelID = newID
                effort = catalogue.first { $0.id == newID }?.defaultEffort   // lowest level it allows
            })) {
                if entry == nil { Text(modelID).tag(modelID) }
                ForEach(catalogue) { Text($0.name).tag($0.id) }
            }
            .accessibilityIdentifier("\(identifier).model")
        }
        // No `reasoning` object in the catalogue: no picker, and the request leaves `reasoning` out.
        let efforts = entry.map(\.efforts) ?? (catalogue.isEmpty ? CatalogueModel.allEfforts : [])
        if !efforts.isEmpty {
            Picker("Thinking", selection: $effort) {
                if entry == nil { Text("Not sent").tag(String?.none) }
                ForEach(efforts, id: \.self) { Text($0 == "none" ? "Off" : $0.capitalized).tag(Optional($0)) }
            }
            .accessibilityIdentifier("\(identifier).effort")
        }
    }
}

/// One entry from `GET /api/v1/models`, cut down to what the pickers need.
struct CatalogueModel: Identifiable, Decodable, Equatable {
    struct Reasoning: Decodable, Equatable {
        let supportedEfforts: [String]?
        let mandatory: Bool?
        enum CodingKeys: String, CodingKey { case supportedEfforts = "supported_efforts", mandatory }
    }

    static let allEfforts = ["max", "xhigh", "high", "medium", "low", "minimal", "none"]   // highest first, like the catalogue

    let id: String
    let name: String
    let reasoning: Reasoning?

    /// The thinking levels to offer. "none" (Off) only when listed and thinking isn't mandatory.
    /// A null `supported_efforts` means every value is accepted (OpenRouter reasoning docs).
    var efforts: [String] {
        guard let reasoning else { return [] }
        let listed = reasoning.supportedEfforts ?? Self.allEfforts
        return reasoning.mandatory == true ? listed.filter { $0 != "none" } : listed
    }

    /// `none` where allowed, otherwise the lowest listed level (the last entry); nil with no `reasoning` object.
    var defaultEffort: String? {
        efforts.contains("none") ? "none" : efforts.last
    }
}

enum OpenRouterCatalogue {
    private struct ModelList: Decodable { let data: [CatalogueModel] }
    private static let session = URLSession(configuration: .ephemeral)   // no cookies or cached responses on disk

    static func models(baseURL: URL) async throws -> [CatalogueModel] {
        let (data, response) = try await session.data(from: baseURL.appending(path: "models"))
        try check(response)
        return try JSONDecoder().decode(ModelList.self, from: data).data.sorted { $0.name < $1.name }
    }

    /// `GET /api/v1/key` answers 200 for a working key.
    static func testKey(_ key: String, baseURL: URL) async throws {
        var request = URLRequest(url: baseURL.appending(path: "key"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    private static func check(_ response: URLResponse) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw AIError.network }
        switch status {
        case 200: return
        case 401: throw AIError.unauthorized
        case 402: throw AIError.outOfCredit
        case 429: throw AIError.rateLimited
        default: throw AIError.server(status)
        }
    }
}
