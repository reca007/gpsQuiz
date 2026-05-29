import SwiftData
import SwiftUI

enum QuizAccessMode: String, CaseIterable, Identifiable {
    case teacher
    case player

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teacher:
            "Lärare"
        case .player:
            "Spelare"
        }
    }
}

struct QuizDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudQuizService: CloudQuizService
    let quiz: Quiz
    let accessMode: QuizAccessMode

    @State private var teamName = ""
    @State private var playerOneName = ""
    @State private var playerTwoName = ""
    @State private var roundToStart: GameRound?
    @State private var showingImport = false
    @State private var showingAIGenerator = false
    @State private var showingShareSheet = false

    private var checkpoints: [Checkpoint] {
        quiz.checkpoints.sorted { $0.sortIndex < $1.sortIndex }
    }

    private var mapPoints: [CourseMapPoint] {
        checkpoints.map {
            CourseMapPoint(id: $0.id, title: $0.name, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var body: some View {
        List {
            if !mapPoints.isEmpty {
                Section {
                    CourseMapPreview(
                        points: mapPoints,
                        title: quiz.title,
                        subtitle: "\(checkpoints.count) checkpoints i banan"
                    )
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(quiz.title)
                        .font(.title2.bold())
                    if !quiz.summary.isEmpty {
                        Text(quiz.summary)
                            .foregroundStyle(.secondary)
                    }
                    if accessMode == .teacher {
                        Toggle(
                            "Aktivt quiz",
                            isOn: Binding(
                                get: { quiz.isActive },
                                set: { newValue in
                                    quiz.isActive = newValue
                                    quiz.updatedAt = .now
                                    try? modelContext.save()
                                }
                            )
                        )
                    } else {
                        Label("Anslut som lag och starta rundan när läraren säger till.", systemImage: "person.2.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if accessMode == .teacher {
                if checkpoints.isEmpty {
                    Section("Dela och testa") {
                        ContentUnavailableView(
                            "Lägg till frågor först",
                            systemImage: "mappin.slash",
                            description: Text("Generera en AI-bana eller importera frågor innan banan kan testas eller delas med QR-kod.")
                        )
                    }
                } else {
                    Section("Dela och testa") {
                        Button {
                            startQuickTestRound()
                        } label: {
                            Label("Testa banan direkt", systemImage: "play.circle.fill")
                        }

                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Visa QR-kod för spelare", systemImage: "qrcode")
                        }

                        Text("Spelare ska ansluta via QR-kod eller länk. De kan inte skapa eller ändra frågor.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Lag") {
                TextField("Lagnamn", text: $teamName)
                    .textContentType(.organizationName)
                TextField("Spelare 1", text: $playerOneName)
                    .textContentType(.name)
                TextField("Spelare 2", text: $playerTwoName)
                    .textContentType(.name)
            }

            Section(accessMode == .teacher ? "Starta testrunda" : "Anslut till runda") {
                Button {
                    startRound()
                } label: {
                    Label(accessMode == .teacher ? "Starta som testlag" : "Starta som lag", systemImage: "person.2.fill")
                }
                .disabled(!canStartRound || checkpoints.isEmpty)
            }

            if accessMode == .teacher {
                Section("Render") {
                    Button {
                        Task {
                            await cloudQuizService.publish(quiz: quiz)
                        }
                    } label: {
                        Label("Publicera quiz till Render", systemImage: "network")
                    }
                    .disabled(cloudQuizService.isWorking || checkpoints.isEmpty)

                    if let message = cloudQuizService.statusMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(accessMode == .teacher ? "Checkpoints" : "Banan") {
                ForEach(checkpoints) { checkpoint in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(checkpoint.name)
                            .font(.headline)
                        if accessMode == .teacher {
                            Text(checkpoint.question)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Frågan låses upp automatiskt när laget är nära platsen.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Label("\(Int(checkpoint.activationRadiusMeters)) m aktiveringsradie", systemImage: "scope")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(accessMode == .teacher ? "Lärarvy" : "Spelarvy")
        .toolbar {
            if accessMode == .teacher {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingAIGenerator = true
                        } label: {
                            Label("Generera AI-bana", systemImage: "sparkles")
                        }

                        Button {
                            showingImport = true
                        } label: {
                            Label("Importera frågor", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Lägg till frågor")
                }
            }
        }
        .navigationDestination(item: $roundToStart) { round in
            GameView(quiz: quiz, round: round)
        }
        .sheet(isPresented: $showingImport) {
            NavigationStack {
                CheckpointImportView(quiz: quiz)
            }
        }
        .sheet(isPresented: $showingAIGenerator) {
            NavigationStack {
                AIQuizGeneratorView(quiz: quiz)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            QuizShareView(quiz: quiz)
        }
    }

    private var canStartRound: Bool {
        !teamDisplayName.isEmpty &&
        !playerOneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !playerTwoName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var teamDisplayName: String {
        let trimmedTeam = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTeam.isEmpty {
            return trimmedTeam
        }

        let first = playerOneName.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = playerTwoName.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.isEmpty || second.isEmpty {
            return ""
        }
        return "\(first) & \(second)"
    }

    private func startRound() {
        createRound(
            playerName: teamDisplayName,
            teamName: teamDisplayName,
            playerOneName: playerOneName.trimmingCharacters(in: .whitespacesAndNewlines),
            playerTwoName: playerTwoName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func startQuickTestRound() {
        let first = playerOneName.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = playerTwoName.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = teamDisplayName.isEmpty ? "Testlag" : teamDisplayName

        createRound(
            playerName: "Test: \(team)",
            teamName: team,
            playerOneName: first.isEmpty ? "Spelare 1" : first,
            playerTwoName: second.isEmpty ? "Spelare 2" : second
        )
    }

    private func createRound(playerName: String, teamName: String, playerOneName: String, playerTwoName: String) {
        let round = GameRound(
            playerName: playerName,
            quiz: quiz,
            teamName: teamName,
            playerOneName: playerOneName,
            playerTwoName: playerTwoName
        )
        modelContext.insert(round)
        try? modelContext.save()
        roundToStart = round
    }
}
