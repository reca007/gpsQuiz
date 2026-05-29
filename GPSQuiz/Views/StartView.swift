import SwiftData
import SwiftUI

struct StartView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var intentRouter: IntentRouter
    @EnvironmentObject private var cloudQuizService: CloudQuizService
    @Query(sort: \Quiz.createdAt, order: .reverse) private var quizzes: [Quiz]
    @State private var showingEditor = false
    @State private var selectedQuiz: Quiz?
    @State private var heroVariant = 0
    @State private var accessMode: QuizAccessMode = .player
    @State private var showingTeacherLogin = false
    @State private var teacherCode = ""
    @State private var teacherLoginError: String?
    @AppStorage("gpsquiz.teacherUnlocked") private var isTeacherUnlocked = false

    private var activeQuizzes: [Quiz] {
        quizzes.filter(\.isActive)
    }

    private var inactiveQuizzes: [Quiz] {
        quizzes.filter { !$0.isActive }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StartHeader(
                    accessMode: accessMode,
                    isWorking: cloudQuizService.isWorking,
                    importAction: importCloudQuizzes,
                    createAction: { showingEditor = true }
                )

                RoleSwitcher(
                    accessMode: accessMode,
                    isTeacherUnlocked: isTeacherUnlocked,
                    selectTeacher: selectTeacherMode,
                    selectPlayer: { accessMode = .player }
                )

                StartHeroCard(
                    variant: heroVariant,
                    accessMode: accessMode,
                    activeCount: activeQuizzes.count,
                    checkpointCount: activeQuizzes.reduce(0) { $0 + $1.checkpoints.count }
                )

                if accessMode == .teacher {
                    QuickActionStrip(
                        isWorking: cloudQuizService.isWorking,
                        importAction: importCloudQuizzes,
                        createAction: { showingEditor = true }
                    )
                } else {
                    PlayerJoinCard()
                }

                if let message = cloudQuizService.statusMessage {
                    StatusBanner(message: message)
                }

                if activeQuizzes.isEmpty {
                    EmptyQuizState(accessMode: accessMode, createAction: { showingEditor = true })
                } else {
                    QuizSection(title: "Aktiva quiz", quizzes: activeQuizzes)
                }

                if !inactiveQuizzes.isEmpty {
                    QuizSection(title: "Inaktiva", quizzes: inactiveQuizzes)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 110)
        }
        .background {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.secondarySystemGroupedBackground),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Quiz.self) { quiz in
            QuizDetailView(quiz: quiz, accessMode: accessMode)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                QuizEditorView()
            }
        }
        .sheet(isPresented: $showingTeacherLogin) {
            TeacherLoginSheet(
                code: $teacherCode,
                errorMessage: teacherLoginError,
                unlockAction: unlockTeacherMode
            )
            .presentationDetents([.height(260)])
        }
        .sheet(item: $selectedQuiz) { quiz in
            NavigationStack {
                QuizDetailView(quiz: quiz, accessMode: accessMode)
            }
        }
        .onAppear {
            seedTeacherDemoIfNeeded()
            heroVariant = Calendar.current.component(.minute, from: .now) % 3

            if intentRouter.shouldStartQuiz, let firstQuiz = activeQuizzes.first {
                intentRouter.shouldStartQuiz = false
                // The shortcut lands the user on the active list; starting still requires an explicit player name.
                firstQuiz.updatedAt = .now
            }

            openRequestedQuizIfNeeded()
            importSharedQuizIfNeeded()
        }
        .onChange(of: intentRouter.requestedQuizID) { _, _ in
            openRequestedQuizIfNeeded()
        }
        .onChange(of: intentRouter.sharedQuizPayload) { _, _ in
            importSharedQuizIfNeeded()
        }
        .onChange(of: accessMode) { _, newMode in
            if newMode == .teacher {
                seedTeacherDemoIfNeeded()
            }
        }
        .onReceive(Timer.publish(every: 7, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.7)) {
                heroVariant = (heroVariant + 1) % 3
            }
        }
    }

    private func importCloudQuizzes() {
        guard accessMode == .teacher else { return }

        Task {
            await cloudQuizService.importPublishedQuizzes(
                into: modelContext,
                existingQuizIDs: Set(quizzes.map(\.id))
            )
        }
    }

    private func seedTeacherDemoIfNeeded() {
        guard accessMode == .teacher else { return }
        SampleDataService.seedIfNeeded(existingQuizzes: quizzes, modelContext: modelContext)
    }

    private func selectTeacherMode() {
        if isTeacherUnlocked {
            accessMode = .teacher
        } else {
            teacherCode = ""
            teacherLoginError = nil
            showingTeacherLogin = true
        }
    }

    private func unlockTeacherMode() {
        if teacherCode.trimmingCharacters(in: .whitespacesAndNewlines) == "2468" {
            isTeacherUnlocked = true
            accessMode = .teacher
            showingTeacherLogin = false
            teacherCode = ""
            teacherLoginError = nil
        } else {
            teacherLoginError = "Fel lärarkod."
        }
    }

    private func openRequestedQuizIfNeeded() {
        guard let quizID = intentRouter.requestedQuizID else { return }
        selectedQuiz = quizzes.first { $0.id == quizID }
        intentRouter.requestedQuizID = nil
    }

    private func importSharedQuizIfNeeded() {
        guard let payload = intentRouter.sharedQuizPayload else { return }
        accessMode = .player

        let quiz = Quiz(title: payload.title, summary: payload.summary, isActive: true)
        if let quizID = payload.quizID {
            quiz.id = quizID
        }
        modelContext.insert(quiz)

        for (checkpointIndex, checkpointPayload) in payload.checkpoints.enumerated() {
            let checkpoint = Checkpoint(
                name: checkpointPayload.name,
                latitude: checkpointPayload.latitude,
                longitude: checkpointPayload.longitude,
                activationRadiusMeters: checkpointPayload.radius,
                question: checkpointPayload.question,
                sortIndex: checkpointIndex
            )
            modelContext.insert(checkpoint)
            checkpoint.quiz = quiz

            for (optionIndex, optionPayload) in checkpointPayload.options.enumerated() {
                let option = AnswerOption(
                    text: optionPayload.text,
                    sortIndex: optionIndex,
                    isCorrect: optionPayload.isCorrect
                )
                modelContext.insert(option)
                option.checkpoint = checkpoint
                checkpoint.options.append(option)
            }

            quiz.checkpoints.append(checkpoint)
        }

        try? modelContext.save()
        selectedQuiz = quiz
        intentRouter.sharedQuizPayload = nil
    }
}

