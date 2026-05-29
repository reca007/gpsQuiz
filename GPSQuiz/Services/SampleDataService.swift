import Foundation
import SwiftData

enum SampleDataService {
    @MainActor
    static func seedIfNeeded(existingQuizzes: [Quiz], modelContext: ModelContext) {
        guard existingQuizzes.isEmpty else { return }

        let quiz = Quiz(
            title: "Demo: Södermalm GPSQuiz",
            summary: "Ett kort testquiz med tre GPS-punkter i Stockholm."
        )

        let rows = [
            CheckpointImportRow(
                name: "Mariatorget",
                latitude: 59.3189,
                longitude: 18.0634,
                radius: 80,
                question: "Vilken stadsdel ligger Mariatorget i?",
                options: ["Södermalm", "Norrmalm", "Kungsholmen"],
                correctAnswer: "Södermalm"
            ),
            CheckpointImportRow(
                name: "Medborgarplatsen",
                latitude: 59.3148,
                longitude: 18.0737,
                radius: 80,
                question: "Vad kallas platsen ofta i folkmun?",
                options: ["Medis", "Plattan", "Nytan"],
                correctAnswer: "Medis"
            ),
            CheckpointImportRow(
                name: "Tantolunden",
                latitude: 59.3112,
                longitude: 18.0466,
                radius: 100,
                question: "Vilken typ av område är Tantolunden mest känt som?",
                options: ["Park", "Flygplats", "Köpcentrum"],
                correctAnswer: "Park"
            )
        ]

        for (index, row) in rows.enumerated() {
            let checkpoint = Checkpoint(
                name: row.name,
                latitude: row.latitude,
                longitude: row.longitude,
                activationRadiusMeters: row.radius,
                question: row.question,
                sortIndex: index
            )
            checkpoint.quiz = quiz

            for (optionIndex, optionText) in row.options.enumerated() {
                let option = AnswerOption(
                    text: optionText,
                    sortIndex: optionIndex,
                    isCorrect: optionText == row.correctAnswer
                )
                option.checkpoint = checkpoint
                checkpoint.options.append(option)
            }

            quiz.checkpoints.append(checkpoint)
        }

        modelContext.insert(quiz)
        try? modelContext.save()
    }
}
