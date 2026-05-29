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

    private var activeQuizzes: [Quiz] {
        quizzes.filter(\.isActive)
    }

    var body: some View {
        List {
            Section {
                StartHeroCard(
                    variant: heroVariant,
                    activeCount: activeQuizzes.count,
                    checkpointCount: activeQuizzes.reduce(0) { $0 + $1.checkpoints.count }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if activeQuizzes.isEmpty {
                ContentUnavailableView(
                    "Inga aktiva quiz",
                    systemImage: "mappin.slash",
                    description: Text("Skapa ett quiz och importera många GPS-frågor på en gång.")
                )
            } else {
                Section("Aktiva quiz") {
                    ForEach(activeQuizzes) { quiz in
                        NavigationLink(value: quiz) {
                            QuizRow(quiz: quiz)
                        }
                    }
                    .onDelete(perform: deleteQuiz)
                }
            }

            if !quizzes.filter({ !$0.isActive }).isEmpty {
                Section("Inaktiva") {
                    ForEach(quizzes.filter { !$0.isActive }) { quiz in
                        NavigationLink(value: quiz) {
                            QuizRow(quiz: quiz)
                        }
                    }
                }
            }

            if let message = cloudQuizService.statusMessage {
                Section {
                    Label(message, systemImage: "icloud")
                }
            }
        }
        .navigationTitle("GPSQuiz")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task {
                        await cloudQuizService.importPublishedQuizzes(
                            into: modelContext,
                            existingQuizIDs: Set(quizzes.map(\.id))
                        )
                    }
                } label: {
                    Image(systemName: cloudQuizService.isWorking ? "icloud.and.arrow.down" : "icloud")
                }
                .disabled(cloudQuizService.isWorking)
                .accessibilityLabel("Hämta molnquiz")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Skapa quiz")
            }
        }
        .navigationDestination(for: Quiz.self) { quiz in
            QuizDetailView(quiz: quiz)
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                QuizEditorView()
            }
        }
        .sheet(item: $selectedQuiz) { quiz in
            NavigationStack {
                QuizDetailView(quiz: quiz)
            }
        }
        .onAppear {
            SampleDataService.seedIfNeeded(existingQuizzes: quizzes, modelContext: modelContext)
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
        .onReceive(Timer.publish(every: 7, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.7)) {
                heroVariant = (heroVariant + 1) % 3
            }
        }
    }

    private func deleteQuiz(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(activeQuizzes[index])
        }
    }

    private func openRequestedQuizIfNeeded() {
        guard let quizID = intentRouter.requestedQuizID else { return }
        selectedQuiz = quizzes.first { $0.id == quizID }
        intentRouter.requestedQuizID = nil
    }

    private func importSharedQuizIfNeeded() {
        guard let payload = intentRouter.sharedQuizPayload else { return }

        let quiz = Quiz(title: payload.title, summary: payload.summary, isActive: true)
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

private struct StartHeroCard: View {
    let variant: Int
    let activeCount: Int
    let checkpointCount: Int

    private var hero: (imageName: String, label: String) {
        switch variant {
        case 0:
            ("CityPromenadeHero", "Citypromenad")
        case 1:
            ("ForestTrailHero", "Skogsbana")
        default:
            ("NatureAdventureHero", "Naturbana")
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(hero.imageName)
                .resizable()
                .scaledToFill()
                .transition(.opacity)

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Label(hero.label, systemImage: "location.north.line.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())

                Text("GPSQuiz")
                    .font(.largeTitle.bold())

                Text("\(activeCount) aktiva quiz · \(checkpointCount) checkpoints")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .padding(20)
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
    }
}

private struct CityPromenadeHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.48, green: 0.74, blue: 0.88),
                    Color(red: 0.98, green: 0.86, blue: 0.66)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<9) { index in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(cityBuildingColor(index))
                            .frame(width: CGFloat(36 + (index % 3) * 12), height: CGFloat(72 + (index % 5) * 18))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, 16)

                ZStack(alignment: .top) {
                    Color(red: 0.74, green: 0.63, blue: 0.44)
                    Color(red: 0.17, green: 0.45, blue: 0.62)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 80, topTrailingRadius: 0))
                        .offset(y: 36)
                }
                .frame(height: 95)
            }

            RouteOverlay(points: [
                CGPoint(x: 0.12, y: 0.77),
                CGPoint(x: 0.30, y: 0.65),
                CGPoint(x: 0.48, y: 0.72),
                CGPoint(x: 0.64, y: 0.58),
                CGPoint(x: 0.83, y: 0.64)
            ])
        }
    }

    private func cityBuildingColor(_ index: Int) -> Color {
        [
            Color(red: 0.83, green: 0.39, blue: 0.31),
            Color(red: 0.90, green: 0.65, blue: 0.32),
            Color(red: 0.62, green: 0.34, blue: 0.42),
            Color(red: 0.48, green: 0.63, blue: 0.62)
        ][index % 4]
    }
}

private struct ForestTrailHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.62, green: 0.80, blue: 0.68),
                    Color(red: 0.12, green: 0.32, blue: 0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(0..<13) { index in
                    VStack(spacing: -18) {
                        Triangle()
                            .fill(Color(red: 0.13, green: 0.38, blue: 0.21).opacity(0.72))
                            .frame(width: CGFloat(58 + (index % 4) * 10), height: CGFloat(82 + (index % 5) * 8))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(red: 0.20, green: 0.22, blue: 0.12).opacity(0.65))
                            .frame(width: 10, height: CGFloat(110 + (index % 6) * 18))
                    }
                }
            }
            .padding(.horizontal, -20)

            TrailShape()
                .fill(Color(red: 0.66, green: 0.52, blue: 0.32).opacity(0.95))

            RouteOverlay(points: [
                CGPoint(x: 0.47, y: 0.82),
                CGPoint(x: 0.53, y: 0.65),
                CGPoint(x: 0.51, y: 0.49),
                CGPoint(x: 0.56, y: 0.34)
            ])
        }
    }
}

private struct RouteOverlay: View {
    let points: [CGPoint]

    var body: some View {
        GeometryReader { geometry in
            let resolved = points.map {
                CGPoint(x: $0.x * geometry.size.width, y: $0.y * geometry.size.height)
            }

            Path { path in
                guard let first = resolved.first else { return }
                path.move(to: first)
                for point in resolved.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(Color.blue.opacity(0.86), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))

            Path { path in
                guard let first = resolved.first else { return }
                path.move(to: first)
                for point in resolved.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(.white.opacity(0.58), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            ForEach(Array(resolved.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(.blue)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Circle()
                            .fill(.white.opacity(0.9))
                            .frame(width: 13, height: 13)
                    }
                    .position(point)
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct TrailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.40, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.62, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.width * 0.58, y: rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.45))
        path.closeSubpath()
        return path
    }
}

private struct QuizRow: View {
    let quiz: Quiz

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(quiz.title)
                .font(.headline)
            if !quiz.summary.isEmpty {
                Text(quiz.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Label("\(quiz.checkpoints.count) checkpoints", systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