private struct StartHeader: View {
    let accessMode: QuizAccessMode
    let isWorking: Bool
    let importAction: () -> Void
    let createAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("GPSQuiz")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text(accessMode == .teacher ? "Skapa banor och dela dem med spelare." : "Anslut till lärarens bana och starta som lag.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                if accessMode == .teacher {
                    CircleIconButton(
                        systemImage: isWorking ? "arrow.down.circle" : "network",
                        title: "Hämta Render-quiz",
                        action: importAction
                    )
                    .disabled(isWorking)

                    CircleIconButton(
                        systemImage: "plus",
                        title: "Skapa quiz",
                        action: createAction
                    )
                } else {
                    Image(systemName: "person.2.badge.key.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 46, height: 46)
                        .background(.regularMaterial, in: Circle())
                }
            }
        }
    }
}

private struct RoleSwitcher: View {
    let accessMode: QuizAccessMode
    let isTeacherUnlocked: Bool
    let selectTeacher: () -> Void
    let selectPlayer: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            RoleButton(
                title: "Spelare",
                systemImage: "person.2.fill",
                isSelected: accessMode == .player,
                action: selectPlayer
            )

            RoleButton(
                title: isTeacherUnlocked ? "Lärare" : "Lärare låst",
                systemImage: isTeacherUnlocked ? "graduationcap.fill" : "lock.fill",
                isSelected: accessMode == .teacher,
                action: selectTeacher
            )
        }
        .padding(4)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RoleButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? .white : .primary)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.blue)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct TeacherLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var code: String
    let errorMessage: String?
    let unlockAction: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Lärarkod", text: $code)
                        .keyboardType(.numberPad)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Demo-kod: 2468. Spelare behöver inte koden och kan bara ansluta till quizrundan.")
                }
            }
            .navigationTitle("Lås upp lärarläge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Lås upp", action: unlockAction)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct StartHeroCard: View {
    let variant: Int
    let accessMode: QuizAccessMode
    let activeCount: Int
    let checkpointCount: Int

    private var hero: (imageName: String, label: String, subtitle: String) {
        switch variant {
        case 0:
            ("CityPromenadeHero", "Citypromenad", "Uppdrag genom stadsmiljö")
        case 1:
            ("ForestTrailHero", "Skogsbana", "Frågor längs stig och skog")
        default:
            ("NatureAdventureHero", "Naturbana", "Utforska platsen med laget")
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(hero.imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .transition(.opacity)

            LinearGradient(
                colors: [
                    .black.opacity(0.00),
                    .black.opacity(0.18),
                    .black.opacity(0.76)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 14) {
                Label(hero.label, systemImage: "location.north.line.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())

                VStack(alignment: .leading, spacing: 6) {
                    Text(hero.subtitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)

                    Text(accessMode == .teacher ? "\(activeCount) aktiva quiz · \(checkpointCount) checkpoints" : "Skanna QR-koden från läraren och anslut till rundan.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .padding(24)
        }
        .frame(height: 430)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.26), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, y: 14)
    }
}

private struct PlayerJoinCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Spelarläge", systemImage: "qrcode.viewfinder")
                .font(.headline.weight(.semibold))

            Text("Spelare kan inte skapa, ändra eller se frågorna i förväg. De ansluter via lärarens QR-kod eller länk och fyller i två spelare i laget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct QuickActionStrip: View {
    let isWorking: Bool
    let importAction: () -> Void
    let createAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ActionPill(
                title: "Ny bana",
                subtitle: "AI eller egen",
                systemImage: "sparkles",
                tint: .blue,
                action: createAction
            )

            ActionPill(
                title: "Render-quiz",
                subtitle: isWorking ? "Hämtar..." : "Hämta",
                systemImage: "network",
                tint: .teal,
                action: importAction
            )
            .disabled(isWorking)
        }
    }
}

private struct QuizSection: View {
    let title: String
    let quizzes: [Quiz]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))

            ForEach(quizzes) { quiz in
                NavigationLink(value: quiz) {
                    QuizCard(quiz: quiz)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct QuizCard: View {
    let quiz: Quiz

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.14))
                Image(systemName: "map.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(quiz.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)

                if !quiz.summary.isEmpty {
                    Text(quiz.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Label("\(quiz.checkpoints.count) checkpoints", systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct ActionPill: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.headline.bold())
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: Circle())
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CircleIconButton: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .frame(width: 46, height: 46)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct StatusBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "network")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct EmptyQuizState: View {
    let accessMode: QuizAccessMode
    let createAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(accessMode == .teacher ? "Inga aktiva quiz" : "Ingen bana ansluten", systemImage: "mappin.slash")
                .font(.headline)

            Text(accessMode == .teacher ? "Skapa ett quiz och importera många GPS-frågor på en gång." : "Be läraren visa QR-koden eller dela länken till quizrundan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if accessMode == .teacher {
                Button(action: createAction) {
                    Label("Skapa första banan", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct StartView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            StartView()
        }
        .modelContainer(PreviewSupport.modelContainer)
        .environmentObject(IntentRouter())
        .environmentObject(CloudQuizService())
    }
}
