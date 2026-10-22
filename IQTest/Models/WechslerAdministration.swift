import Foundation

/// 施测方式与偏离记录；不把过程记录包装成已验证的效度指标。
struct WechslerAdministration: Codable {
    struct Interruption: Codable {
        enum Stage: String, Codable { case stimulus, question }
        let itemID: String
        let stage: Stage
        let inactiveSeconds: Double
    }
    let protocolVersion: String
    let completedTutorials: [WechslerSubtest]
    let hasPriorExposure: Bool
    let interruptions: [Interruption]
}
