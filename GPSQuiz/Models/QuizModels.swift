import Foundation
import SwiftData

@Model
final class Quiz {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Checkpoint.quiz)
    var checkpoints: [Checkpoint]

    init(title: String, summary: String = "", isActive: Bool = true) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.isActive = isActive
        self.createdAt = .now
        self.updatedAt = .now
        self.checkpoints = []
    }
}

@Model
final class Checkpoint {
    @Attribute(.unique) var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var activationRadiusMeters: Double
    var question: String
    var sortIndex: Int

    var quiz: Quiz?

    @Relationship(deleteRule: .cascade, inverse: \AnswerOption.checkpoint)
    var options: [AnswerOption]

    init(
        name: String,
        latitude: Double,
        longitude: Double,
        activationRadiusMeters: Double,
        question: String,
        sortIndex: Int
    ) {
        self.id = UUID()
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.activationRadiusMeters = activationRadiusMeters
        self.question = question
        self.sortIndex = sortIndex
        self.options = []
    }
}

@Model
final class AnswerOption {
    @Attribute(.unique) var id: UUID
    var text: String
    var sortIndex: Int
    var isCorrect: Bool

    var checkpoint: Checkpoint?

    init(text: String, sortIndex: Int, isCorrect: Bool = false) {
        self.id = UUID()
        self.text = text
        self.sortIndex = sortIndex
        self.isCorrect = isCorrect
    }
}

@Model
final class GameRound {
    @Attribute(.unique) var id: UUID
    var playerName: String
    var teamName: String = ""
    var playerOneName: String = ""
    var playerTwoName: String = ""
    var startedAt: Date
    var completedAt: Date?
    var submittedToLeaderboardAt: Date?
    var quizID: UUID
    var quizTitleSnapshot: String

    var quiz: Quiz?

    @Relationship(deleteRule: .cascade, inverse: \QuestionResponse.round)
    var responses: [QuestionResponse]

    init(playerName: String, quiz: Quiz, teamName: String? = nil, playerOneName: String = "", playerTwoName: String = "") {
        self.id = UUID()
        self.playerName = playerName
        self.teamName = teamName ?? playerName
        self.playerOneName = playerOneName
        self.playerTwoName = playerTwoName
        self.startedAt = .now
        self.quizID = quiz.id
        self.quizTitleSnapshot = quiz.title
        self.quiz = quiz
        self.responses = []
    }

    var totalSeconds: TimeInterval {
        (completedAt ?? .now).timeIntervalSince(startedAt)
    }

    var correctCount: Int {
        responses.filter(\.isCorrect).count
    }

    var isComplete: Bool {
        completedAt != nil
    }
}

@Model
final class QuestionResponse {
    @Attribute(.unique) var id: UUID
    var checkpointID: UUID
    var checkpointNameSnapshot: String
    var selectedOptionID: UUID
    var selectedOptionTextSnapshot: String
    var correctOptionID: UUID
    var isCorrect: Bool
    var unlockedAt: Date
    var answeredAt: Date
    var distanceAtUnlockMeters: Double

    var round: GameRound?

    init(
        checkpoint: Checkpoint,
        selectedOption: AnswerOption,
        correctOption: AnswerOption,
        unlockedAt: Date,
        distanceAtUnlockMeters: Double
    ) {
        self.id = UUID()
        self.checkpointID = checkpoint.id
        self.checkpointNameSnapshot = checkpoint.name
        self.selectedOptionID = selectedOption.id
        self.selectedOptionTextSnapshot = selectedOption.text
        self.correctOptionID = correctOption.id
        self.isCorrect = selectedOption.id == correctOption.id
        self.unlockedAt = unlockedAt
        self.answeredAt = .now
        self.distanceAtUnlockMeters = distanceAtUnlockMeters
    }
}

struct CheckpointImportRow: Identifiable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let question: String
    let options: [String]
    let correctAnswer: String
}
