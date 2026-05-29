import SwiftData
import SwiftUI

struct LeaderboardView: View {
    @EnvironmentObject private var leaderboardService: LeaderboardService
    @Query(sort: \GameRound.startedAt, order: .reverse) private var rounds: [GameRound]

    private var localCompletedRounds: [GameRound] {
        rounds
            .filter(\.isComplete)
            .sorted {
                if $0.correctCount != $1.correctCount {
                    return $0.correctCount > $1.correctCount
                }
                return $0.totalSeconds < $1.totalSeconds
            }
    }

    var body: some View {
        List {
            if let message = leaderboardService.statusMessage {
                Section {
                    Label(message, systemImage: leaderboardService.isOffline ? "wifi.slash" : "icloud")
                }
            }

            Section("Gemensam topplista") {
                if leaderboardService.entries.isEmpty {
                    ContentUnavailableView("Ingen topplista", systemImage: "trophy", description: Text("Slutför en runda för att lägga upp ett resultat."))
                } else {
                    ForEach(Array(leaderboardService.entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardEntryRow(rank: index + 1, name: entry.playerName, quizTitle: entry.quizTitle, correctCount: entry.correctCount, seconds: entry.totalSeconds)
                    }
                }
            }

            Section("Lokala resultat") {
                ForEach(Array(localCompletedRounds.enumerated()), id: \.element.id) { index, round in
                    LeaderboardEntryRow(rank: index + 1, name: round.playerName, quizTitle: round.quizTitleSnapshot, correctCount: round.correctCount, seconds: round.totalSeconds)
                }
            }
        }
        .navigationTitle("Topplista")
        .refreshable {
            await leaderboardService.refresh()
        }
        .task {
            await leaderboardService.refresh()
        }
    }
}

private struct LeaderboardEntryRow: View {
    let rank: Int
    let name: String
    let quizTitle: String
    let correctCount: Int
    let seconds: TimeInterval

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("#\(rank)")
                .font(.headline.monospacedDigit())
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                Text(quizTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(correctCount) rätt")
                    .font(.subheadline.bold())
                Text(TimeFormatter.minutesAndSeconds(seconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
