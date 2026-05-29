import Foundation
import Combine

enum AppTab: Hashable {
    case quizzes
    case leaderboard
}

final class IntentRouter: ObservableObject {
    @Published var selectedTab: AppTab = .quizzes
    @Published var shouldStartQuiz = false
    @Published var requestedQuizID: UUID?
    @Published var sharedQuizPayload: SharedQuizPayload?

    func handle(_ url: URL) {
        guard url.scheme == "gpsquiz" else { return }

        switch url.host() {
        case "start":
            selectedTab = .quizzes
            shouldStartQuiz = true
        case "leaderboard":
            selectedTab = .leaderboard
        case "quiz":
            selectedTab = .quizzes
            requestedQuizID = Self.quizID(from: url)
        case "import":
            selectedTab = .quizzes
            sharedQuizPayload = Self.sharedPayload(from: url)
        default:
            break
        }
    }

    private static func quizID(from url: URL) -> UUID? {
        if let id = url.pathComponents.dropFirst().first, let uuid = UUID(uuidString: id) {
            return uuid
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let id = components?.queryItems?.first(where: { $0.name == "id" })?.value
        return id.flatMap(UUID.init(uuidString:))
    }

    private static func sharedPayload(from url: URL) -> SharedQuizPayload? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let token = components?.queryItems?.first(where: { $0.name == "data" })?.value else {
            return nil
        }
        return SharedQuizPayload.decode(from: token)
    }
}

struct SharedQuizPayload: Codable, Equatable {
    var quizID: UUID?
    var title: String
    var summary: String
    var checkpoints: [SharedCheckpointPayload]

    init(quiz: Quiz) {
        quizID = quiz.id
        title = quiz.title
        summary = quiz.summary
        checkpoints = quiz.checkpoints
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(SharedCheckpointPayload.init)
    }

    static func importURL(for quiz: Quiz) -> URL? {
        let payload = SharedQuizPayload(quiz: quiz)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let token = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents()
        components.scheme = "gpsquiz"
        components.host = "import"
        components.queryItems = [URLQueryItem(name: "data", value: token)]
        return components.url
    }

    static func decode(from token: String) -> SharedQuizPayload? {
        var base64 = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(SharedQuizPayload.self, from: data)
    }
}

struct SharedCheckpointPayload: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var question: String
    var options: [SharedAnswerPayload]

    init(checkpoint: Checkpoint) {
        name = checkpoint.name
        latitude = checkpoint.latitude
        longitude = checkpoint.longitude
        radius = checkpoint.activationRadiusMeters
        question = checkpoint.question
        options = checkpoint.options
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(SharedAnswerPayload.init)
    }
}

struct SharedAnswerPayload: Codable, Equatable {
    var text: String
    var isCorrect: Bool

    init(option: AnswerOption) {
        text = option.text
        isCorrect = option.isCorrect
    }
}
