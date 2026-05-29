import SwiftData
import SwiftUI

struct QuizDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var cloudQuizService: CloudQuizService
    let quiz: Quiz

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
                }
            }

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
                        Label("Visa QR-kod", systemImage: "qrcode")
                    }

                    Text("Snabbtest skapar ett tillfälligt testlag om du inte fyllt i spelarnamn ännu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

            Section("Starta runda") {
                Button {
                    startRound()
                } label: {
                    Label("Starta som lag", systemImage: "person.2.fill")
                }
                .disabled(!canStartRound || checkpoints.isEmpty)
            }

            Section("Moln") {
                Button {
                    Task {
                        await cloudQuizService.publish(quiz: quiz)
                    }
                } label: {
                    Label("Publicera quiz", systemImage: "icloud.and.arrow.up")
                }
                .disabled(cloudQuizService.isWorking || checkpoints.isEmpty)

                if let message = cloudQuizService.statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Checkpoints") {
                ForEach(checkpoints) { checkpoint in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(checkpoint.name)
                            .font(.headline)
                        Text(checkpoint.question)
                            .foregroundStyle(.secondary)
                        Label("\(Int(checkpoint.activationRadiusMeters)) m aktiveringsradie", systemImage: "scope")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Quizdetaljer")
        .toolbar {
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
