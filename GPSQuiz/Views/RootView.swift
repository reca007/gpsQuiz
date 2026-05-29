import SwiftData
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var intentRouter: IntentRouter

    var body: some View {
        TabView(selection: $intentRouter.selectedTab) {
            NavigationStack {
                StartView()
            }
            .tabItem {
                Label("Quiz", systemImage: "location.circle")
            }
            .tag(AppTab.quizzes)

            NavigationStack {
                LeaderboardView()
            }
            .tabItem {
                Label("Topplista", systemImage: "trophy")
            }
            .tag(AppTab.leaderboard)
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .modelContainer(PreviewSupport.modelContainer)
            .environmentObject(LocationService())
            .environmentObject(LeaderboardService())
            .environmentObject(CloudQuizService())
            .environmentObject(IntentRouter())
    }
}
