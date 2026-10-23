import Foundation

/// 记录每个题库里已经做过的题目。
///
/// 一次完整练习后，同一题池里的题就不该再被抽到：重复出题既让「多次测量」失去意义，
/// 也会让复测分数混入练习效应（看过解析再遇到同一题，分数必然虚高）。
/// 这里按题库分别记录题号，抽题时优先选未做过的；未做过的题不够时用做过的题补足，
/// 保证每轮题量恒定——题量一变，同一轮的得分率分母就变了，不同轮次的成绩无法比较。
enum ItemExposureStore {
    private static let keyPrefix = "seenItemIDs."

    /// 题池的标识。不同题组、题型与难度分别记录，避免互相干扰。
    static func bankKey(_ components: String...) -> String {
        keyPrefix + components.joined(separator: ".")
    }

    /// 某题池里已经做过的题号。
    static func seen(for key: String) -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    /// 把本次做过的题号并入记录。已存在的题号不重复写入。
    static func markSeen(_ itemIDs: [String], for key: String) {
        guard !itemIDs.isEmpty else { return }
        var merged = seen(for: key)
        merged.formUnion(itemIDs)
        // 排序后编码，保证同样的记录集合产生同样的存储内容，便于排查。
        let ids = merged.sorted()
        guard let data = try? JSONEncoder().encode(ids) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 清空某题池的记录，让下一轮重新从全部题目中抽取。
    static func reset(for key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// 该题库里是否已经记录过做过的题。用于界面提示。
    static func hasRecord(for key: String) -> Bool {
        !seen(for: key).isEmpty
    }
}
