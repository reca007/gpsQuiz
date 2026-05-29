import Combine
import Foundation

struct LeaderboardEntry: Identifiable, Hashable, Decodable {
    let id: String
    let quizID: UUID
    let quizTitle: String
    let playerName: String
    let correctCount: Int
    let totalSeconds: TimeInterval
    let completedAt: Date

    static func < (lhs: LeaderboardEntry, rhs: LeaderboardEntry) -> Bool {
        if lhs.correctCount != rhs.correctCount {
            return lhs.correctCount > rhs.correctCount
        }
        return lhs.totalSeconds < rhs.totalSeconds
    }
}

@MainActor
final class LeaderboardService: ObservableObject {
    @Published private(set) var entries: [LeaderboardEntry] = []
    @Published private(set) var isOffline = false
    @Published private(set) var statusMessage: String?

    func refresh(quizID: UUID? = nil) async {
        guard let backendURL = BackendConfig.url("api/leaderboard") else {
            isOffline = true
            statusMessage = "Render-URL saknas. Topplistan visas lokalt."
            return
        }

        do {
            var components = URLComponents(url: backendURL, resolvingAgainstBaseURL: false)
            if let quizID {
                components?.queryItems = [URLQueryItem(name: "quizID", value: quizID.uuidString)]
            }

            guard let url = components?.url else { throw BackendLeaderboardError.unavailable }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                throw BackendLeaderboardError.unavailable
            }

            let payload = try JSONDecoder().decode(BackendLeaderboardList.self, from: data)
            entries = payload.entries.sorted(by: <)
            isOffline = false
            statusMessage = entries.isEmpty ? "Ingen gemensam topplista ännu." : nil
        } catch {
            isOffline = true
            statusMessage = "Kunde inte hämta Render-topplistan."
        }
    }

    func submit(round: GameRound) async {
        guard let completedAt = round.completedAt else { return }
        guard let backendURL = BackendConfig.url("api/leaderboard") else {
            isOffline = true
            statusMessage = "Render-URL saknas. Resultatet sparades lokalt."
            return
        }

        do {
            var request = URLRequest(url: backendURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(BackendLeaderboardSubmission(round: round, completedAt: completedAt))

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                throw BackendLeaderboardError.unavailable
            }

            round.submittedToLeaderboardAt = .now
            isOffline = false
            statusMessage = "Resultatet är uppladdat till Render."
            await refresh(quizID: round.quizID)
        } catch {
            isOffline = true
            statusMessage = "Resultatet sparades lokalt och kan skickas igen senare."
        }
    }
}

private struct BackendLeaderboardList: Decodable {
    let entries: [LeaderboardEntry]
}

private struct BackendLeaderboardSubmission: Encodable {
    let id: String
    let quizID: UUID
    let quizTitle: String
    let playerName: String
    let correctCount: Int
    let totalSeconds: TimeInterval
    let completedAt: Date

    init(round: GameRound, completedAt: Date) {
        id = round.id.uuidString
        quizID = round.quizID
        quizTitle = round.quizTitleSnapshot
        playerName = round.playerName
        correctCount = round.correctCount
        totalSeconds = round.totalSeconds
        self.completedAt = completedAt
    }
}

private enum BackendLeaderboardError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Servern svarade inte korrekt."
    }
}
