import Foundation

enum QuestionLoader {
    static func load() -> [Question] {
        guard let url = Bundle.main.url(forResource: "Questions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("Questions.json not found in bundle")
            return []
        }
        do {
            return try JSONDecoder().decode([Question].self, from: data)
        } catch {
            assertionFailure("Failed to decode Questions.json: \(error)")
            return []
        }
    }
}
