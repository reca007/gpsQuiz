import CoreLocation
import MapKit
import SwiftUI

struct AIQuizGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var locationService: LocationService

    let quiz: Quiz

    @State private var subject = "Naturkunskap"
    @State private var subjectMode = SubjectMode.single
    @State private var selectedAreas: Set<SubjectArea> = [.science]
    @State private var schoolLevel = SchoolLevel.lowerSecondary
    @State private var gradeLevel = "Årskurs 7-9"
    @State private var placeName = "Skolgården"
    @State private var minutes = 30
    @State private var questionCount = 6
    @State private var activationRadius = 60.0
    @State private var latitudeText = "59.3293"
    @State private var longitudeText = "18.0686"
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CourseMapPreview(
                    points: previewPoints,
                    title: "\(questionCount) frågor på \(minutes) minuter",
                    subtitle: "\(displayedSubjectSummary), \(gradeLevel) nära \(placeName)"
                )

                VStack(alignment: .leading, spacing: 14) {
                    Label("Skolämne", systemImage: "books.vertical.fill")
                        .font(.headline)
                    Picker("Nivå", selection: $schoolLevel) {
                        ForEach(SchoolLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: schoolLevel) { _, newValue in
                        subject = newValue.subjects[0]
                        gradeLevel = newValue.defaultGrade
                    }

                    Picker("Ämnesläge", selection: $subjectMode) {
                        ForEach(SubjectMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if subjectMode == .single {
                        Picker("Ämne", selection: $subject) {
                            ForEach(schoolLevel.subjects, id: \.self) { subject in
                                Text(subject).tag(subject)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(SubjectArea.allCases) { area in
                                Toggle(
                                    area.title(for: schoolLevel),
                                    isOn: Binding(
                                        get: { selectedAreas.contains(area) },
                                        set: { isOn in
                                            if isOn {
                                                selectedAreas.insert(area)
                                            } else if selectedAreas.count > 1 {
                                                selectedAreas.remove(area)
                                            }
                                        }
                                    )
                                )
                            }
                        }
                    }

                    Picker("Kursnivå", selection: $gradeLevel) {
                        ForEach(schoolLevel.gradeOptions, id: \.self) { grade in
                            Text(grade).tag(grade)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                .panelStyle()

                VStack(alignment: .leading, spacing: 14) {
                    Label("Plats och bana", systemImage: "map.fill")
                        .font(.headline)
                    TextField("Platsnamn", text: $placeName)
                        .textFieldStyle(.roundedBorder)
                    Stepper("Tid: \(minutes) minuter", value: $minutes, in: 10...120, step: 5)
                    Stepper("Frågor: \(questionCount)", value: $questionCount, in: 1...20)
                    Stepper("Radie: \(Int(activationRadius)) m", value: $activationRadius, in: 20...200, step: 10)

                    Button {
                        useCurrentLocation()
                    } label: {
                        Label("Använd min GPS-position", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    HStack {
                        TextField("Latitud", text: $latitudeText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("Longitud", text: $longitudeText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .panelStyle()

                Button {
                    Task {
                        await generate()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isGenerating {
                            ProgressView()
                        } else {
                            Label("Generera bana", systemImage: "sparkles")
                        }
                        Spacer()
                    }
                    .font(.headline)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating || !canGenerate)

                Text("AI-läget kan kopplas till en backend via GPSQuizAIEndpointURL. Utan backend skapas ett lokalt utkast som går att testa direkt.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .panelStyle()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("AI-bana")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") {
                    dismiss()
                }
            }
        }
        .onAppear {
            useCurrentLocation()
        }
    }

    private var canGenerate: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedSubjectAreas.isEmpty &&
        !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        parsedLatitude != nil &&
        parsedLongitude != nil
    }

    private var currentRequest: GeneratedCourseRequest {
        GeneratedCourseRequest(
            subject: subject,
            subjectAreas: selectedSubjectAreas,
            gradeLevel: gradeLevel,
            placeName: placeName,
            centerLatitude: parsedLatitude ?? 59.3293,
            centerLongitude: parsedLongitude ?? 18.0686,
            minutes: minutes,
            questionCount: questionCount,
            activationRadiusMeters: activationRadius
        )
    }

    private var previewPoints: [CourseMapPoint] {
        AIQuizGenerationService.previewRows(for: currentRequest).map {
            CourseMapPoint(title: $0.name, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var displayedSubjectSummary: String {
        if subjectMode == .single {
            return subject
        }
        return selectedSubjectAreas.joined(separator: " + ")
    }

    private var selectedSubjectAreas: [String] {
        if subjectMode == .single {
            return [subject]
        }

        return SubjectArea.allCases
            .filter { selectedAreas.contains($0) }
            .map { $0.title(for: schoolLevel) }
    }

    private var parsedLatitude: Double? {
        Double(latitudeText.replacingOccurrences(of: ",", with: "."))
    }

    private var parsedLongitude: Double? {
        Double(longitudeText.replacingOccurrences(of: ",", with: "."))
    }

    private func useCurrentLocation() {
        locationService.requestPermission()
        locationService.startTracking()

        guard let coordinate = locationService.currentLocation?.coordinate else { return }
        latitudeText = String(format: "%.6f", coordinate.latitude)
        longitudeText = String(format: "%.6f", coordinate.longitude)
    }

    private func generate() async {
        guard let latitude = parsedLatitude, let longitude = parsedLongitude else { return }

        isGenerating = true
        errorMessage = nil

        do {
            let request = GeneratedCourseRequest(
                subject: subject,
                subjectAreas: selectedSubjectAreas,
                gradeLevel: gradeLevel,
                placeName: placeName,
                centerLatitude: latitude,
                centerLongitude: longitude,
                minutes: minutes,
                questionCount: questionCount,
                activationRadiusMeters: activationRadius
            )
            let rows = try await AIQuizGenerationService.generateRows(for: request)
            append(rows)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    private func append(_ rows: [CheckpointImportRow]) {
        let startIndex = quiz.checkpoints.count

        for (offset, row) in rows.enumerated() {
            let checkpoint = Checkpoint(
                name: row.name,
                latitude: row.latitude,
                longitude: row.longitude,
                activationRadiusMeters: row.radius,
                question: row.question,
                sortIndex: startIndex + offset
            )
            modelContext.insert(checkpoint)
            checkpoint.quiz = quiz

            for (optionIndex, optionText) in row.options.enumerated() {
                let option = AnswerOption(
                    text: optionText,
                    sortIndex: optionIndex,
                    isCorrect: optionText == row.correctAnswer
                )
                modelContext.insert(option)
                option.checkpoint = checkpoint
                checkpoint.options.append(option)
            }

            quiz.checkpoints.append(checkpoint)
        }

        quiz.updatedAt = .now
        try? modelContext.save()
    }
}

private enum SchoolLevel: String, CaseIterable, Identifiable {
    case lowerSecondary
    case upperSecondary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lowerSecondary:
            "Högstadiet"
        case .upperSecondary:
            "Gymnasiet"
        }
    }

    var defaultGrade: String {
        switch self {
        case .lowerSecondary:
            "Årskurs 7-9"
        case .upperSecondary:
            "Gymnasiet"
        }
    }

    var subjects: [String] {
        switch self {
        case .lowerSecondary:
            [
                "Biologi",
                "Engelska",
                "Fysik",
                "Geografi",
                "Historia",
                "Kemi",
                "Matematik",
                "Naturkunskap",
                "Religion",
                "Samhällskunskap",
                "Svenska"
            ]
        case .upperSecondary:
            [
                "Biologi 1",
                "Engelska 5",
                "Engelska 6",
                "Filosofi 1",
                "Fysik 1",
                "Geografi 1",
                "Historia 1b",
                "Kemi 1",
                "Matematik 1c",
                "Matematik 2b",
                "Naturkunskap 1b",
                "Psykologi 1",
                "Religion 1",
                "Samhällskunskap 1b",
                "Svenska 1",
                "Svenska 2"
            ]
        }
    }

    var gradeOptions: [String] {
        switch self {
        case .lowerSecondary:
            ["Årskurs 7", "Årskurs 8", "Årskurs 9", "Årskurs 7-9"]
        case .upperSecondary:
            ["Gymnasiet", "Gymnasiet år 1", "Gymnasiet år 2", "Gymnasiet år 3", "Komvux"]
        }
    }
}

private enum SubjectMode: String, CaseIterable, Identifiable {
    case single
    case combined

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            "Ett ämne"
        case .combined:
            "Kombinera"
        }
    }
}

private enum SubjectArea: String, CaseIterable, Identifiable {
    case math
    case history
    case language
    case science

    var id: String { rawValue }

    func title(for level: SchoolLevel) -> String {
        switch self {
        case .math:
            return level == .upperSecondary ? "Matematik 1-2" : "Matematik"
        case .history:
            return level == .upperSecondary ? "Historia 1b" : "Historia"
        case .language:
            return level == .upperSecondary ? "Språk: Svenska/Engelska" : "Språk: Svenska/Engelska"
        case .science:
            return level == .upperSecondary ? "Naturkunskap/Biologi" : "NO: Natur/Biologi"
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
