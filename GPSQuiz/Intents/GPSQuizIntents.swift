import AppIntents
import Foundation

struct StartQuizIntent: AppIntent {
    static var title: LocalizedStringResource = "Starta quiz"
    static var description = IntentDescription("Öppnar GPSQuiz så att spelaren kan välja ett aktivt quiz och starta rundan.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "gpsquiz://start")!))
    }
}

struct ShowLeaderboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Visa topplista"
    static var description = IntentDescription("Öppnar GPSQuiz på topplistan.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "gpsquiz://leaderboard")!))
    }
}

struct GPSQuizShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartQuizIntent(),
            phrases: [
                "Starta quiz i \(.applicationName)",
                "Börja GPS-runda med \(.applicationName)"
            ],
            shortTitle: "Starta quiz",
            systemImageName: "play.circle"
        )

        AppShortcut(
            intent: ShowLeaderboardIntent(),
            phrases: [
                "Visa topplista i \(.applicationName)",
                "Öppna \(.applicationName) topplista"
            ],
            shortTitle: "Topplista",
            systemImageName: "trophy"
        )
    }
}
