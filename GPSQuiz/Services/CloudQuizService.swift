import Combine
import Foundation
import SwiftData

@MainActor
final class CloudQuizService: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?

    func publish(quiz: Quiz) async {
        guard let backendURL = BackendConfig.url("api/quizzes") else {
            statusMessage = "Render-URL saknas. Quizet är kvar lokalt."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            var request = URLRequest(url: backendURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(SharedQuizPayload(quiz: quiz))

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                throw BackendError.unavailable
            }

            statusMessage = "Quizet är publicerat till Render."
        } catch {
            statusMessage = "Kunde inte publicera till Render: \(error.localizedDescription)"
        }
    }

    func importPublishedQuizzes(into modelContext: ModelContext, existingQuizIDs: Set<UUID>) async {
        guard let backendURL = BackendConfig.url("api/quizzes") else {
            statusMessage = "Render-URL saknas."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: backendURL)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                throw BackendError.unavailable
            }

            let payload = try JSONDecoder().decode(BackendQuizList.self, from: data)
            var importedCount = 0

            for sharedQuiz in payload.quizzes {
                if let quizID = sharedQuiz.quizID, existingQuizIDs.contains(quizID) {
                    continue
                }

                let quiz = Quiz(title: sharedQuiz.title, summary: sharedQuiz.summary, isActive: true)
                if let quizID = sharedQuiz.quizID {
                    quiz.id = quizID
                }
                appendSharedCheckpoints(sharedQuiz.checkpoints, to: quiz)
                modelContext.insert(quiz)
                importedCount += 1
            }

            try modelContext.save()
            statusMessage = importedCount == 0 ? "Inga nya Render-quiz hittades." : "\(importedCount) quiz hämtades från Render."
        } catch {
            statusMessage = "Kunde inte hämta från Render: \(error.localizedDescription)"
        }
    }

    private func appendSharedCheckpoints(_ checkpoints: [SharedCheckpointPayload], to quiz: Quiz) {
        for (checkpointIndex, checkpointPayload) in checkpoints.enumerated() {
            let checkpoint = Checkpoint(
                name: checkpointPayload.name,
                latitude: checkpointPayload.latitude,
                longitude: checkpointPayload.longitude,
                activationRadiusMeters: checkpointPayload.radius,
                question: checkpointPayload.question,
                sortIndex: checkpointIndex
            )
            checkpoint.quiz = quiz

            for (optionIndex, optionPayload) in checkpointPayload.options.enumerated() {
                let option = AnswerOption(
                    text: optionPayload.text,
                    sortIndex: optionIndex,
                    isCorrect: optionPayload.isCorrect
                )
                option.checkpoint = checkpoint
                checkpoint.options.append(option)
            }

            quiz.checkpoints.append(checkpoint)
        }
    }
}

private struct BackendQuizList: Decodable {
    let quizzes: [SharedQuizPayload]
}

private enum BackendError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Servern svarade inte korrekt."
    }
}
