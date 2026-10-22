import XCTest
@testable import IQTest

final class RecordArchiveTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "RecordArchiveTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }

    private func store() -> RecordArchive { RecordArchive(directory: directory, legacyDefaults: defaults) }
    private func record(_ score: Int = 1, at date: TimeInterval = 0) -> TestRecord {
        TestRecord(date: Date(timeIntervalSince1970: date), testType: .raven, difficulty: .medium,
                   score: score, total: 12, iq: nil, percentile: nil)
    }

    func testRecordsPersistAcrossInstancesAndRetryDoesNotDuplicate() throws {
        let first = record(), second = record(2, at: 10)
        try store().append(first)
        try store().append(second)
        try store().append(first)
        let loaded = try store().read()
        XCTAssertEqual(loaded.records.map(\.id), [first.id, second.id])
        XCTAssertEqual(loaded.unreadableCount, 0)
    }

    func testRetryCannotOverwriteADifferentRecordWithTheSameID() throws {
        let first = record()
        var other = record(8)
        other.id = first.id
        try store().append(first)
        XCTAssertThrowsError(try store().append(other))
        XCTAssertEqual(try store().read().records.first?.score, 1)
    }

    func testLegacyMigrationKeepsValidRowsAndOriginalBytes() throws {
        let good = record()
        let row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(good))
        let original = try JSONSerialization.data(withJSONObject: [row, ["score": "broken"]])
        defaults.set(original, forKey: "testRecords")
        let first = try store().read()
        XCTAssertEqual(first.records.map(\.id), [good.id])
        XCTAssertEqual(first.unreadableCount, 1)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("legacy-backup.json")), original)
        XCTAssertEqual(try store().read().records.map(\.id), [good.id])
        let next = record(3)
        try store().append(next)
        XCTAssertEqual(try store().read().records.count, 2)
    }

    func testLegacyRecordsWithoutIDsKeepTheAssignedIDAfterMigration() throws {
        let data = Data(#"[{"date":0,"difficulty":"中级","score":5,"total":12}]"#.utf8)
        defaults.set(data, forKey: "testRecords")
        let first = try XCTUnwrap(store().read().records.first)
        let second = try XCTUnwrap(store().read().records.first)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.score, 5)
    }

    func testInterruptedMigrationResumesWithTheSameAssignedIDs() throws {
        let data = Data(#"[{"date":0,"difficulty":"中级","score":5,"total":12},{"date":1,"difficulty":"中级","score":6,"total":12}]"#.utf8)
        defaults.set(data, forKey: "testRecords")
        var recordWrites = 0
        let failing = RecordArchive(directory: directory, legacyDefaults: defaults, write: { data, url in
            if url.deletingLastPathComponent().lastPathComponent == "records" {
                recordWrites += 1
                if recordWrites == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            }
            try data.write(to: url, options: .atomic)
        })
        XCTAssertThrowsError(try failing.read())
        let savedFiles = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("records"), includingPropertiesForKeys: nil)
        XCTAssertEqual(savedFiles.count, 1)
        let savedID = try XCTUnwrap(savedFiles.first?.deletingPathExtension().lastPathComponent)
        let resumed = try store().read()
        XCTAssertEqual(resumed.records.count, 2)
        XCTAssertTrue(resumed.records.contains { $0.id.uuidString == savedID && $0.score == 5 })
        XCTAssertEqual(try store().read().records.map(\.id), resumed.records.map(\.id))
    }

    func testRemovingLastActiveRecordStillExposesLegacyBackupUntilClear() throws {
        let item = record()
        defaults.set(try JSONEncoder().encode([item]), forKey: "testRecords")
        try store().delete(id: item.id)
        let empty = try store().read()
        XCTAssertTrue(empty.records.isEmpty)
        XCTAssertTrue(empty.hasLegacyBackup)
        try store().clear()
        XCTAssertFalse(try store().read().hasLegacyBackup)
    }

    func testMalformedLegacyArchiveIsNotReplacedWhenSaving() throws {
        let original = Data("not valid JSON".utf8)
        defaults.set(original, forKey: "testRecords")
        XCTAssertThrowsError(try store().read())
        XCTAssertThrowsError(try store().append(record()))
        XCTAssertEqual(defaults.data(forKey: "testRecords"), original)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("legacy-backup.json")), original)
    }

    func testBrokenIndividualFileDoesNotHideHealthyRecordsOrGetOverwritten() throws {
        let good = record(), broken = record(2)
        try store().append(good)
        try store().append(broken)
        let brokenURL = directory.appendingPathComponent("records/\(broken.id.uuidString).json")
        let damaged = Data("broken".utf8)
        try damaged.write(to: brokenURL)
        let snapshot = try store().read()
        XCTAssertEqual(snapshot.records.map(\.id), [good.id])
        XCTAssertEqual(snapshot.unreadableCount, 1)
        XCTAssertThrowsError(try store().append(broken))
        try store().append(record(3))
        XCTAssertEqual(try store().read().records.count, 2)
        XCTAssertEqual(try Data(contentsOf: brokenURL), damaged)
    }

    func testUnsupportedArchiveVersionIsNotModified() throws {
        try store().append(record())
        let index = directory.appendingPathComponent("index.json")
        let original = Data(#"{"formatVersion":999,"skippedLegacyCount":0}"#.utf8)
        try original.write(to: index)
        XCTAssertThrowsError(try store().append(record(3)))
        XCTAssertEqual(try Data(contentsOf: index), original)
    }

    func testDeleteAndClearDoNotResurrectMigratedData() throws {
        let a = record(), b = record(2)
        defaults.set(try JSONEncoder().encode([a, b]), forKey: "testRecords")
        try store().delete(id: a.id)
        XCTAssertEqual(try store().read().records.map(\.id), [b.id])
        try store().clear()
        XCTAssertTrue(try store().read().records.isEmpty)
        XCTAssertNil(defaults.object(forKey: "testRecords"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("legacy-backup.json").path))
    }

    func testUnavailableStorageReportsFailure() throws {
        try Data("a file cannot be used as a directory".utf8).write(to: directory)
        XCTAssertThrowsError(try store().append(record()))
        XCTAssertThrowsError(try store().read())
    }

    func testRecoveryExportPreservesUnreadableSourceBytes() throws {
        let raw = Data("corrupt legacy bytes".utf8)
        defaults.set(raw, forKey: "testRecords")
        _ = try? store().read()
        let data = try store().recoveryExport()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let files = try XCTUnwrap(object["files"] as? [String: String])
        XCTAssertEqual(files["legacy-backup.json"].flatMap { Data(base64Encoded: $0) }, raw)
    }
}
