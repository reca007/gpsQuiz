import SwiftData
import SwiftUI

@main
struct GPSQuizApp: App {
    @StateObject private var locationService = LocationService()
    @StateObject private var leaderboardService = LeaderboardService()
    @StateObject private var cloudQuizService = CloudQuizService()
    @StateObject private var intentRouter = IntentRouter()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Quiz.self,
            Checkpoint.self,
            AnswerOption.self,
            GameRound.self,
            QuestionResponse.self
        ])

        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationService)
                .environmentObject(leaderboardService)
                .environmentObject(cloudQuizService)
                .environmentObject(intentRouter)
                .onOpenURL { url in
                    intentRouter.handle(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
