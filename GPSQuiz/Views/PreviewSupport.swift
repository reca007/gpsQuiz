import SwiftData
import SwiftUI

enum PreviewSupport {
    @MainActor
    static var modelContainer: ModelContainer = {
        let schema = Schema([
            Quiz.self,
            Checkpoint.self,
            AnswerOption.self,
            GameRound.self,
            QuestionResponse.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        SampleDataService.seedIfNeeded(existingQuizzes: [], modelContext: container.mainContext)
        return container
    }()
}
