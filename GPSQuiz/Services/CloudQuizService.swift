import CloudKit
import Combine
import Foundation
import SwiftData

@MainActor
final class CloudQuizService: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?

    private let quizRecordType = "CloudQuiz"
    private let checkpointRecordType = "CloudCheckpoint"

    func publish(quiz: Quiz) async {
        guard let database = cloudDatabase else {
            statusMessage = "Molnpublicering kräver ett betalt Apple Developer-konto. Quizet är kvar lokalt."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let quizRecord = CKRecord(recordType: quizRecordType, recordID: CKRecord.ID(recordName: quiz.id.uuidString))
            quizRecord["quizID"] = quiz.id.uuidString
            quizRecord["title"] = quiz.title
            quizRecord["summary"] = quiz.summary
            quizRecord["updatedAt"] = quiz.updatedAt
            _ = try await database.save(quizRecord)

            for checkpoint in quiz.checkpoints {
                let record = CKRecord(recordType: checkpointRecordType, recordID: CKRecord.ID(recordName: checkpoint.id.uuidString))
                record["quizID"] = quiz.id.uuidString
                record["name"] = checkpoint.name
                record["latitude"] = NSNumber(value: checkpoint.latitude)
                record["longitude"] = NSNumber(value: checkpoint.longitude)
                record["activationRadiusMeters"] = NSNumber(value: checkpoint.activationRadiusMeters)
                record["question"] = checkpoint.question
                record["sortIndex"] = NSNumber(value: checkpoint.sortIndex)
                record["options"] = checkpoint.options.sorted { $0.sortIndex < $1.sortIndex }.map(\.text)
                record["correctAnswer"] = checkpoint.options.first(where: \.isCorrect)?.text ?? ""
                _ = try await database.save(record)
            }

            statusMessage = "Quizet är publicerat i molnet."
        } catch {
            statusMessage = "Kunde inte publicera quizet: \(error.localizedDescription)"
        }
    }

    func importPublishedQuizzes(into modelContext: ModelContext, existingQuizIDs: Set<UUID>) async {
        guard let database = cloudDatabase else {
            statusMessage = "Molnhämtning kräver ett betalt Apple Developer-konto."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let query = CKQuery(recordType: quizRecordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            let result = try await database.records(matching: query, resultsLimit: 50)
            var importedCount = 0

            for match in result.matchResults {
                guard case let .success(record) = match.1,
                      let quizIDText = record["quizID"] as? String,
                      let quizID = UUID(uuidString: quizIDText),
                      !existingQuizIDs.contains(quizID),
                      let title = record["title"] as? String else {
                    continue
                }

                let quiz = Quiz(title: title, summary: record["summary"] as? String ?? "")
                quiz.id = quizID
                quiz.updatedAt = record["updatedAt"] as? Date ?? .now
                try await appendCloudCheckpoints(to: quiz, quizID: quizID, database: database)
                modelContext.insert(quiz)
                importedCount += 1
            }

            try modelContext.save()
            statusMessage = importedCount == 0 ? "Inga nya molnquiz hittades." : "\(importedCount) quiz hämtades från molnet."
        } catch {
            statusMessage = "Kunde inte hämta molnquiz: \(error.localizedDescription)"
        }
    }

    private func appendCloudCheckpoints(to quiz: Quiz, quizID: UUID, database: CKDatabase) async throws {
        let query = CKQuery(
            recordType: checkpointRecordType,
            predicate: NSPredicate(format: "quizID == %@", quizID.uuidString)
        )
        query.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true)]
        let result = try await database.records(matching: query, resultsLimit: 100)

        for match in result.matchResults {
            guard case let .success(record) = match.1,
                  let name = record["name"] as? String,
                  let latitude = record["latitude"] as? NSNumber,
                  let longitude = record["longitude"] as? NSNumber,
                  let radius = record["activationRadiusMeters"] as? NSNumber,
                  let question = record["question"] as? String,
                  let sortIndex = record["sortIndex"] as? NSNumber,
                  let options = record["options"] as? [String],
                  let correctAnswer = record["correctAnswer"] as? String else {
                continue
            }

            let checkpoint = Checkpoint(
                name: name,
                latitude: latitude.doubleValue,
                longitude: longitude.doubleValue,
                activationRadiusMeters: radius.doubleValue,
                question: question,
                sortIndex: sortIndex.intValue
            )
            checkpoint.quiz = quiz

            for (optionIndex, optionText) in options.enumerated() {
                let option = AnswerOption(
                    text: optionText,
                    sortIndex: optionIndex,
                    isCorrect: optionText == correctAnswer
                )
                option.checkpoint = checkpoint
                checkpoint.options.append(option)
            }

            quiz.checkpoints.append(checkpoint)
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
