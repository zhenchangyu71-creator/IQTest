import SwiftUI
import UniformTypeIdentifiers

struct RecordJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct RecordExportButton: View {
    var records: [TestRecord] = []
    var recovery = false
    @State private var presenting = false
    @State private var document = RecordJSONDocument(data: Data())
    @State private var error: String?

    var body: some View {
        Button {
            do {
                document = RecordJSONDocument(data: try recovery ? RecordStore.recoveryExport() : RecordExport.encode(records))
                presenting = true
            } catch { self.error = error.localizedDescription }
        } label: {
            Label(recovery ? "导出原始备份" : "导出 JSON（\(records.count) 条）", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier(recovery ? "exportRecovery" : "exportRecords")
        .fileExporter(isPresented: $presenting, document: document, contentType: .json,
                      defaultFilename: recovery ? "IQTest-原始备份" : "IQTest-成绩记录") { result in
            if case .failure(let failure) = result, (failure as NSError).code != NSUserCancelledError {
                error = failure.localizedDescription
            }
        }
        .alert("导出未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }
}
