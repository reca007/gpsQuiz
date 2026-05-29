import SwiftUI

struct ResultView: View {
    @EnvironmentObject private var leaderboardService: LeaderboardService
    let round: GameRound
    let questionCount: Int

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rundan är klar")
                        .font(.title.bold())
                    Text(round.playerName)
                        .foregroundStyle(.secondary)
                    HStack {
                        ResultMetric(title: "Rätt", value: "\(round.correctCount)/\(questionCount)")
                        ResultMetric(title: "Tid", value: TimeFormatter.minutesAndSeconds(round.totalSeconds))
                    }
                }
            }

            if let message = leaderboardService.statusMessage {
                Section {
                    Label(message, systemImage: leaderboardService.isOffline ? "wifi.slash" : "network")
                }
            }

            Section("Svar") {
                ForEach(round.responses.sorted { $0.answeredAt < $1.answeredAt }) { response in
                    HStack {
                        Image(systemName: response.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(response.isCorrect ? .green : .red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(response.checkpointNameSnapshot)
                            Text(response.selectedOptionTextSnapshot)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(response.answeredAt, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Resultat")
        .task {
            await leaderboardService.submit(round: round)
        }
    }
}

private struct ResultMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
