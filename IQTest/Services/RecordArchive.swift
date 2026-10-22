import Foundation

/// 由主线程串行调用；每条成绩独立原子写入，读取损坏项不覆盖原文件。
final class RecordArchive {
    struct Snapshot {
        let records: [TestRecord]
        let unreadableCount: Int
        let hasLegacyBackup: Bool
    }
    private struct Index: Codable {
        var formatVersion = 1
        var skippedLegacyCount = 0
    }
    private struct Migration: Codable {
        let records: [TestRecord]
        let skippedCount: Int
    }
    enum ArchiveError: LocalizedError {
        case corruptLegacy, unsupportedVersion, conflict, changedLegacy
        var errorDescription: String? {
            switch self {
            case .corruptLegacy: return "旧历史无法读取，原始数据已保留。可先导出原始备份。"
            case .unsupportedVersion: return "历史格式无法识别，请使用支持该格式的应用版本。"
            case .conflict: return "存在同编号但内容不同的记录，原文件未被覆盖。"
            case .changedLegacy: return "迁移中的旧历史发生变化，已保留两份数据，请先导出原始备份。"
            }
        }
    }

    private let directory: URL
    private let legacyDefaults: UserDefaults
    private let files: FileManager
    private let write: (Data, URL) throws -> Void
    private var recordsURL: URL { directory.appendingPathComponent("records", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var backupURL: URL { directory.appendingPathComponent("legacy-backup.json") }
    private var migrationURL: URL { directory.appendingPathComponent("migration-prepared.json") }

    init(directory: URL, legacyDefaults: UserDefaults = .standard, files: FileManager = .default,
         write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.directory = directory
        self.legacyDefaults = legacyDefaults
        self.files = files
        self.write = write
    }

    func read() throws -> Snapshot {
        let index = try migrateIfNeeded()
        var records: [TestRecord] = []
        var unreadable = index.skippedLegacyCount
        for url in try files.contentsOfDirectory(at: recordsURL, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            do {
                let record = try JSONDecoder().decode(TestRecord.self, from: Data(contentsOf: url))
                guard record.id.uuidString == url.deletingPathExtension().lastPathComponent else {
                    throw ArchiveError.conflict
                }
                records.append(record)
            } catch { unreadable += 1 }
        }
        records.sort { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        return Snapshot(records: records, unreadableCount: unreadable,
                        hasLegacyBackup: files.fileExists(atPath: backupURL.path)
                            || files.fileExists(atPath: migrationURL.path)
                            || legacyDefaults.object(forKey: "testRecords") != nil)
    }

    func append(_ record: TestRecord) throws {
        _ = try migrateIfNeeded()
        try writeRecord(record)
    }

    func delete(id: UUID) throws {
        _ = try migrateIfNeeded()
        let url = recordsURL.appendingPathComponent(id.uuidString + ".json")
        if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
    }

    func clear() throws {
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        if files.fileExists(atPath: recordsURL.path) { try files.removeItem(at: recordsURL) }
        try files.createDirectory(at: recordsURL, withIntermediateDirectories: true)
        // 先提交空索引，再清理迁移备份，防止旧偏好数据重新出现。
        try write(encode(Index()), indexURL)
        for url in [migrationURL, backupURL] where files.fileExists(atPath: url.path) {
            try files.removeItem(at: url)
        }
        legacyDefaults.removeObject(forKey: "testRecords")
    }

    /// 原始字节用 Base64 包装；损坏内容也能导出，不必先成功解码。
    func recoveryExport() throws -> Data {
        var contents: [String: String] = [:]
        if let legacy = legacyDefaults.data(forKey: "testRecords") {
            contents["userdefaults-testRecords.json"] = legacy.base64EncodedString()
        }
        if files.fileExists(atPath: directory.path) {
            for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                if url.lastPathComponent == "records" {
                    for recordURL in try files.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        contents["records/" + recordURL.lastPathComponent] = try Data(contentsOf: recordURL).base64EncodedString()
                    }
                } else {
                    contents[url.lastPathComponent] = try Data(contentsOf: url).base64EncodedString()
                }
            }
        }
        return try JSONSerialization.data(withJSONObject: ["formatVersion": 1, "kind": "raw-history-backup", "files": contents], options: [.prettyPrinted, .sortedKeys])
    }

    private func migrateIfNeeded() throws -> Index {
        try files.createDirectory(at: recordsURL, withIntermediateDirectories: true)
        if files.fileExists(atPath: indexURL.path) {
            let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
            guard index.formatVersion == 1, index.skippedLegacyCount >= 0 else { throw ArchiveError.unsupportedVersion }
            return index
        }
        let raw = legacyDefaults.data(forKey: "testRecords")
        let migration: Migration
        if files.fileExists(atPath: migrationURL.path) {
            if let raw, try Data(contentsOf: backupURL) != raw { throw ArchiveError.changedLegacy }
            migration = try JSONDecoder().decode(Migration.self, from: Data(contentsOf: migrationURL))
        } else if let raw {
            if files.fileExists(atPath: backupURL.path) {
                guard try Data(contentsOf: backupURL) == raw else { throw ArchiveError.changedLegacy }
            } else { try write(raw, backupURL) }
            guard let rows = try? JSONSerialization.jsonObject(with: raw) as? [Any] else {
                throw ArchiveError.corruptLegacy
            }
            var records: [TestRecord] = []
            var ids: Set<UUID> = []
            var skipped = 0
            for row in rows {
                do {
                    let data = try JSONSerialization.data(withJSONObject: row, options: .fragmentsAllowed)
                    let record = try JSONDecoder().decode(TestRecord.self, from: data)
                    guard ids.insert(record.id).inserted else { skipped += 1; continue }
                    records.append(record)
                } catch { skipped += 1 }
            }
            migration = Migration(records: records, skippedCount: skipped)
            // 在逐条落盘前固定旧记录缺失的 UUID；中途失败后继续使用相同题次。
            try write(encode(migration), migrationURL)
        } else {
            let index = Index()
            try write(encode(index), indexURL)
            return index
        }
        for record in migration.records { try writeRecord(record) }
        let index = Index(skippedLegacyCount: migration.skippedCount)
        try write(encode(index), indexURL)
        return index
    }

    private func writeRecord(_ record: TestRecord) throws {
        let url = recordsURL.appendingPathComponent(record.id.uuidString + ".json")
        let data = try encode(record)
        if files.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == data else { throw ArchiveError.conflict }
            return
        }
        try write(data, url)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
}

@MainActor
enum RecordStore {
    private static func archive() throws -> RecordArchive {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        return RecordArchive(directory: root.appendingPathComponent("IQTestHistory", isDirectory: true))
    }
    static func read() throws -> RecordArchive.Snapshot { try archive().read() }
    static func load() throws -> [TestRecord] { try read().records }
    static func append(_ record: TestRecord) throws { try archive().append(record) }
    static func delete(id: UUID) throws { try archive().delete(id: id) }
    static func clear() throws { try archive().clear() }
    static func recoveryExport() throws -> Data { try archive().recoveryExport() }
}
