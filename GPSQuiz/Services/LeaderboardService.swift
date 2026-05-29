import Combine
import CloudKit
import Foundation

struct LeaderboardEntry: Identifiable, Hashable {
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

    private let recordType = "LeaderboardEntry"

    func refresh(quizID: UUID? = nil) async {
        if let backendURL = BackendConfig.url("api/leaderboard") {
            await refreshWithBackend(endpoint: backendURL, quizID: quizID)
            return
        }

        guard let database = cloudDatabase else {
            isOffline = true
            statusMessage = "Topplistan är i lokalt testläge. CloudKit kräver ett betalt Apple Developer-konto."
            return
        }

        do {
            let predicate: NSPredicate
            if let quizID {
                predicate = NSPredicate(format: "quizID == %@", quizID.uuidString)
            } else {
                predicate = NSPredicate(value: true)
            }

            let query = CKQuery(recordType: recordType, predicate: predicate)
            query.sortDescriptors = [
                NSSortDescriptor(key: "correctCount", ascending: false),
                NSSortDescriptor(key: "totalSeconds", ascending: true)
            ]

            let result = try await database.records(matching: query, resultsLimit: 50)
            entries = result.matchResults.compactMap { _, value in
                guard case let .success(record) = value else { return nil }
                return LeaderboardEntry(record: record)
            }.sorted(by: <)
            isOffline = false
            statusMessage = entries.isEmpty ? "Ingen topplista ännu." : nil
        } catch {
            isOffline = true
            statusMessage = "Topplistan visas lokalt tills nätet eller iCloud fungerar igen."
        }
    }

    func submit(round: GameRound) async {
        guard let completedAt = round.completedAt else { return }
        if let backendURL = BackendConfig.url("api/leaderboard") {
            await submitWithBackend(round: round, completedAt: completedAt, endpoint: backendURL)
            return
        }

        guard let database = cloudDatabase else {
            isOffline = true
            statusMessage = "Resultatet sparades lokalt. CloudKit kräver ett betalt Apple Developer-konto."
            return
        }

        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: round.id.uuidString))
        record["quizID"] = round.quizID.uuidString
        record["quizTitle"] = round.quizTitleSnapshot
        record["playerName"] = round.playerName
        record["correctCount"] = NSNumber(value: round.correctCount)
        record["totalSeconds"] = NSNumber(value: round.totalSeconds)
        record["completedAt"] = completedAt

        do {
            _ = try await database.save(record)
            round.submittedToLeaderboardAt = .now
            isOffline = false
            statusMessage = "Resultatet är uppladdat."
            await refresh(quizID: round.quizID)
        } catch {
            isOffline = true
            statusMessage = "Resultatet sparades lokalt och kan skickas igen senare."
        }
    }

    private func refreshWithBackend(endpoint: URL, quizID: UUID?) async {
        do {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
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

    private func submitWithBackend(round: GameRound, completedAt: Date, endpoint: URL) async {
        do {
            var request = URLRequest(url: endpoint)
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

    private var cloudDatabase: CKDatabase? {
        #if DEBUG
        return nil
        #else
        CKContainer.default().publicCloudDatabase
        #endif
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

private extension LeaderboardEntry {
    init?(record: CKRecord) {
        guard
            let quizIDText = record["quizID"] as? String,
            let quizID = UUID(uuidString: quizIDText),
            let quizTitle = record["quizTitle"] as? String,
            let playerName = record["playerName"] as? String,
            let correctCount = record["correctCount"] as? NSNumber,
            let totalSeconds = record["totalSeconds"] as? NSNumber,
            let completedAt = record["completedAt"] as? Date
        else {
            return nil
        }

        self.id = record.recordID.recordName
        self.quizID = quizID
        self.quizTitle = quizTitle
        self.playerName = playerName
        self.correctCount = correctCount.intValue
        self.totalSeconds = totalSeconds.doubleValue
        self.completedAt = completedAt
    }
}
