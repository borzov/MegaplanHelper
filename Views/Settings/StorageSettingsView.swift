import SwiftUI
import UniformTypeIdentifiers

struct StorageSettingsView: View {
    @State private var showResetConfirm = false
    @State private var importingFromFile = false
    @State private var exportingToFile = false
    @State private var exportText: String = ""

    private let exporter = SettingsExporter()

    var body: some View {
        Form {
            Section(String(localized: "settings.storage.cacheSection")) {
                CacheStatsRow()
            }

            Section(String(localized: "settings.storage.dataSection")) {
                Button(String(localized: "settings.storage.export")) {
                    do {
                        exportText = try exporter.export()
                        exportingToFile = true
                    } catch {
                        exportText = error.localizedDescription
                    }
                }
                Button(String(localized: "settings.storage.import")) {
                    importingFromFile = true
                }
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Text(String(localized: "settings.storage.reset"))
                }
            }
        }
        .formStyle(.grouped)
        .alert(String(localized: "settings.storage.resetConfirm"), isPresented: $showResetConfirm) {
            Button(String(localized: "settings.storage.reset"), role: .destructive) {
                resetToDefaults()
            }
            Button(String(localized: "general.cancel"), role: .cancel) {}
        }
        .fileExporter(
            isPresented: $exportingToFile,
            document: SettingsJSONDocument(text: exportText),
            contentType: .json,
            defaultFilename: "MegaplanHelper-settings"
        ) { _ in }
        .fileImporter(
            isPresented: $importingFromFile,
            allowedContentTypes: [.json]
        ) { result in
            if case .success(let url) = result,
               let text = try? String(contentsOf: url, encoding: .utf8) {
                try? exporter.importing(json: text)
            }
        }
    }

    private func resetToDefaults() {
        for key in SettingsExporter.exportableKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

private struct SettingsJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.json]
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let str = String(data: data, encoding: .utf8) {
            text = str
        } else { text = "" }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
